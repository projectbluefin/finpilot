#!/usr/bin/env bats
# Tests for build/validate-flatpaks.sh.
#
# All runs use a fake flatpak binary, never the host's. The contract under
# test: every line must be blank, a '#' comment, a [Flatpak Preinstall <app-id>]
# header, or a key=value pair; every such section must declare a non-empty
# Branch= (an empty one fails closed); every app-id is passed to
# `flatpak remote-info` as data, as <app-id>//<branch>, so an unresolvable
# branch fails; and an empty discovery result fails closed instead of
# passing vacuously.
#
# Run with: bats tests/contract/validate-flatpaks_test.bats

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
        # $1=remote-info $2=--user $3=flathub $4=<app-id>//<branch>
        [[ $# -eq 4 && "$4" == *//* ]] || exit 99
        # Like flatpak's ref parser, reject a branch containing whitespace.
        if [[ "${4#*//}" =~ [[:space:]] ]]; then
            echo "error: Invalid branch ${4#*//}" >&2
            exit 1
        fi
        case " ${MOCK_REMOTE_FAILURES:-} " in
            *" ${4%%//*} "*)
                echo 'error: remote-info failed' >&2
                exit 42
                ;;
        esac
        case " ${MOCK_BRANCH_FAILURES:-} " in
            *" ${4#*//} "*)
                echo 'error: No remote refs found for branch' >&2
                exit 43
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

@test "validator fails closed on an empty Branch= value" {
    # Regression: an empty `Branch=` used to satisfy /^Branch=/ and pass,
    # letting flatpak resolve against the remote default branch instead of
    # failing closed. See projectbluefin/finpilot#504.
    cat > "${FIXTURES}/base.preinstall" <<'EOF'
[Flatpak Preinstall org.gnome.Calculator]
Branch=
EOF
    run bash "${SCRIPT}" "${FIXTURES}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"FAIL: ${FIXTURES}/base.preinstall: org.gnome.Calculator: missing Branch= key"* ]]
}

@test "validator fails closed on a whitespace-only Branch= value" {
    # Whitespace-only is still empty for the END check, so it fails closed.
    printf '[Flatpak Preinstall org.gnome.Calculator]\nBranch=   \n' > "${FIXTURES}/base.preinstall"
    run bash "${SCRIPT}" "${FIXTURES}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"FAIL: ${FIXTURES}/base.preinstall: org.gnome.Calculator: missing Branch= key"* ]]
}

@test "validator accepts key-side whitespace around the = (GKeyFile strips it)" {
    # GKeyFile strips the whitespace around the key and the `=` before
    # comparing, so `Branch = stable` is the key Branch and must not be
    # reported as missing. See projectbluefin/finpilot#509.
    cat > "${FIXTURES}/base.preinstall" <<'EOF'
[Flatpak Preinstall org.gnome.Calculator]
Branch = stable
EOF
    run bash "${SCRIPT}" "${FIXTURES}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"PASS: ${FIXTURES}/base.preinstall: org.gnome.Calculator (stable)"* ]]
}

@test "validator preserves trailing whitespace in the Branch= value (GKeyFile does)" {
    # GKeyFile strips only leading whitespace from the value, so
    # `Branch=stable ` names the branch "stable " (with the trailing space),
    # which flatpak cannot resolve. The branch is now checked on the remote,
    # so this fails instead of resolving against the default branch and
    # passing. See projectbluefin/finpilot#513.
    printf '[Flatpak Preinstall org.gnome.Calculator]\nBranch=stable \n' > "${FIXTURES}/base.preinstall"
    run bash "${SCRIPT}" "${FIXTURES}"
    [ "${status}" -eq 1 ]
    # bash's %q renders a trailing space as a backslash-escape, not quoted.
    [[ "${output}" == *"FAIL: ${FIXTURES}/base.preinstall: org.gnome.Calculator: not on flathub at branch stable\\  (exit 1)"* ]]
    run grep -c '^remote-info --user flathub org.gnome.Calculator//stable $' "${CALLS}"
    [ "${output}" = "1" ]
}

@test "validator takes the last Branch= of a duplicate (GKeyFile last-wins)" {
    # For a duplicate key GKeyFile uses the last value, not the first, so the
    # later `Branch=stable` must win over the earlier `Branch=old`. See
    # projectbluefin/finpilot#509.
    cat > "${FIXTURES}/base.preinstall" <<'EOF'
[Flatpak Preinstall org.gnome.Calculator]
Branch=old
Branch=stable
EOF
    run bash "${SCRIPT}" "${FIXTURES}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"PASS: ${FIXTURES}/base.preinstall: org.gnome.Calculator (stable)"* ]]
}

@test "validator fails closed when the last of duplicate Branch= is empty" {
    # GKeyFile last-wins also means an empty final value fails closed, even
    # though an earlier value was non-empty. See projectbluefin/finpilot#509.
    cat > "${FIXTURES}/base.preinstall" <<'EOF'
[Flatpak Preinstall org.gnome.Calculator]
Branch=stable
Branch=
EOF
    run bash "${SCRIPT}" "${FIXTURES}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"FAIL: ${FIXTURES}/base.preinstall: org.gnome.Calculator: missing Branch= key"* ]]
}

@test "validator fails when the Branch value does not exist on the remote" {
    # Regression (projectbluefin/finpilot#513): Branch= was only echoed in
    # the PASS line, so a non-empty but nonexistent branch (e.g. Branch=nope)
    # passed because remote-info was called with the app-id alone and
    # resolved against the remote default branch. remote-info is now called
    # with <app-id>//<branch>, so a missing branch fails.
    export MOCK_BRANCH_FAILURES="nope"
    cat > "${FIXTURES}/base.preinstall" <<'EOF'
[Flatpak Preinstall org.gnome.Calculator]
Branch=nope
EOF
    run bash "${SCRIPT}" "${FIXTURES}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"FAIL: ${FIXTURES}/base.preinstall: org.gnome.Calculator: not on flathub at branch nope (exit 43)"* ]]
}

@test "validator fails when an app is not on flathub" {
    export MOCK_REMOTE_FAILURES="com.example.Missing"
    cat > "${FIXTURES}/base.preinstall" <<'EOF'
[Flatpak Preinstall com.example.Missing]
Branch=stable
EOF
    run bash "${SCRIPT}" "${FIXTURES}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"FAIL: ${FIXTURES}/base.preinstall: com.example.Missing: not on flathub at branch stable (exit 42)"* ]]
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

@test "validator ensures the flathub remote and passes the branch as data" {
    cat > "${FIXTURES}/base.preinstall" <<'EOF'
[Flatpak Preinstall org.gnome.Calculator]
Branch=stable
EOF
    run bash "${SCRIPT}" "${FIXTURES}"
    [ "${status}" -eq 0 ]
    # The remote is added from the checked-in fixture, never the live URL: the
    # whole point of #493 is that the descriptor is pinned, not fetched.
    run grep -c '^remote-add --user --if-not-exists flathub .*fixtures/flathub.flatpakrepo$' "${CALLS}"
    [ "${output}" = "1" ]
    run grep -c '^remote-add --user --if-not-exists flathub https://dl.flathub.org' "${CALLS}"
    [ "${output}" = "0" ]
    run grep -c '^remote-info --user flathub org.gnome.Calculator//stable$' "${CALLS}"
    [ "${output}" = "1" ]
}

@test "validator accepts blank lines and # comments" {
    cat > "${FIXTURES}/base.preinstall" <<'EOF'
# Header comment

[Flatpak Preinstall org.gnome.Calculator]
Branch=stable

# Trailing comment
EOF
    run bash "${SCRIPT}" "${FIXTURES}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"1 preinstall files, 1 app checks, 0 failures."* ]]
}

@test "validator rejects a ';' comment, which flatpak parses as a syntax error" {
    # flatpak's parser is GKeyFile: ';' is not a comment character, and a
    # malformed line makes it discard the whole file while still exiting 0.
    cat > "${FIXTURES}/base.preinstall" <<'EOF'
# Header
;[Flatpak Preinstall org.gnome.Calculator]
;Branch=stable

[Flatpak Preinstall org.gnome.TextEditor]
Branch=stable
EOF
    run bash "${SCRIPT}" "${FIXTURES}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"FAIL: ${FIXTURES}/base.preinstall:2: not a # comment"* ]]
    [[ "${output}" == *"FAIL: ${FIXTURES}/base.preinstall:3: not a # comment"* ]]
    # The well-formed section is still checked and reported.
    [[ "${output}" == *"PASS: ${FIXTURES}/base.preinstall: org.gnome.TextEditor (stable)"* ]]
    [[ "${output}" == *"1 app checks, 2 failures."* ]]
}

@test "validator rejects a group header flatpak would skip" {
    # Groups are matched by prefix and anything else is skipped at g_info level,
    # so a header with no app-id installs nothing and says nothing.
    cat > "${FIXTURES}/base.preinstall" <<'EOF'
[Flatpak Preinstall]
EOF
    run bash "${SCRIPT}" "${FIXTURES}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"FAIL: ${FIXTURES}/base.preinstall:1: not a # comment"* ]]
}
