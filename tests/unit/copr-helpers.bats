#!/usr/bin/env bats
# Unit tests for build/copr-helpers.sh :: copr_install_isolated

setup() {
	load 'helpers/stub'
	setup_sandbox
	HELPERS="${REPO_ROOT}/build/copr-helpers.sh"
	export HELPERS
	stub_command dnf5
}

# Runs copr_install_isolated with the given arguments in a subshell so the
# helper's `set -euo pipefail` never leaks into the BATS process.
call_helper() {
	run bash -c 'source "${HELPERS}"; copr_install_isolated "$@"' _ "$@"
}

@test "copr_install_isolated fails when no packages are given" {
	call_helper "ublue-os/staging"
	[ "$status" -eq 1 ]
	[[ "$output" == *"No packages specified for copr_install_isolated"* ]]
	run stub_log_contains "dnf5"
	[ "$status" -ne 0 ]
}

@test "copr_install_isolated enables then disables the copr before installing" {
	call_helper "ublue-os/staging" "hello"
	[ "$status" -eq 0 ]
	run cat "${STUB_LOG}"
	[ "${lines[0]}" = "dnf5 -y copr enable ublue-os/staging" ]
	[ "${lines[1]}" = "dnf5 -y copr disable ublue-os/staging" ]
	[[ "${lines[2]}" == "dnf5 -y install --enablerepo="* ]]
}

@test "copr_install_isolated derives the repo id from the copr name" {
	call_helper "ublue-os/staging" "hello"
	[ "$status" -eq 0 ]
	run stub_log_contains "--enablerepo=copr:copr.fedorainfracloud.org:ublue-os:staging"
	[ "$status" -eq 0 ]
}

@test "copr_install_isolated replaces every slash in the copr name" {
	call_helper "owner/project/extra" "hello"
	[ "$status" -eq 0 ]
	run stub_log_contains "--enablerepo=copr:copr.fedorainfracloud.org:owner:project:extra"
	[ "$status" -eq 0 ]
}

@test "copr_install_isolated installs every requested package in one call" {
	call_helper "ublue-os/staging" "pkg-a" "pkg-b" "pkg-c"
	[ "$status" -eq 0 ]
	run stub_log_contains "install --enablerepo=copr:copr.fedorainfracloud.org:ublue-os:staging pkg-a pkg-b pkg-c"
	[ "$status" -eq 0 ]
}

@test "copr_install_isolated reports which packages it installed" {
	call_helper "ublue-os/staging" "pkg-a" "pkg-b"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Installing pkg-a pkg-b from COPR ublue-os/staging (isolated)"* ]]
	[[ "$output" == *"Installed pkg-a pkg-b from ublue-os/staging"* ]]
}

@test "copr_install_isolated propagates a dnf5 install failure" {
	stub_command dnf5 1
	call_helper "ublue-os/staging" "pkg-a"
	[ "$status" -ne 0 ]
}
