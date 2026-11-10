#!/usr/bin/env bats
# Contract test for the third-party repository gate.
#
# The gate is the build's last line of defence against shipping an image with
# an outside software source switched on. It lives in build/90-cleanup.sh, in
# the same cleanup RUN that disables third-party repositories, so it re-checks
# the post-cleanup state. It asks dnf which repositories are actually enabled
# rather than pattern-matching the .repo files (a repository that ships with no
# enabled= key is enabled by dnf's default and would slip past a grep).
#
# Run with: bats tests/contract/repository-gate_test.bats

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
CLEANUP_SRC="${SCRIPT_DIR}/../../build/90-cleanup.sh"

setup() {
	[ -f "${CLEANUP_SRC}" ]
}

@test "the gate lives in build/90-cleanup.sh, after the disable pass" {
	disable_idx="$(grep -n 'disable_repo_file' "${CLEANUP_SRC}" | head -1 | cut -d: -f1)"
	gate_idx="$(grep -n 'dnf5 -q repo list --enabled' "${CLEANUP_SRC}" | head -1 | cut -d: -f1)"
	[ -n "${disable_idx}" ]
	[ -n "${gate_idx}" ]
	[ "${gate_idx}" -gt "${disable_idx}" ]
}

@test "the gate asks dnf which repositories are enabled" {
	# The header dnf prints (Id State Name) is skipped by content, not by line
	# number, so a copr: repository that sorts first is still caught.
	grep -qF 'dnf5 -q repo list --enabled' "${CLEANUP_SRC}"
	grep -qF '$1 == "repo" && $2 == "id"' "${CLEANUP_SRC}"
}

@test "the gate allowlists only exact Fedora repository ids" {
	grep -qF 'split("fedora updates fedora-updates fedora-cisco-openh264 fedora-updates-archive updates-archive"' "${CLEANUP_SRC}"
	! grep -qF "grep -vE '^(fedora|updates)'" "${CLEANUP_SRC}"
}

@test "the gate fails the build when the dnf query fails" {
	grep -qF 'could not query enabled repositories' "${CLEANUP_SRC}"
}

@test "the gate fails the build on a leaked repository" {
	grep -qF 'exit 1' "${CLEANUP_SRC}"
	grep -qF 'third-party repository still enabled' "${CLEANUP_SRC}"
}
