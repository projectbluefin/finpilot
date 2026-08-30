#!/usr/bin/env bats
#
# Unit tests for the `tag-images` recipe in the repository Justfile.
#
# The recipe is exercised through the real `just` binary inside a sandbox
# directory that contains only a copy of the Justfile. Every external command
# it reaches for (`podman`) is a PATH stub that records its argv, so no
# container engine is required and nothing outside the sandbox is touched.

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	SANDBOX="$(mktemp -d)"
	STUB_BIN="${SANDBOX}/stub-bin"
	mkdir -p "${STUB_BIN}"

	cp "${REPO_ROOT}/Justfile" "${SANDBOX}/Justfile"

	PODMAN_LOG="${SANDBOX}/podman.log"
	: >"${PODMAN_LOG}"

	# Default podman stub: logs argv, answers `inspect` with a manifest that
	# carries a known image Id, succeeds for everything else.
	cat >"${STUB_BIN}/podman" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${PODMAN_LOG}"
if [[ "${1:-}" == "inspect" ]]; then
	printf '[{"Id":"sha256:deadbeef"}]\n'
fi
exit 0
STUB
	chmod +x "${STUB_BIN}/podman"

	export PODMAN_LOG
	export PATH="${STUB_BIN}:${PATH}"
}

teardown() {
	rm -rf "${SANDBOX}"
}

run_tag_images() {
	run just --justfile "${SANDBOX}/Justfile" --working-directory "${SANDBOX}" \
		tag-images "$@"
}

podman_calls() {
	cat "${PODMAN_LOG}"
}

@test "tag-images: rejects a missing image name" {
	run_tag_images "" stable "t1 t2"
	[ "$status" -eq 1 ]
	[[ "$output" == *"Usage: just tag-images <image_name> <default_tag> <tags>"* ]]
	[ ! -s "${PODMAN_LOG}" ]
}

@test "tag-images: rejects a missing default tag" {
	run_tag_images finpilot "" "t1 t2"
	[ "$status" -eq 1 ]
	[[ "$output" == *"Usage: just tag-images"* ]]
	[ ! -s "${PODMAN_LOG}" ]
}

@test "tag-images: rejects an empty tag list" {
	run_tag_images finpilot stable ""
	[ "$status" -eq 1 ]
	[[ "$output" == *"Usage: just tag-images"* ]]
	[ ! -s "${PODMAN_LOG}" ]
}

@test "tag-images: rejects invocation with no arguments at all" {
	run_tag_images
	[ "$status" -eq 1 ]
	[[ "$output" == *"Usage: just tag-images"* ]]
	[ ! -s "${PODMAN_LOG}" ]
}

@test "tag-images: resolves the image id from the localhost-qualified default tag" {
	run_tag_images finpilot stable "stable-42 latest"
	[ "$status" -eq 0 ]
	podman_calls | grep -Fxq 'inspect localhost/finpilot:stable'
}

@test "tag-images: untags the localhost default reference before re-tagging" {
	run_tag_images finpilot stable "stable-42"
	[ "$status" -eq 0 ]

	local untag_line tag_line
	untag_line="$(grep -n '^untag ' "${PODMAN_LOG}" | head -n1 | cut -d: -f1)"
	tag_line="$(grep -n '^tag ' "${PODMAN_LOG}" | head -n1 | cut -d: -f1)"
	[ -n "${untag_line}" ]
	[ -n "${tag_line}" ]
	[ "${untag_line}" -lt "${tag_line}" ]
	podman_calls | grep -Fxq 'untag localhost/finpilot:stable'
}

@test "tag-images: applies every tag in the whitespace-separated list" {
	run_tag_images finpilot stable "stable-42 stable-42.20250101 latest"
	[ "$status" -eq 0 ]
	podman_calls | grep -Fxq 'tag sha256:deadbeef finpilot:stable-42'
	podman_calls | grep -Fxq 'tag sha256:deadbeef finpilot:stable-42.20250101'
	podman_calls | grep -Fxq 'tag sha256:deadbeef finpilot:latest'
}

@test "tag-images: re-applies the default tag so local lookups keep working" {
	run_tag_images finpilot stable "latest"
	[ "$status" -eq 0 ]
	podman_calls | grep -Fxq 'tag sha256:deadbeef finpilot:stable'

	# The default tag is restored last, after every alias tag.
	local last_tag
	last_tag="$(grep '^tag ' "${PODMAN_LOG}" | tail -n1)"
	[ "${last_tag}" = 'tag sha256:deadbeef finpilot:stable' ]
}

@test "tag-images: alias tags are unqualified (no localhost/ prefix)" {
	run_tag_images finpilot stable "latest"
	[ "$status" -eq 0 ]
	run grep -c '^tag sha256:deadbeef localhost/' "${PODMAN_LOG}"
	[ "$status" -ne 0 ]
}

@test "tag-images: a single tag produces exactly two tag calls (alias + default)" {
	run_tag_images finpilot stable "latest"
	[ "$status" -eq 0 ]
	[ "$(grep -c '^tag ' "${PODMAN_LOG}")" -eq 2 ]
}

@test "tag-images: collapses repeated whitespace in the tag list" {
	run_tag_images finpilot stable "  latest   stable-42  "
	[ "$status" -eq 0 ]
	[ "$(grep -c '^tag ' "${PODMAN_LOG}")" -eq 3 ]
	podman_calls | grep -Fxq 'tag sha256:deadbeef finpilot:latest'
	podman_calls | grep -Fxq 'tag sha256:deadbeef finpilot:stable-42'
}

@test "tag-images: reports the tags it applied" {
	run_tag_images finpilot stable "latest stable-42"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Tagged finpilot with: latest stable-42"* ]]
}

@test "tag-images: honours a PODMAN override from the environment" {
	cat >"${STUB_BIN}/docker-shim" <<'STUB'
#!/usr/bin/env bash
printf 'shim %s\n' "$*" >>"${PODMAN_LOG}"
if [[ "${1:-}" == "inspect" ]]; then
	printf '[{"Id":"sha256:cafe"}]\n'
fi
exit 0
STUB
	chmod +x "${STUB_BIN}/docker-shim"

	PODMAN=docker-shim run_tag_images finpilot stable "latest"
	[ "$status" -eq 0 ]
	podman_calls | grep -Fxq 'shim inspect localhost/finpilot:stable'
	podman_calls | grep -Fxq 'shim tag sha256:cafe finpilot:latest'
	run grep -c '^inspect ' "${PODMAN_LOG}"
	[ "$status" -ne 0 ]
}

@test "tag-images: fails when the image cannot be inspected" {
	cat >"${STUB_BIN}/podman" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${PODMAN_LOG}"
if [[ "${1:-}" == "inspect" ]]; then
	echo "Error: no such object" >&2
	exit 125
fi
exit 0
STUB
	chmod +x "${STUB_BIN}/podman"

	run_tag_images finpilot stable "latest"
	[ "$status" -ne 0 ]
	# No tagging is attempted once the id lookup fails.
	run grep -c '^tag ' "${PODMAN_LOG}"
	[ "$status" -ne 0 ]
	run grep -c '^untag ' "${PODMAN_LOG}"
	[ "$status" -ne 0 ]
}

@test "tag-images: fails when untagging the default reference fails" {
	cat >"${STUB_BIN}/podman" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${PODMAN_LOG}"
if [[ "${1:-}" == "inspect" ]]; then
	printf '[{"Id":"sha256:deadbeef"}]\n'
	exit 0
fi
if [[ "${1:-}" == "untag" ]]; then
	echo "Error: untag failed" >&2
	exit 125
fi
exit 0
STUB
	chmod +x "${STUB_BIN}/podman"

	run_tag_images finpilot stable "latest"
	[ "$status" -ne 0 ]
	run grep -c '^tag ' "${PODMAN_LOG}"
	[ "$status" -ne 0 ]
}

@test "tag-images: fails when applying an alias tag fails" {
	cat >"${STUB_BIN}/podman" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${PODMAN_LOG}"
if [[ "${1:-}" == "inspect" ]]; then
	printf '[{"Id":"sha256:deadbeef"}]\n'
	exit 0
fi
if [[ "${1:-}" == "tag" ]]; then
	echo "Error: tag failed" >&2
	exit 125
fi
exit 0
STUB
	chmod +x "${STUB_BIN}/podman"

	run_tag_images finpilot stable "latest stable-42"
	[ "$status" -ne 0 ]
	# Aborts on the first failing tag rather than continuing the loop.
	[ "$(grep -c '^tag ' "${PODMAN_LOG}")" -eq 1 ]
}
