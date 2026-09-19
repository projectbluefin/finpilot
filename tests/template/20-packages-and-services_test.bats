#!/usr/bin/env bats
# Unit tests for build/20-packages-and-services.sh.
#
# This phase owns RPM and COPR installation, so the tests assert what it
# installs and the boundary around it: filesystem overlays and their units
# belong to 10-overlay.sh. The script sources /ctx/build/copr-helpers.sh, so
# each test rewrites a throwaway copy to point at a sandbox context and stubs
# dnf5, systemctl and rsync.
#
# Run with: bats tests/template/20-packages-and-services_test.bats

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_SRC="${REPO_ROOT}/build/20-packages-and-services.sh"

setup() {
	TEST_ROOT="${BATS_TEST_TMPDIR:-${BATS_TMPDIR}}/20-packages.${BATS_TEST_NUMBER:-0}.$$"
	CTX="${TEST_ROOT}/ctx"
	STUB_BIN="${TEST_ROOT}/stub-bin"
	SCRIPT="${TEST_ROOT}/20-packages-and-services.sh"

	DNF5_LOG="${TEST_ROOT}/logs/dnf5.log"
	SYSTEMCTL_LOG="${TEST_ROOT}/logs/systemctl.log"
	RSYNC_LOG="${TEST_ROOT}/logs/rsync.log"

	mkdir -p "${STUB_BIN}" "${TEST_ROOT}/logs" "${CTX}/build"

	# The real helper library is sourced verbatim so a syntax break there fails
	# this suite too.
	cp "${REPO_ROOT}/build/copr-helpers.sh" "${CTX}/build/copr-helpers.sh"

	sed -e "s#/ctx/#${CTX}/#g" "${BUILD_SRC}" >"${SCRIPT}"

	export PATH="${STUB_BIN}:${PATH}"
	export DNF5_LOG SYSTEMCTL_LOG RSYNC_LOG

	for tool in dnf5 systemctl rsync; do
		local log_var
		log_var="$(printf '%s' "${tool}" | tr '[:lower:]' '[:upper:]')_LOG"
		cat >"${STUB_BIN}/${tool}" <<EOF
#!/usr/bin/bash
printf '%s\n' "\$*" >> "\${${log_var}}"
exit 0
EOF
		chmod +x "${STUB_BIN}/${tool}"
	done
}

teardown() {
	rm -rf "${TEST_ROOT}"
}

@test "20-packages-and-services: sandbox rewrite left no writes to the host filesystem" {
	# Guards the rewrite above: if the script's paths change, the sed no longer
	# matches and the suite would exec the real package provider.
	run grep -nE '(^|[^-[:alnum:]])/ctx/' "${SCRIPT}"
	[ "$status" -ne 0 ]

	grep -q "source ${CTX}/build/copr-helpers.sh" "${SCRIPT}"
}

@test "20-packages-and-services: completes successfully" {
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]
}

@test "20-packages-and-services: emits GitHub Actions group markers" {
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"::group:: Install Default Packages"* ]]
	[[ "$output" == *"::group:: Install uupd"* ]]
	[[ "$output" == *"::group:: Enable update services"* ]]
	[[ "$output" == *"::endgroup::"* ]]
}

@test "20-packages-and-services: installs the default packages in one dnf5 call" {
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]

	mapfile -t calls <"${DNF5_LOG}"
	[ "${calls[0]}" = "install -y just gum fzf jq" ]
}

@test "20-packages-and-services: installs uupd from its COPR in isolation" {
	# copr_install_isolated enables the repo, disables it again, then installs
	# with a one-shot --enablerepo, so no COPR file persists enabled.
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]

	mapfile -t calls <"${DNF5_LOG}"
	[ "${#calls[@]}" -eq 4 ]
	[ "${calls[1]}" = "-y copr enable ublue-os/packages" ]
	[ "${calls[2]}" = "-y copr disable ublue-os/packages" ]
	[ "${calls[3]}" = "-y install --enablerepo=copr:copr.fedorainfracloud.org:ublue-os:packages uupd" ]
}

@test "20-packages-and-services: enables the update timers" {
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]

	mapfile -t calls <"${SYSTEMCTL_LOG}"
	[ "${#calls[@]}" -eq 2 ]
	[ "${calls[0]}" = "enable uupd.timer" ]
	[ "${calls[1]}" = "enable uupd-resume.timer" ]
}

@test "20-packages-and-services: performs no overlays or service enablement beyond its own" {
	# Boundary guard for the phase split: the filesystem overlays belong to
	# 10-overlay.sh, so a package change never invalidates them.
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]

	[ ! -e "${RSYNC_LOG}" ]
}

@test "20-packages-and-services: sources copr-helpers.sh so copr_install_isolated is available" {
	cat >>"${SCRIPT}" <<'EOF'
declare -F copr_install_isolated >/dev/null && echo "HELPER_PRESENT"
EOF
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"HELPER_PRESENT"* ]]
}

@test "20-packages-and-services: fails fast when copr-helpers.sh is missing from the context" {
	rm -f "${CTX}/build/copr-helpers.sh"
	run bash "${SCRIPT}"
	[ "$status" -ne 0 ]
}

@test "20-packages-and-services: restores default glob behaviour before finishing" {
	cat >>"${SCRIPT}" <<'EOF'
shopt -q nullglob || echo "NULLGLOB_OFF"
EOF
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"NULLGLOB_OFF"* ]]
}
