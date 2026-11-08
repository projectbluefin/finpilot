#!/usr/bin/env bats
# Unit tests for build/90-cleanup.sh.
#
# The script honours CLEAN_ROOT as a filesystem prefix, so every destructive
# operation runs against a sandbox directory instead of the host. dnf5,
# systemctl and mountpoint are stubbed on PATH.
#
# Run with: bats tests/template/90-cleanup_test.bats

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
CLEANUP_SRC="${SCRIPT_DIR}/../../build/90-cleanup.sh"

setup() {
	TEST_ROOT="${BATS_TEST_TMPDIR:-${BATS_TMPDIR}}/90-cleanup.${BATS_TEST_NUMBER:-0}.$$"
	STUB_BIN="${TEST_ROOT}/stub-bin"
	DNF5_LOG="${TEST_ROOT}/logs/dnf5.log"
	SYSTEMCTL_LOG="${TEST_ROOT}/logs/systemctl.log"
	SANDBOX="${TEST_ROOT}/root"
	REPOS_DIR="${SANDBOX}/etc/yum.repos.d"

	mkdir -p "${STUB_BIN}" "${TEST_ROOT}/logs"

	# Minimal filesystem layout the script expects to operate on.
	mkdir -p "${SANDBOX}/usr/lib/systemd/system"
	mkdir -p "${REPOS_DIR}"
	mkdir -p "${SANDBOX}/var/cache/libdnf5"
	mkdir -p "${SANDBOX}/var/cache/rpm-ostree"
	mkdir -p "${SANDBOX}/var/cache/dnf"
	mkdir -p "${SANDBOX}/var/log"
	mkdir -p "${SANDBOX}/tmp/leftover"
	mkdir -p "${SANDBOX}/boot/efi"
	mkdir -p "${SANDBOX}/run/dnf"
	touch "${SANDBOX}/usr/lib/systemd/system/flatpak-add-fedora-repos.service"
	touch "${SANDBOX}/.gitkeep"
	touch "${SANDBOX}/run/dnf/state"

	# One repository file per shape the script disables, plus a Fedora repo it
	# must leave alone.
	printf '[copr]\nenabled=1\n' \
		>"${REPOS_DIR}/_copr:copr.fedorainfracloud.org:ublue-os:packages.repo"
	printf '[rpmfusion]\nenabled=1\n' >"${REPOS_DIR}/rpmfusion-free.repo"
	printf '[multimedia]\nenabled=1\n' >"${REPOS_DIR}/fedora-multimedia.repo"
	printf '[fedora]\nenabled=1\n' >"${REPOS_DIR}/fedora.repo"

	export PATH="${STUB_BIN}:${PATH}"
	export CLEAN_ROOT="${SANDBOX}"
	export DNF5_LOG SYSTEMCTL_LOG

	cat >"${STUB_BIN}/dnf5" <<'EOF'
#!/usr/bin/bash
printf '%s\n' "$*" >> "${DNF5_LOG}"
# `dnf5 repo list --enabled` is what the guard re-checks. A test sets
# DNF5_REPO_LIST to simulate dnf's view of enabled repositories; unset means
# dnf lists none and the guard passes.
case " $* " in
  *" repo list "*) [ -n "${DNF5_REPO_LIST:-}" ] && printf '%s\n' "${DNF5_REPO_LIST}" ;;
esac
exit 0
EOF
	chmod +x "${STUB_BIN}/dnf5"

	cat >"${STUB_BIN}/systemctl" <<'EOF'
#!/usr/bin/bash
printf '%s\n' "$*" >> "${SYSTEMCTL_LOG}"
exit 0
EOF
	chmod +x "${STUB_BIN}/systemctl"

	# mountpoint(1) is not meaningful inside the sandbox; default to "not a
	# mountpoint" so the script takes its normal removal path.
	cat >"${STUB_BIN}/mountpoint" <<'EOF'
#!/usr/bin/bash
exit 1
EOF
	chmod +x "${STUB_BIN}/mountpoint"

	# rpm(1) classifies a .repo file as base-owned only when an installed RPM
	# owns it. fedora.repo is provided by fedora-repos; every file the build
	# added (copr, addrepo, curl) is unowned, so ownership says third-party.
	cat >"${STUB_BIN}/rpm" <<'EOF'
#!/usr/bin/bash
[[ "$(basename "$2")" == "fedora.repo" ]] && exit 0
exit 1
EOF
	chmod +x "${STUB_BIN}/rpm"
}

teardown() {
	rm -rf "${TEST_ROOT}"
}

run_cleanup() {
	run bash "${CLEANUP_SRC}"
}

@test "90-cleanup: completes successfully against a sandbox root" {
	run_cleanup
	[ "$status" -eq 0 ]
}

@test "90-cleanup: emits GitHub Actions group markers" {
	run_cleanup
	[ "$status" -eq 0 ]
	[[ "$output" == *"::group:: Finalise package repositories"* ]]
	[[ "$output" == *"::group:: Finalise Flatpak sources"* ]]
	[[ "$output" == *"::group:: Prune build artifacts"* ]]
	[[ "$output" == *"::endgroup::"* ]]
}

@test "90-cleanup: restores dnf5 upstream defaults and clears versionlock" {
	run_cleanup
	[ "$status" -eq 0 ]

	mapfile -t calls <"${DNF5_LOG}"
	[ "${#calls[@]}" -eq 3 ]
	[ "${calls[0]}" = "config-manager unsetopt keepcache install_weak_deps" ]
	[ "${calls[1]}" = "versionlock clear" ]
	[ "${calls[2]}" = "-q repo list --enabled" ]
}

@test "90-cleanup: disables and masks the fedora flatpak service and the base updater" {
	run_cleanup
	[ "$status" -eq 0 ]

	mapfile -t calls <"${SYSTEMCTL_LOG}"
	[ "${#calls[@]}" -eq 3 ]
	[ "${calls[0]}" = "disable flatpak-add-fedora-repos.service" ]
	[ "${calls[1]}" = "mask flatpak-add-fedora-repos.service" ]
	[ "${calls[2]}" = "disable rpm-ostreed-automatic.timer" ]
}

@test "90-cleanup: removes the flatpak-add-fedora-repos unit file" {
	[ -f "${SANDBOX}/usr/lib/systemd/system/flatpak-add-fedora-repos.service" ]

	run_cleanup
	[ "$status" -eq 0 ]
	[ ! -e "${SANDBOX}/usr/lib/systemd/system/flatpak-add-fedora-repos.service" ]
}

@test "90-cleanup: disables every third-party repository and leaves Fedora's alone" {
	run_cleanup
	[ "$status" -eq 0 ]

	grep -q '^enabled=0' "${REPOS_DIR}/_copr:copr.fedorainfracloud.org:ublue-os:packages.repo"
	grep -q '^enabled=0' "${REPOS_DIR}/rpmfusion-free.repo"
	grep -q '^enabled=0' "${REPOS_DIR}/fedora-multimedia.repo"
	grep -q '^enabled=1' "${REPOS_DIR}/fedora.repo"
}

@test "90-cleanup: leaves an already-disabled third-party repository disabled" {
	printf '[copr]\nenabled=0\n' \
		>"${REPOS_DIR}/_copr:copr.fedorainfracloud.org:ublue-os:packages.repo"

	run_cleanup
	[ "$status" -eq 0 ]

	grep -q '^enabled=0' "${REPOS_DIR}/_copr:copr.fedorainfracloud.org:ublue-os:packages.repo"
}

@test "90-cleanup: fails the build when sed cannot rewrite a third-party repository" {
	# This covers the sed failure under set -e, not the final guard. The build must never ship a live third-party repository, so a repository
	# the script cannot rewrite is a hard failure. sed -i needs a writable
	# directory rather than a writable file, and root bypasses permissions.
	[ "$(id -u)" -ne 0 ] || skip "file permissions do not apply to root"
	chmod 500 "${REPOS_DIR}"

	run_cleanup
	[ "$status" -ne 0 ]
	chmod 700 "${REPOS_DIR}"
}

@test "90-cleanup: disables third-party repositories whatever spelling enables them" {
	printf '[copr]\nenabled = 1\n' \
		>"${REPOS_DIR}/_copr:copr.fedorainfracloud.org:ublue-os:packages.repo"
	printf '[rpmfusion]\nenabled=true\n' >"${REPOS_DIR}/rpmfusion-free.repo"
	printf '[multimedia]\nEnabled = Yes\n' >"${REPOS_DIR}/fedora-multimedia.repo"

	run_cleanup
	[ "$status" -eq 0 ]

	grep -qx 'enabled=0' "${REPOS_DIR}/_copr:copr.fedorainfracloud.org:ublue-os:packages.repo"
	grep -qx 'enabled=0' "${REPOS_DIR}/rpmfusion-free.repo"
	grep -qx 'enabled=0' "${REPOS_DIR}/fedora-multimedia.repo"
}

@test "90-cleanup: guard fails the build when dnf reports a third-party repository enabled" {
	# A repository dnf still lists as enabled leaked through the disable pass.
	# The guard asks dnf which repositories are live, so the test seeds dnf's
	# view with the leaked repository id via DNF5_REPO_LIST.
	DNF5_REPO_LIST="rpmfusion-free" run_cleanup
	[ "$status" -eq 1 ]
	[[ "$output" == *"::error::third-party repository still enabled: rpmfusion-free"* ]]
}

@test "90-cleanup: guard fails the build when a named third-party repository is still enabled" {
	# The named repositories (tailscale, ...) are disabled by a separate list
	# from the glob-matched ones; the guard must cover them too. tailscale is an
	# outside source, so dnf reporting it as live fails the build.
	DNF5_REPO_LIST="tailscale" run_cleanup
	[ "$status" -eq 1 ]
	[[ "$output" == *"::error::third-party repository still enabled: tailscale"* ]]
}

@test "90-cleanup: disables an unowned third-party repository the name list misses" {
	# A vendor repository the build added (for example vscode.repo from an
	# addrepo) has no fixed name in the list, so ownership classification must
	# still disable it before the guard runs.
	printf '[vscode]\nenabled=1\n' >"${REPOS_DIR}/vscode.repo"

	run_cleanup
	[ "$status" -eq 0 ]

	grep -q '^enabled=0' "${REPOS_DIR}/vscode.repo"
}

@test "90-cleanup: guard fails the build when an unowned third-party repository is still enabled" {
	# An unowned repository the build added has no fixed name in the disable
	# list, so the guard must catch it via dnf. Seed dnf's view with the repo id.
	DNF5_REPO_LIST="vscode" run_cleanup
	[ "$status" -eq 1 ]
	[[ "$output" == *"::error::third-party repository still enabled: vscode"* ]]
}

@test "90-cleanup: guard passes when dnf reports only Fedora repositories" {
	# Fedora's own repositories (fedora, fedora-updates, fedora-cisco-openh264)
	# are the only ones the build may ship enabled.
	DNF5_REPO_LIST="fedora fedora-updates fedora-cisco-openh264" run_cleanup
	[ "$status" -eq 0 ]
}

@test "90-cleanup: guard catches a repository that ships with no enabled= key" {
	# A repository that ships with no enabled= key is enabled by dnf's default.
	# The guard asks dnf, so it catches such a repository even though a grep of
	# its file would miss it. Here dnf reports the repository as live while its
	# file has no enabled= key at all.
	printf '[leaked]\n\ntype=rpmfusion\n' >"${REPOS_DIR}/leaked.repo"
	DNF5_REPO_LIST="leaked" run_cleanup
	[ "$status" -eq 1 ]
	[[ "$output" == *"::error::third-party repository still enabled: leaked"* ]]
}

@test "90-cleanup: removes the root .gitkeep placeholder" {
	run_cleanup
	[ "$status" -eq 0 ]
	[ ! -e "${SANDBOX}/.gitkeep" ]
}

@test "90-cleanup: removes /var subdirectories other than cache" {
	run_cleanup
	[ "$status" -eq 0 ]
	[ ! -e "${SANDBOX}/var/log" ]
	[ -d "${SANDBOX}/var/cache" ]
}

@test "90-cleanup: keeps libdnf5 and rpm-ostree cache dirs, drops the rest" {
	run_cleanup
	[ "$status" -eq 0 ]
	[ -d "${SANDBOX}/var/cache/libdnf5" ]
	[ -d "${SANDBOX}/var/cache/rpm-ostree" ]
	[ ! -e "${SANDBOX}/var/cache/dnf" ]
}

@test "90-cleanup: empties tmp and boot but keeps the directories" {
	run_cleanup
	[ "$status" -eq 0 ]
	[ -d "${SANDBOX}/tmp" ]
	[ -d "${SANDBOX}/boot" ]
	[ ! -e "${SANDBOX}/tmp/leftover" ]
	[ ! -e "${SANDBOX}/boot/efi" ]
}

@test "90-cleanup: creates tmp and boot when they are absent" {
	rm -rf "${SANDBOX}/tmp" "${SANDBOX}/boot"

	run_cleanup
	[ "$status" -eq 0 ]
	[ -d "${SANDBOX}/tmp" ]
	[ -d "${SANDBOX}/boot" ]
}

@test "90-cleanup: clears /run contents while keeping /run itself" {
	run_cleanup
	[ "$status" -eq 0 ]
	[ -d "${SANDBOX}/run" ]
	[ ! -e "${SANDBOX}/run/dnf" ]
}

@test "90-cleanup: skips mounted entries under tmp, boot and run" {
	mkdir -p "${SANDBOX}/run/mounted"
	touch "${SANDBOX}/run/mounted/keepme"
	mkdir -p "${SANDBOX}/tmp/mounted"

	cat >"${STUB_BIN}/mountpoint" <<EOF
#!/usr/bin/bash
# Treat only the two seeded paths as mountpoints.
case "\$2" in
  "${SANDBOX}/run/mounted"|"${SANDBOX}/tmp/mounted") exit 0 ;;
esac
exit 1
EOF
	chmod +x "${STUB_BIN}/mountpoint"

	run_cleanup
	[ "$status" -eq 0 ]
	[ -d "${SANDBOX}/run/mounted" ]
	[ -d "${SANDBOX}/tmp/mounted" ]
}

@test "90-cleanup: tolerates empty var cache directories" {
	rm -rf "${SANDBOX}/var/cache/libdnf5" "${SANDBOX}/var/cache/rpm-ostree" "${SANDBOX}/var/cache/dnf"

	run_cleanup
	[ "$status" -eq 0 ]
	[ -d "${SANDBOX}/var/cache" ]
}

@test "90-cleanup: is idempotent across repeated runs" {
	run_cleanup
	[ "$status" -eq 0 ]

	run_cleanup
	[ "$status" -eq 0 ]
}
