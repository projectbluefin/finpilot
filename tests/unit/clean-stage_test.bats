#!/usr/bin/env bats
# Unit tests for build/clean-stage.sh.
# The script honours CLEAN_ROOT as a filesystem prefix, so every destructive
# operation is exercised against a sandbox directory instead of the host.
# Run with: bats tests/unit/clean-stage_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
CLEAN_STAGE="${SCRIPT_DIR}/../../build/clean-stage.sh"

setup() {
    TEST_ROOT="${BATS_TEST_TMPDIR:-${BATS_TMPDIR}}/clean-stage.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/stub-bin"
    DNF5_LOG="${TEST_ROOT}/logs/dnf5.log"
    SYSTEMCTL_LOG="${TEST_ROOT}/logs/systemctl.log"
    SANDBOX="${TEST_ROOT}/root"

    mkdir -p "${STUB_BIN}" "${TEST_ROOT}/logs"

    # Minimal filesystem layout the script expects to operate on.
    mkdir -p "${SANDBOX}/usr/lib/systemd/system"
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

    export PATH="${STUB_BIN}:${PATH}"
    export CLEAN_ROOT="${SANDBOX}"
    export DNF5_LOG
    export SYSTEMCTL_LOG

    cat >"${STUB_BIN}/dnf5" <<'EOF'
#!/usr/bin/bash
printf '%s\n' "$*" >> "${DNF5_LOG}"
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
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

run_clean_stage() {
    run bash "${CLEAN_STAGE}"
}

@test "clean-stage: completes successfully against a sandbox root" {
    run_clean_stage
    [ "$status" -eq 0 ]
}

@test "clean-stage: emits GitHub Actions group markers" {
    run_clean_stage
    [ "$status" -eq 0 ]
    [[ "$output" == *"::group::"* ]]
    [[ "$output" == *"::endgroup::"* ]]
}

@test "clean-stage: restores dnf5 upstream defaults and clears versionlock" {
    run_clean_stage
    [ "$status" -eq 0 ]

    mapfile -t calls <"${DNF5_LOG}"
    [ "${#calls[@]}" -eq 2 ]
    [ "${calls[0]}" = "config-manager setopt keepcache=0" ]
    [ "${calls[1]}" = "versionlock clear" ]
}

@test "clean-stage: disables and masks the fedora flatpak repo service" {
    run_clean_stage
    [ "$status" -eq 0 ]

    mapfile -t calls <"${SYSTEMCTL_LOG}"
    [ "${#calls[@]}" -eq 2 ]
    [ "${calls[0]}" = "disable flatpak-add-fedora-repos.service" ]
    [ "${calls[1]}" = "mask flatpak-add-fedora-repos.service" ]
}

@test "clean-stage: removes the flatpak-add-fedora-repos unit file" {
    [ -f "${SANDBOX}/usr/lib/systemd/system/flatpak-add-fedora-repos.service" ]

    run_clean_stage
    [ "$status" -eq 0 ]
    [ ! -e "${SANDBOX}/usr/lib/systemd/system/flatpak-add-fedora-repos.service" ]
}

@test "clean-stage: removes the root .gitkeep placeholder" {
    run_clean_stage
    [ "$status" -eq 0 ]
    [ ! -e "${SANDBOX}/.gitkeep" ]
}

@test "clean-stage: removes /var subdirectories other than cache" {
    run_clean_stage
    [ "$status" -eq 0 ]
    [ ! -e "${SANDBOX}/var/log" ]
    [ -d "${SANDBOX}/var/cache" ]
}

@test "clean-stage: keeps libdnf5 and rpm-ostree cache dirs, drops the rest" {
    run_clean_stage
    [ "$status" -eq 0 ]
    [ -d "${SANDBOX}/var/cache/libdnf5" ]
    [ -d "${SANDBOX}/var/cache/rpm-ostree" ]
    [ ! -e "${SANDBOX}/var/cache/dnf" ]
}

@test "clean-stage: empties tmp and boot but keeps the directories" {
    run_clean_stage
    [ "$status" -eq 0 ]
    [ -d "${SANDBOX}/tmp" ]
    [ -d "${SANDBOX}/boot" ]
    [ ! -e "${SANDBOX}/tmp/leftover" ]
    [ ! -e "${SANDBOX}/boot/efi" ]
}

@test "clean-stage: creates tmp and boot when they are absent" {
    rm -rf "${SANDBOX}/tmp" "${SANDBOX}/boot"

    run_clean_stage
    [ "$status" -eq 0 ]
    [ -d "${SANDBOX}/tmp" ]
    [ -d "${SANDBOX}/boot" ]
}

@test "clean-stage: clears /run contents while keeping /run itself" {
    run_clean_stage
    [ "$status" -eq 0 ]
    [ -d "${SANDBOX}/run" ]
    [ ! -e "${SANDBOX}/run/dnf" ]
}

@test "clean-stage: skips mounted entries under tmp, boot and run" {
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

    run_clean_stage
    [ "$status" -eq 0 ]
    [ -d "${SANDBOX}/run/mounted" ]
    [ -d "${SANDBOX}/tmp/mounted" ]
}

@test "clean-stage: tolerates empty var cache directories" {
    rm -rf "${SANDBOX}/var/cache/libdnf5" "${SANDBOX}/var/cache/rpm-ostree" "${SANDBOX}/var/cache/dnf"

    run_clean_stage
    [ "$status" -eq 0 ]
    [ -d "${SANDBOX}/var/cache" ]
}

@test "clean-stage: is idempotent across repeated runs" {
    run_clean_stage
    [ "$status" -eq 0 ]

    run_clean_stage
    [ "$status" -eq 0 ]
}
