#!/usr/bin/env bats
# Regression test for finpilot #681: the release SBOM must be bound to the
# exact promoted image digest, not selected as "the newest successful build".
#
# The release workflow (release-from-build.yml) iterates the successful runs of
# build-image.yml newest-first and downloads each run's `sbom-finpilot`
# artifact, keeping the first whose recorded image digest matches the promoted
# digest. The failure this fixes: image A is promoted and released; a later
# image B builds successfully (so it sorts first); if the run selected "newest"
# it would attach B's package inventory to A's release. The loop must instead
# keep A, and must fail before publication if no run's artifact carries A's
# digest.
#
# The selection `run:` block is extracted from the workflow (to a temp file, so
# the tests execute the script the workflow executes instead of a copy that can
# drift) and run for real, with a stub `gh` on PATH that simulates two
# successful build runs. Nothing here touches the network.
#
# Run with: bats tests/contract/sbom-digest-binding_test.bats

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
WORKFLOW="${REPO_ROOT}/.github/workflows/release-from-build.yml"
SCRIPT="${BATS_TEST_TMPDIR}/selection.sh"

# Lift the "Find build artifact for the promoted digest" step's `run: |` block
# out of the workflow and dedent it.
extract_run_block() {
	awk '
		!grab && $0 ~ /Find build artifact for the promoted digest/ { looking = 1 }
		looking && !grab && /run: *\|/ { grab = 1; match($0, /^[ ]*/); base = RLENGTH; next }
		grab {
			if ($0 ~ /^[ ]*$/) { print ""; next }
			match($0, /^[ ]*/); cur = RLENGTH
			if (cur <= base) { exit }
			if (dedent == 0) { dedent = cur }
			print substr($0, dedent + 1)
		}
	' "${WORKFLOW}"
}

# Build a stub `gh` for a scenario. $1 = output dir, $2 = A digest, $3 = B
# digest, $4 = "ok" or "a-missing". It lists two successful runs (B newest
# first, then A) and, on download, writes the run's own digest into
# <dir>/image-digest (or fails to download when A's artifact is missing). The
# digests and behavior are injected via environment so the stub body stays a
# static, single-quoted heredoc with no shell escaping to get wrong.
make_gh_stub() {
	local dir="$1" a_digest="$2" b_digest="$3" behavior="$4"
	cat >"${dir}/gh" <<'EOF'
#!/bin/bash
if [[ "${1}" == "run" && "${2}" == "list" ]]; then
  printf '%s' '[{"databaseId":200},{"databaseId":100}]'
  exit 0
fi
if [[ "${1}" == "run" && "${2}" == "download" ]]; then
  run_id="${3}"
  dir="${!#}"
  mkdir -p "${dir}"
  if [[ "${STUB_BEHAVIOR}" == "a-missing" ]]; then
    echo "artifact \"sbom-finpilot\" for run ${run_id} not found" >&2
    exit 2
  fi
  if [[ "${run_id}" == "100" ]]; then
    printf '%s\n' "${STUB_A_DIGEST}" > "${dir}/image-digest"
  else
    printf '%s\n' "${STUB_B_DIGEST}" > "${dir}/image-digest"
  fi
  exit 0
fi
echo "unexpected gh call: $*" >&2
exit 2
EOF
	chmod +x "${dir}/gh"
}

# Build a stub `skopeo` that reports the promoted digest for any
# `skopeo inspect` call, driven by STUB_PROMOTED_DIGEST. The selection script
# resolves the promoted digest this way (skopeo inspect docker://IMAGE:STREAM).
make_skopeo_stub() {
	local dir="$1"
	cat >"${dir}/skopeo" <<'EOF'
#!/bin/bash
printf '%s\n' "${STUB_PROMOTED_DIGEST}"
EOF
	chmod +x "${dir}/skopeo"
}

A_DIGEST="sha256:$(printf 'a%.0s' {1..64})"
B_DIGEST="sha256:$(printf 'b%.0s' {1..64})"

setup() {
	[ -f "${WORKFLOW}" ]
	extract_run_block >"${SCRIPT}"
	[ -s "${SCRIPT}" ]
	grep -q 'EXPECTED_DIGEST' "${SCRIPT}"
}

@test "the workflow selects the SBOM by promoted digest, not newest run" {
	grep -q 'image-digest' "${WORKFLOW}"
	grep -q 'EXPECTED_DIGEST' "${WORKFLOW}"
	! grep -q 'gh run list.*--limit 1' "${WORKFLOW}"
	# The promoted digest is resolved in-workflow via skopeo on :stable, so the
	# release does not depend on an output the execute job never forwards.
	grep -q 'skopeo inspect' "${WORKFLOW}"
	! grep -q 'promoted_digests' "${WORKFLOW}"
	! grep -q 'build_digest' "${WORKFLOW}"
	! grep -q 'needs.execute.outputs' "${WORKFLOW}"
}

@test "with B newest and A promoted, the loop still selects A" {
	local bin; bin="$(mktemp -d)"
	make_gh_stub "${bin}" "${A_DIGEST}" "${B_DIGEST}" "ok"
	make_skopeo_stub "${bin}"

	local gh_output; gh_output="$(mktemp)"
	local run_id
	# skopeo reports the promoted digest (A); gh lists B newest first, then A.
	run_id="$(env STUB_PROMOTED_DIGEST="${A_DIGEST}" STUB_A_DIGEST="${A_DIGEST}" STUB_B_DIGEST="${B_DIGEST}" STUB_BEHAVIOR="ok" PATH="${bin}:${PATH}" GH_TOKEN=test GITHUB_OUTPUT="${gh_output}" BUILD_WORKFLOW=build-image.yml BUILD_BRANCH=main REPOSITORY=projectbluefin/finpilot IMAGE=ghcr.io/projectbluefin/finpilot STREAM_NAME=stable SBOM_ARTIFACT=sbom-finpilot bash "${SCRIPT}" 2>/dev/null)"
	run_id="$(sed -n 's/^run_id=//p' "${gh_output}")"

	[ "${run_id}" = "100" ]
}

@test "the release fails before publication when no run carries the promoted digest" {
	local bin; bin="$(mktemp -d)"
	make_gh_stub "${bin}" "${A_DIGEST}" "${B_DIGEST}" "a-missing"
	make_skopeo_stub "${bin}"

	local gh_output; gh_output="$(mktemp)"
	local out; local status=0
	# skopeo reports the promoted digest (A), but no run's artifact can be
	# downloaded, so the loop must fail loudly before publication.
	if out="$(env STUB_PROMOTED_DIGEST="${A_DIGEST}" STUB_A_DIGEST="${A_DIGEST}" STUB_B_DIGEST="${B_DIGEST}" STUB_BEHAVIOR="a-missing" PATH="${bin}:${PATH}" GH_TOKEN=test GITHUB_OUTPUT="${gh_output}" BUILD_WORKFLOW=build-image.yml BUILD_BRANCH=main REPOSITORY=projectbluefin/finpilot IMAGE=ghcr.io/projectbluefin/finpilot STREAM_NAME=stable SBOM_ARTIFACT=sbom-finpilot bash "${SCRIPT}" 2>&1)"; then
		status=0
	else
		status=$?
	fi

	[ "${status}" -eq 1 ]
	[[ "${out}" == *"No retained SBOM matches promoted digest"* ]]
}
