#!/usr/bin/env bats
# Unit tests for build/clean-stage.sh
#
# The script is exercised against a fake filesystem root via its CLEAN_ROOT
# hook, with dnf5/systemctl/mountpoint replaced by stubs.

setup() {
	load 'helpers/stub'
	setup_sandbox
	SCRIPT="${REPO_ROOT}/build/clean-stage.sh"
	export SCRIPT
	stub_command dnf5
	stub_command systemctl
	stub_command mountpoint 1

	# Minimum tree the script walks unconditionally.
	mkdir -p "${SANDBOX}/var/cache" "${SANDBOX}/usr/lib/systemd/system"
}

run_clean_stage() {
	run env CLEAN_ROOT="${SANDBOX}" bash "${SCRIPT}"
}

@test "clean-stage restores upstream dnf5 cache and versionlock defaults" {
	run_clean_stage
	[ "$status" -eq 0 ]
	run stub_log_contains "dnf5 config-manager setopt keepcache=0"
	[ "$status" -eq 0 ]
	run stub_log_contains "dnf5 versionlock clear"
	[ "$status" -eq 0 ]
}

@test "clean-stage disables and masks the fedora flatpak repo service" {
	run_clean_stage
	[ "$status" -eq 0 ]
	run stub_log_contains "systemctl disable flatpak-add-fedora-repos.service"
	[ "$status" -eq 0 ]
	run stub_log_contains "systemctl mask flatpak-add-fedora-repos.service"
	[ "$status" -eq 0 ]
}

@test "clean-stage removes the flatpak repo unit file under CLEAN_ROOT" {
	touch "${SANDBOX}/usr/lib/systemd/system/flatpak-add-fedora-repos.service"
	run_clean_stage
	[ "$status" -eq 0 ]
	[ ! -e "${SANDBOX}/usr/lib/systemd/system/flatpak-add-fedora-repos.service" ]
}

@test "clean-stage removes the repo .gitkeep placeholder" {
	touch "${SANDBOX}/.gitkeep"
	run_clean_stage
	[ "$status" -eq 0 ]
	[ ! -e "${SANDBOX}/.gitkeep" ]
}

@test "clean-stage removes /var subdirectories but keeps /var/cache" {
	mkdir -p "${SANDBOX}/var/log" "${SANDBOX}/var/lib"
	run_clean_stage
	[ "$status" -eq 0 ]
	[ ! -d "${SANDBOX}/var/log" ]
	[ ! -d "${SANDBOX}/var/lib" ]
	[ -d "${SANDBOX}/var/cache" ]
}

@test "clean-stage keeps libdnf5 and rpm-ostree caches and drops the rest" {
	mkdir -p "${SANDBOX}/var/cache/libdnf5" "${SANDBOX}/var/cache/rpm-ostree" \
		"${SANDBOX}/var/cache/dnf" "${SANDBOX}/var/cache/ldconfig"
	run_clean_stage
	[ "$status" -eq 0 ]
	[ -d "${SANDBOX}/var/cache/libdnf5" ]
	[ -d "${SANDBOX}/var/cache/rpm-ostree" ]
	[ ! -d "${SANDBOX}/var/cache/dnf" ]
	[ ! -d "${SANDBOX}/var/cache/ldconfig" ]
}

@test "clean-stage empties tmp and boot without deleting the directories" {
	mkdir -p "${SANDBOX}/tmp/nested" "${SANDBOX}/boot/loader"
	touch "${SANDBOX}/tmp/stale" "${SANDBOX}/boot/vmlinuz"
	run_clean_stage
	[ "$status" -eq 0 ]
	[ -d "${SANDBOX}/tmp" ]
	[ -d "${SANDBOX}/boot" ]
	[ -z "$(ls -A "${SANDBOX}/tmp")" ]
	[ -z "$(ls -A "${SANDBOX}/boot")" ]
}

@test "clean-stage creates tmp, boot and run when they are absent" {
	run_clean_stage
	[ "$status" -eq 0 ]
	[ -d "${SANDBOX}/tmp" ]
	[ -d "${SANDBOX}/boot" ]
	[ -d "${SANDBOX}/run" ]
}

@test "clean-stage removes image-owned files and empty dirs under /run" {
	mkdir -p "${SANDBOX}/run/dnf/sub"
	touch "${SANDBOX}/run/dnf/sub/lock"
	run_clean_stage
	[ "$status" -eq 0 ]
	[ -d "${SANDBOX}/run" ]
	[ ! -e "${SANDBOX}/run/dnf" ]
}

@test "clean-stage leaves mounted entries and their parents in place" {
	mkdir -p "${SANDBOX}/run/mounted"
	touch "${SANDBOX}/run/mounted/keepme" "${SANDBOX}/run/loose"
	# mountpoint succeeds only for the file we declare mounted.
	cat >"${STUB_BIN}/mountpoint" <<EOF
#!/usr/bin/bash
[[ "\${*}" == *"${SANDBOX}/run/mounted/keepme" ]]
EOF
	chmod +x "${STUB_BIN}/mountpoint"

	run_clean_stage
	[ "$status" -eq 0 ]
	[ -e "${SANDBOX}/run/mounted/keepme" ]
	[ -d "${SANDBOX}/run/mounted" ]
	[ ! -e "${SANDBOX}/run/loose" ]
}

@test "clean-stage wraps its output in a GitHub Actions log group" {
	run_clean_stage
	[ "$status" -eq 0 ]
	[[ "$output" == *"::group::"* ]]
	[[ "$output" == *"::endgroup::"* ]]
}
