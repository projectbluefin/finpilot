#!/usr/bin/env bats
# Unit tests for build/10-build.sh.
#
# The script sources /ctx/build/copr-helpers.sh and writes under /usr/share, so
# each test rewrites a throwaway copy to point at a sandbox root and stubs the
# binaries it shells out to (rsync, dnf5, systemctl). Production behaviour is
# never modified; the rewrite is asserted below so the suite fails loudly if the
# paths in the script ever drift.
#
# Run with: bats tests/unit/10-build_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_SRC="${REPO_ROOT}/build/10-build.sh"

setup() {
    TEST_ROOT="${BATS_TEST_TMPDIR:-${BATS_TMPDIR}}/10-build.${BATS_TEST_NUMBER:-0}.$$"
    SANDBOX="${TEST_ROOT}/root"
    CTX="${SANDBOX}/ctx"
    STUB_BIN="${TEST_ROOT}/stub-bin"
    SCRIPT="${TEST_ROOT}/10-build.sh"

    RSYNC_LOG="${TEST_ROOT}/logs/rsync.log"
    DNF5_LOG="${TEST_ROOT}/logs/dnf5.log"
    SYSTEMCTL_LOG="${TEST_ROOT}/logs/systemctl.log"

    HOMEBREW_DIR="${SANDBOX}/usr/share/ublue-os/homebrew"
    JUST_DIR="${SANDBOX}/usr/share/ublue-os/just"
    PREINSTALL_DIR="${SANDBOX}/usr/share/flatpak/preinstall.d"

    mkdir -p "${STUB_BIN}" "${TEST_ROOT}/logs"
    mkdir -p "${CTX}/oci/brew" "${CTX}/custom/brew" "${CTX}/custom/ujust" "${CTX}/custom/flatpaks"

    # The real helper library is sourced verbatim so a syntax break there fails
    # this suite too.
    mkdir -p "${CTX}/build"
    cp "${REPO_ROOT}/build/copr-helpers.sh" "${CTX}/build/copr-helpers.sh"

    # Representative build context contents.
    printf 'brew "tmux"\n' >"${CTX}/custom/brew/default.Brewfile"
    printf 'brew "gcc"\n' >"${CTX}/custom/brew/development.Brewfile"
    printf 'custom-apps-marker:\n\techo apps\n' >"${CTX}/custom/ujust/custom-apps.just"
    printf 'custom-system-marker:\n\techo system\n' >"${CTX}/custom/ujust/custom-system.just"
    printf '# not a just file\n' >"${CTX}/custom/ujust/README.md"
    printf 'org.mozilla.firefox\n' >"${CTX}/custom/flatpaks/default.preinstall"

    sed \
        -e "s#/ctx/#${CTX}/#g" \
        -e "s#/usr/share/#${SANDBOX}/usr/share/#g" \
        "${BUILD_SRC}" >"${SCRIPT}"

    export PATH="${STUB_BIN}:${PATH}"
    export RSYNC_LOG DNF5_LOG SYSTEMCTL_LOG

    for tool in rsync dnf5 systemctl; do
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

@test "10-build: sandbox rewrite left no writes to the host filesystem" {
    # Guards the rewrite above: if the script's paths change, the sed no longer
    # matches and every other test in this file would silently touch the host.
    run grep -nE '(^|[^-[:alnum:]])/ctx/|[^-[:alnum:]]/usr/share/' "${SCRIPT}"
    [ "$status" -ne 0 ]

    grep -q "source ${CTX}/build/copr-helpers.sh" "${SCRIPT}"
}

@test "10-build: completes successfully against a populated sandbox context" {
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Custom build complete!"* ]]
}

@test "10-build: emits GitHub Actions group markers" {
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"::group:: Overlay Brew Integration Files"* ]]
    [[ "$output" == *"::group:: Copy Custom Files"* ]]
    [[ "$output" == *"::group:: Install Packages"* ]]
    [[ "$output" == *"::group:: System Configuration"* ]]
    [[ "$output" == *"::endgroup::"* ]]
}

@test "10-build: overlays the brew OCI payload onto the image root" {
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]

    mapfile -t calls <"${RSYNC_LOG}"
    [ "${#calls[@]}" -eq 1 ]
    [ "${calls[0]}" = "-rvK ${CTX}/oci/brew/ /" ]
}

@test "10-build: copies every Brewfile into the ublue-os homebrew dir" {
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]

    [ -f "${HOMEBREW_DIR}/default.Brewfile" ]
    [ -f "${HOMEBREW_DIR}/development.Brewfile" ]
    grep -q 'brew "tmux"' "${HOMEBREW_DIR}/default.Brewfile"
}

@test "10-build: consolidates only .just files into 60-custom.just" {
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]

    [ -f "${JUST_DIR}/60-custom.just" ]
    grep -q 'custom-apps-marker:' "${JUST_DIR}/60-custom.just"
    grep -q 'custom-system-marker:' "${JUST_DIR}/60-custom.just"
    ! grep -q 'not a just file' "${JUST_DIR}/60-custom.just"
}

@test "10-build: separates consolidated just recipes with blank lines" {
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]

    # Without the separator the last line of one file and the first recipe of
    # the next would merge into a single unparseable line.
    run head -c 2 "${JUST_DIR}/60-custom.just"
    [ "$output" = "" ]
}

@test "10-build: copies flatpak preinstall files into preinstall.d" {
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]

    [ -f "${PREINSTALL_DIR}/default.preinstall" ]
    grep -q 'org.mozilla.firefox' "${PREINSTALL_DIR}/default.preinstall"
}

@test "10-build: installs the packages the default ujust recipes depend on" {
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]

    mapfile -t calls <"${DNF5_LOG}"
    [ "${#calls[@]}" -eq 1 ]
    [ "${calls[0]}" = "install -y tmux gum" ]
}

@test "10-build: enables exactly the podman and brew units" {
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]

    mapfile -t calls <"${SYSTEMCTL_LOG}"
    [ "${#calls[@]}" -eq 4 ]
    [ "${calls[0]}" = "enable podman.socket" ]
    [ "${calls[1]}" = "enable brew-setup.service" ]
    [ "${calls[2]}" = "enable brew-update.timer" ]
    [ "${calls[3]}" = "enable brew-upgrade.timer" ]
}

@test "10-build: sources copr-helpers.sh so copr_install_isolated is available" {
    cat >>"${SCRIPT}" <<'EOF'
declare -F copr_install_isolated >/dev/null && echo "HELPER_PRESENT"
EOF
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"HELPER_PRESENT"* ]]
}

@test "10-build: fails fast when copr-helpers.sh is missing from the context" {
    rm -f "${CTX}/build/copr-helpers.sh"
    run bash "${SCRIPT}"
    [ "$status" -ne 0 ]
    [ ! -d "${HOMEBREW_DIR}" ]
}

@test "10-build: the consolidated just file accumulates across repeated runs" {
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]
    local first_count
    first_count="$(grep -c 'custom-apps-marker:' "${JUST_DIR}/60-custom.just")"
    [ "${first_count}" -eq 1 ]

    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]

    # find(1) appends, so the consolidated file grows on every rebuild. This
    # only matters for repeated runs against a persistent root; documented here
    # so a future change to '>>' semantics is a deliberate one.
    run grep -c 'custom-apps-marker:' "${JUST_DIR}/60-custom.just"
    [ "$output" -eq 2 ]
}

@test "10-build: an empty brew dir fails the build despite nullglob (regression guard)" {
    # nullglob makes the glob expand to nothing, which leaves cp with a single
    # argument — cp then fails with 'missing destination file operand'. See
    # issue #287: nullglob does not make these copies optional.
    rm -f "${CTX}"/custom/brew/*.Brewfile
    run bash "${SCRIPT}"
    [ "$status" -ne 0 ]
}

@test "10-build: an empty flatpaks dir fails the build despite nullglob (regression guard)" {
    rm -f "${CTX}"/custom/flatpaks/*.preinstall
    run bash "${SCRIPT}"
    [ "$status" -ne 0 ]
}

@test "10-build: an empty ujust dir still produces a consolidated just file" {
    rm -f "${CTX}"/custom/ujust/*
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]
    [ -f "${JUST_DIR}/60-custom.just" ]
}

@test "10-build: restores default glob behaviour before finishing" {
    cat >>"${SCRIPT}" <<'EOF'
shopt -q nullglob || echo "NULLGLOB_OFF"
EOF
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"NULLGLOB_OFF"* ]]
}
