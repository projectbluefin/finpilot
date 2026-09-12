#!/usr/bin/env bats
# Tests for build/validate-flatpaks.sh.
#
# All runs use a fake flatpak binary, never the host's. The contract under
# test: every [Flatpak Preinstall <app>] section must declare Branch=, every
# app-id is passed to `flatpak remote-info` as data, and an empty discovery
# result fails closed instead of passing vacuously.
#
# Run with: bats tests/unit/validate-flatpaks_test.bats

SCRIPT="${BATS_TEST_DIRNAME}/../../build/validate-flatpaks.sh"

setup() {
    WORKDIR="$(mktemp -d)"
    FIXTURES="${WORKDIR}/flatpaks"
    CALLS="${WORKDIR}/calls"
    mkdir -p "${FIXTURES}" "${WORKDIR}/bin"
    : > "${CALLS}"
    cat > "${WORKDIR}/bin/flatpak" <<'MOCK'
#!/usr/bin/bash
printf '%s\n' "$*" >> "${CALLS}"
case "$1" in
    remote-add)
        ;;
    remote-info)
        # $1=remote-info $2=--user $3=flathub $4=app-id
        [[ $# -eq 4 ]] || exit 99
        case " ${MOCK_REMOTE_FAILURES:-} " in
            *" $4 "*)
                echo 'error: remote-info failed' >&2
                exit 42
                ;;
        esac
        ;;
    *) echo "unexpected flatpak operation: $*" >&2; exit 99 ;;
esac
MOCK
    chmod +x "${WORKDIR}/bin/flatpak"
    export CALLS
    export PATH="${WORKDIR}/bin:/usr/bin:/bin"
}

teardown() {
    rm -rf "${WORKDIR}"
}

@test "validator passes a well-formed preinstall file" {
    cat > "${FIXTURES}/base.preinstall" <<'EOF'
[Flatpak Preinstall org.gnome.Calculator]
Branch=stable
EOF
    run bash "${SCRIPT}" "${FIXTURES}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"PASS: ${FIXTURES}/base.preinstall: org.gnome.Calculator (stable)"* ]]
    [[ "${output}" == *"1 preinstall files, 1 app checks, 0 failures."* ]]
}

@test "validator fails closed on a missing Branch= key" {
    cat > "${FIXTURES}/base.preinstall" <<'EOF'
[Flatpak Preinstall org.gnome.Calculator]
[Flatpak Preinstall org.gnome.TextEditor]
Branch=stable
EOF
    run bash "${SCRIPT}" "${FIXTURES}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"FAIL: ${FIXTURES}/base.preinstall: org.gnome.Calculator: missing Branch= key"* ]]
    # The well-formed app in the same file is still checked and reported.
    [[ "${output}" == *"PASS: ${FIXTURES}/base.preinstall: org.gnome.TextEditor (stable)"* ]]
}

@test "validator fails when an app is not on flathub" {
    export MOCK_REMOTE_FAILURES="com.example.Missing"
    cat > "${FIXTURES}/base.preinstall" <<'EOF'
[Flatpak Preinstall com.example.Missing]
Branch=stable
EOF
    run bash "${SCRIPT}" "${FIXTURES}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"FAIL: ${FIXTURES}/base.preinstall: com.example.Missing: not on flathub (exit 42)"* ]]
}

@test "validator fails closed when the directory has no preinstall files" {
    run bash "${SCRIPT}" "${FIXTURES}"
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"No .preinstall files found"* ]]
}

@test "validator fails closed when the directory does not exist" {
    run bash "${SCRIPT}" "${FIXTURES}/nope"
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"Flatpak directory does not exist"* ]]
}

@test "validator ensures the flathub remote and passes app-ids as data" {
    cat > "${FIXTURES}/base.preinstall" <<'EOF'
[Flatpak Preinstall org.gnome.Calculator]
Branch=stable
EOF
    run bash "${SCRIPT}" "${FIXTURES}"
    [ "${status}" -eq 0 ]
    run grep -c '^remote-add --user --if-not-exists flathub ' "${CALLS}"
    [ "${output}" = "1" ]
    run grep -c '^remote-info --user flathub org.gnome.Calculator$' "${CALLS}"
    [ "${output}" = "1" ]
}
