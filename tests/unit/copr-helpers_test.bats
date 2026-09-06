#!/usr/bin/env bats
# Unit tests for build/copr-helpers.sh (copr_install_isolated).
# Run with: bats tests/unit/copr-helpers_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
COPR_HELPERS_LIB="${SCRIPT_DIR}/../../build/copr-helpers.sh"

setup() {
    TEST_ROOT="${BATS_TEST_TMPDIR:-${BATS_TMPDIR}}/copr-helpers.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/bin"
    DNF5_LOG="${TEST_ROOT}/dnf5.log"

    mkdir -p "${STUB_BIN}"
    export PATH="${STUB_BIN}:${PATH}"
    export COPR_HELPERS_LIB
    export DNF5_LOG
    unset DNF5_FAIL_MATCH
    unset DNF5_FAIL_CODE

    cat >"${STUB_BIN}/dnf5" <<'EOF'
#!/usr/bin/bash
printf '%s\n' "$*" >> "${DNF5_LOG}"
if [[ -n "${DNF5_FAIL_MATCH:-}" && "$*" == *"${DNF5_FAIL_MATCH}"* ]]; then
    exit "${DNF5_FAIL_CODE:-1}"
fi
exit 0
EOF
    chmod +x "${STUB_BIN}/dnf5"

    # shellcheck source=../../build/copr-helpers.sh
    source "${COPR_HELPERS_LIB}"
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

@test "copr_install_isolated: enables, disables, then installs from the repo id" {
    run copr_install_isolated atim/starship starship

    [ "$status" -eq 0 ]
    [[ "$output" == *"Installing starship from COPR atim/starship (isolated)"* ]]
    [[ "$output" == *"Installed starship from atim/starship"* ]]

    mapfile -t calls <"${DNF5_LOG}"
    [ "${#calls[@]}" -eq 3 ]
    [ "${calls[0]}" = "-y copr enable atim/starship" ]
    [ "${calls[1]}" = "-y copr disable atim/starship" ]
    [ "${calls[2]}" = "-y install --enablerepo=copr:copr.fedorainfracloud.org:atim:starship starship" ]
}

@test "copr_install_isolated: disable runs before install so the repo stays off by default" {
    run copr_install_isolated ublue-os/staging ublue-update

    [ "$status" -eq 0 ]

    mapfile -t calls <"${DNF5_LOG}"
    disable_index=-1
    install_index=-1
    for i in "${!calls[@]}"; do
        [[ "${calls[$i]}" == *"copr disable"* ]] && disable_index="$i"
        [[ "${calls[$i]}" == *" install "* ]] && install_index="$i"
    done
    [ "$disable_index" -ge 0 ]
    [ "$install_index" -ge 0 ]
    [ "$disable_index" -lt "$install_index" ]
}

@test "copr_install_isolated: installs multiple packages in a single dnf5 transaction" {
    run copr_install_isolated atim/starship starship zsh fish

    [ "$status" -eq 0 ]

    mapfile -t calls <"${DNF5_LOG}"
    [ "${#calls[@]}" -eq 3 ]
    [ "${calls[2]}" = "-y install --enablerepo=copr:copr.fedorainfracloud.org:atim:starship starship zsh fish" ]
}

@test "copr_install_isolated: translates every slash in the copr name into the repo id" {
    run copr_install_isolated "owner/project" pkg

    [ "$status" -eq 0 ]

    mapfile -t calls <"${DNF5_LOG}"
    [[ "${calls[2]}" == *"--enablerepo=copr:copr.fedorainfracloud.org:owner:project"* ]]
    [[ "${calls[2]}" != *"owner/project "* ]]
}

@test "copr_install_isolated: fails when no packages are supplied" {
    run copr_install_isolated atim/starship

    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: No packages specified for copr_install_isolated"* ]]
    [ ! -s "${DNF5_LOG}" ] || [ ! -f "${DNF5_LOG}" ]
}

@test "copr_install_isolated: does not enable the repo when no packages are supplied" {
    run copr_install_isolated ublue-os/staging

    [ "$status" -eq 1 ]
    [ ! -f "${DNF5_LOG}" ]
}

@test "copr_install_isolated: propagates dnf5 install failure" {
    export DNF5_FAIL_MATCH=" install "
    export DNF5_FAIL_CODE=23

    run bash -c 'set -euo pipefail; source "$COPR_HELPERS_LIB"; copr_install_isolated atim/starship starship'

    [ "$status" -eq 23 ]
    [[ "$output" == *"Installing starship from COPR atim/starship (isolated)"* ]]
    [[ "$output" != *"Installed starship from atim/starship"* ]]
}

@test "copr_install_isolated: propagates dnf5 copr enable failure without installing" {
    export DNF5_FAIL_MATCH="copr enable"
    export DNF5_FAIL_CODE=7

    run bash -c 'set -euo pipefail; source "$COPR_HELPERS_LIB"; copr_install_isolated atim/starship starship'

    [ "$status" -eq 7 ]
    mapfile -t calls <"${DNF5_LOG}"
    [ "${#calls[@]}" -eq 1 ]
    [ "${calls[0]}" = "-y copr enable atim/starship" ]
}

@test "copr-helpers.sh: sourcing the library performs no dnf5 calls" {
    run bash -c 'source "$COPR_HELPERS_LIB"'

    [ "$status" -eq 0 ]
    [ ! -f "${DNF5_LOG}" ]
}
