#!/usr/bin/env bats
#
# Unit tests for the `sbom` recipe in the repository Justfile, and for the
# wiring that makes main's build and the PR image build run that same recipe
# (#686).
#
# The recipe is exercised through the real `just` binary inside a sandbox
# directory that contains only a copy of the Justfile. `podman` and `syft` are
# PATH stubs that record their argv, so no container engine or scanner is
# required and nothing outside the sandbox is touched.

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	SANDBOX="$(mktemp -d)"
	STUB_BIN="${SANDBOX}/stub-bin"
	mkdir -p "${STUB_BIN}"

	cp "${REPO_ROOT}/Justfile" "${SANDBOX}/Justfile"

	CALL_LOG="${SANDBOX}/calls.log"
	: >"${CALL_LOG}"

	# podman stub: logs argv; `image mount` prints a mount path.
	cat >"${STUB_BIN}/podman" <<'STUB'
#!/usr/bin/env bash
printf 'podman %s\n' "$*" >>"${CALL_LOG}"
if [[ "${1:-}" == "image" && "${2:-}" == "mount" ]]; then
	printf '/var/lib/containers/storage/overlay/abc/merged\n'
fi
exit 0
STUB
	chmod +x "${STUB_BIN}/podman"

	# syft stub: logs argv and writes the -o spdx-json=<file> target, unless
	# SYFT_STUB_FAIL is set.
	cat >"${STUB_BIN}/syft" <<'STUB'
#!/usr/bin/env bash
printf 'syft %s\n' "$*" >>"${CALL_LOG}"
[[ -n "${SYFT_STUB_FAIL:-}" ]] && exit 3
prev=""
for arg in "$@"; do
	if [[ "${prev}" == "-o" ]]; then
		printf '{"packages":[]}\n' >"${arg#spdx-json=}"
	fi
	prev="${arg}"
done
exit 0
STUB
	chmod +x "${STUB_BIN}/syft"

	export CALL_LOG
	export PATH="${STUB_BIN}:${PATH}"
	unset SYFT SYFT_STUB_FAIL
}

teardown() {
	rm -rf "${SANDBOX}"
}

run_sbom() {
	run just --justfile "${SANDBOX}/Justfile" --working-directory "${SANDBOX}" \
		sbom "$@"
}

@test "sbom: mounts the localhost image, scans the mount as a directory, unmounts" {
	run_sbom finpilot stable out
	[ "$status" -eq 0 ]
	grep -Fxq 'podman image mount localhost/finpilot:stable' "${CALL_LOG}"
	grep -Fxq 'syft dir:/var/lib/containers/storage/overlay/abc/merged --source-name finpilot --source-version stable --parallelism 1 --override-default-catalogers rpm-db-cataloger -o spdx-json=out/finpilot.sbom.json' "${CALL_LOG}"
	grep -Fxq 'podman image unmount localhost/finpilot:stable' "${CALL_LOG}"
	[ -s "${SANDBOX}/out/finpilot.sbom.json" ]
}

@test "sbom: scans in order mount, syft, unmount" {
	run_sbom finpilot stable out
	[ "$status" -eq 0 ]
	[ "$(sed -n 1p "${CALL_LOG}")" = 'podman image mount localhost/finpilot:stable' ]
	[[ "$(sed -n 2p "${CALL_LOG}")" == syft\ dir:* ]]
	[ "$(sed -n 3p "${CALL_LOG}")" = 'podman image unmount localhost/finpilot:stable' ]
}

@test "sbom: unmounts and fails when the scan fails" {
	SYFT_STUB_FAIL=1 run_sbom finpilot stable out
	[ "$status" -ne 0 ]
	grep -Fxq 'podman image unmount localhost/finpilot:stable' "${CALL_LOG}"
}

@test "sbom: does not use syft's podman: source (it needs a Podman socket, #683)" {
	run_sbom finpilot stable out
	[ "$status" -eq 0 ]
	run grep -F 'podman:' "${CALL_LOG}"
	[ "$status" -ne 0 ]
}

@test "sbom: runs the binary named by SYFT" {
	cp "${STUB_BIN}/syft" "${SANDBOX}/my-syft"
	sed -i 's/^printf .syft /printf '"'"'my-syft /' "${SANDBOX}/my-syft"
	SYFT="${SANDBOX}/my-syft" run_sbom finpilot stable out
	[ "$status" -eq 0 ]
	grep -q '^my-syft dir:' "${CALL_LOG}"
	run grep -q '^syft ' "${CALL_LOG}"
	[ "$status" -ne 0 ]
}

@test "sbom: defaults to IMAGE_NAME, DEFAULT_TAG and sbom-current" {
	run_sbom
	[ "$status" -eq 0 ]
	grep -Fxq 'podman image mount localhost/finpilot:stable' "${CALL_LOG}"
	[ -s "${SANDBOX}/sbom-current/finpilot.sbom.json" ]
}

@test "wiring: build-image.yml and pr-build.yml both scan through the sbom recipe" {
	grep -Eq 'just\)" sbom' "${REPO_ROOT}/.github/workflows/build-image.yml"
	grep -Eq 'just\)" sbom' "${REPO_ROOT}/.github/workflows/pr-build.yml"
}

@test "wiring: no workflow calls syft directly (the command lives in the recipe)" {
	run grep -En '"dir:|"podman:|override-default-catalogers' \
		"${REPO_ROOT}/.github/workflows/build-image.yml" \
		"${REPO_ROOT}/.github/workflows/pr-build.yml"
	[ "$status" -ne 0 ]
}

@test "wiring: the PR image build treats build-image.yml as a build input" {
	grep -Fq '.github/workflows/build-image.yml)' "${REPO_ROOT}/.github/workflows/pr-build.yml"
}
