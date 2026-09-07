#!/usr/bin/env bats
# Tests for build/validate-brewfiles.sh.
#
# All commands use a fake brew, never the host's package manager. The central
# security property under test: the script greps Brewfiles and passes names to
# `brew info` as data — a Brewfile containing executable Ruby must fail closed
# WITHOUT ever reaching `brew bundle` (the taps file is the only input that
# gets evaluated, so non-literal tap lines are rejected up front).
#
# Run with: bats tests/unit/validate-brewfiles_test.bats

SCRIPT="${BATS_TEST_DIRNAME}/../../build/validate-brewfiles.sh"

setup() {
    WORKDIR="$(mktemp -d)"
    FIXTURES="${WORKDIR}/brewfiles"
    CALLS="${WORKDIR}/calls"
    TAPS="${WORKDIR}/taps"
    mkdir -p "${FIXTURES}" "${WORKDIR}/bin"
    : > "${CALLS}"
    cat > "${WORKDIR}/bin/brew" <<'MOCK'
#!/usr/bin/bash
printf '%s|%s|%s\n' "${1:-}" "${2:-}" "${@: -1}" >> "${CALLS}"
case "$1" in
    bundle)
        cp "${2#--file=}" "${TAPS}"
        if [[ "${MOCK_TAP_STATUS:-0}" != 0 ]]; then
            echo 'tap stdout diagnostic'
            echo 'tap stderr: authentication/network/trust error' >&2
            exit "${MOCK_TAP_STATUS}"
        fi
        ;;
    info)
        [[ $# -eq 4 && "$3" == -- ]] || exit 99
        case " ${MOCK_INFO_FAILURES:-} " in
            *" $4 "*)
                echo 'metadata stdout diagnostic'
                echo "${MOCK_INFO_ERROR:-metadata stderr: cask unavailable}" >&2
                exit 42
                ;;
        esac
        ;;
    *) echo "unexpected brew operation: $*" >&2; exit 99 ;;
esac
MOCK
    chmod +x "${WORKDIR}/bin/brew"
    export CALLS TAPS
    export PATH="${WORKDIR}/bin:/usr/bin:/bin"
}

teardown() {
    rm -rf "${WORKDIR}"
}

@test "validator checks formulas and casks with source lines" {
    printf '  brew "ripgrep" # comment\n' > "${FIXTURES}/test.Brewfile"
    echo "  cask 'demo', args: { no_quarantine: true }" >> "${FIXTURES}/test.Brewfile"
    run bash "${SCRIPT}" "${FIXTURES}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"test.Brewfile:1: formula ripgrep"* ]]
    [[ "${output}" == *"test.Brewfile:2: cask demo"* ]]
    [[ "${output}" == *"1 Brewfiles, 2 package checks, 0 failures"* ]]
    grep -qFx 'info|--formula|ripgrep' "${CALLS}"
    grep -qFx 'info|--cask|demo' "${CALLS}"
    [ ! -e "${TAPS}" ]
}

@test "validator syncs deduplicated taps before any package checks" {
    printf 'tap "one/tap", trusted: true\ncask "one/tap/demo"\n' > "${FIXTURES}/a.Brewfile"
    printf 'tap "two/tap"\ntap "one/tap", trusted: true\n' > "${FIXTURES}/z.Brewfile"
    run bash "${SCRIPT}" "${FIXTURES}"
    [ "${status}" -eq 0 ]
    grep -qFx 'tap "one/tap", trusted: true' "${TAPS}"
    grep -qFx 'tap "two/tap"' "${TAPS}"
    [ "$(wc -l < "${TAPS}")" -eq 2 ]
    [[ "$(head -1 "${CALLS}")" == bundle\|* ]]
    run test -z "$(grep -E '^[[:space:]]*(brew|cask) ' "${TAPS}" || true)"
    [ "${status}" -eq 0 ]
}

@test "computed tap lines fail closed without reaching brew bundle" {
    printf 'tap "evil/#{"x"}/tap"\nbrew "ripgrep"\n' > "${FIXTURES}/interp.Brewfile"
    printf 'tap "x/y" if system("id")\n' > "${FIXTURES}/trailer.Brewfile"
    printf 'tap "x/y"; system("id")\n' > "${FIXTURES}/semicolon.Brewfile"
    run bash "${SCRIPT}" "${FIXTURES}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"expected a quoted literal tap declaration"* ]]
    [[ "${output}" == *"refusing to evaluate non-literal tap lines"* ]]
    [ ! -e "${TAPS}" ]
    run test "$(grep -c '^bundle|' "${CALLS}" || true)" -eq 0
    [ "${status}" -eq 0 ]
    run test "$(grep -c '^info|' "${CALLS}" || true)" -eq 0
    [ "${status}" -eq 0 ]
}

@test "tap failure is fatal and preserves both output streams" {
    printf 'tap "broken/tap"\ncask "demo"\n' > "${FIXTURES}/test.Brewfile"
    MOCK_TAP_STATUS=17 run bash "${SCRIPT}" "${FIXTURES}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"tap setup (exit 17)"* ]]
    [[ "${output}" == *"Package checks were not run"* ]]
    [[ "${output}" == *"Command: brew bundle"* ]]
    [[ "${output}" == *"tap stdout diagnostic"* ]]
    [[ "${output}" == *"tap stderr: authentication/network/trust error"* ]]
    run test "$(grep -c '^info|' "${CALLS}" || true)" -eq 0
    [ "${status}" -eq 0 ]
}

@test "info failure reports file line command exit code and original error" {
    printf '# heading\ncask "missing"\n' > "${FIXTURES}/test.Brewfile"
    MOCK_INFO_FAILURES=missing run bash "${SCRIPT}" "${FIXTURES}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"test.Brewfile:2: cask missing (exit 42)"* ]]
    [[ "${output}" == *"Command: brew info --cask -- missing"* ]]
    [[ "${output}" == *"metadata stdout diagnostic"* ]]
    [[ "${output}" == *"metadata stderr: cask unavailable"* ]]
    [[ "${output}" == *"1 package checks, 1 failures"* ]]
}

@test "malformed brew declarations are rejected, failures accumulate across files" {
    printf 'cask "missing"\nbrew ripgrep\n' > "${FIXTURES}/a.Brewfile"
    printf 'brew "other"\ncask "good"\n' > "${FIXTURES}/z.Brewfile"
    MOCK_INFO_FAILURES='missing other' run bash "${SCRIPT}" "${FIXTURES}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"expected a quoted literal brew/cask name"* ]]
    [[ "${output}" == *"2 Brewfiles, 3 package checks, 3 failures"* ]]
    grep -qFx 'info|--cask|good' "${CALLS}"
}

@test "missing directory and empty directory exit 2" {
    run bash "${SCRIPT}" "${WORKDIR}/nope"
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"does not exist"* ]]
    run bash "${SCRIPT}" "${FIXTURES}"
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"No Brewfiles found"* ]]
}

@test "validator checks final declaration without trailing newline" {
    printf '# cask "ignored"\nflatpak "org.example.App"\nbrew "ripgrep"' > "${FIXTURES}/test.Brewfile"
    run bash "${SCRIPT}" "${FIXTURES}"
    [ "${status}" -eq 0 ]
    [ "$(grep -c '^info|' "${CALLS}")" -eq 1 ]
}
