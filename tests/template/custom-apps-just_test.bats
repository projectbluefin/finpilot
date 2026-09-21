#!/usr/bin/env bats
# Tests for custom/ujust/custom-apps.just recipes:
#   install-default-apps, install-dev-tools.
#
# Each shebang recipe body is extracted out of the justfile into a standalone
# bash script and run against a PATH mock for brew, so the Brewfile path and
# the recipe's exit status are exercised without touching the host or the
# network.

APPS_JUST="${BATS_TEST_DIRNAME}/../../custom/ujust/custom-apps.just"
BREW_DIR="${BATS_TEST_DIRNAME}/../../custom/brew"
WORKDIR=""
MOCKDIR=""
COMMAND_LOG=""

_extract_recipe() {
    local recipe="$1" out_file="$2"
    awk -v recipe="${recipe}" '
        $0 ~ ("^" recipe "([ ][A-Za-z_]+)*:$") { in_recipe=1; next }
        in_recipe && !found && /^    #!/ { found=1; next }
        found && /^[^[:space:]]/ { exit }
        found { sub(/^    /, ""); print }
    ' "${APPS_JUST}" > "${out_file}"
    chmod +x "${out_file}"
    # Guard against a recipe rename silently producing an empty test subject.
    [ -s "${out_file}" ]
}

setup() {
    WORKDIR="$(mktemp -d)"
    MOCKDIR="${WORKDIR}/bin"
    COMMAND_LOG="${WORKDIR}/commands.log"
    mkdir -p "${MOCKDIR}" "${WORKDIR}/home"
    : > "${COMMAND_LOG}"

    cat > "${MOCKDIR}/brew" <<'MOCK'
#!/usr/bin/bash
echo "brew $*" >> "${COMMAND_LOG}"
exit "${MOCK_BREW_STATUS:-0}"
MOCK
    chmod +x "${MOCKDIR}/brew"

    export COMMAND_LOG
    export HOME="${WORKDIR}/home"
    # A minimal PATH keeps a real brew on the runner from leaking in.
    export PATH="${MOCKDIR}:/usr/bin:/bin"
}

teardown() {
    rm -rf "${WORKDIR}"
}

_run_recipe() {
    local recipe="$1"
    shift
    _extract_recipe "${recipe}" "${WORKDIR}/${recipe}.sh"
    run env PATH="${PATH}" HOME="${HOME}" COMMAND_LOG="${COMMAND_LOG}" "$@" \
        /usr/bin/bash "${WORKDIR}/${recipe}.sh"
}

@test "install-default-apps bundles only the default Brewfile" {
    _run_recipe "install-default-apps"

    [ "${status}" -eq 0 ]
    [ "$(grep -cF "brew bundle" "${COMMAND_LOG}")" -eq 1 ]
    grep -qF "brew bundle --file /usr/share/ublue-os/homebrew/default.Brewfile" "${COMMAND_LOG}"
}

@test "install-dev-tools bundles only the development Brewfile" {
    _run_recipe "install-dev-tools"

    [ "${status}" -eq 0 ]
    [ "$(grep -cF "brew bundle" "${COMMAND_LOG}")" -eq 1 ]
    grep -qF "brew bundle --file /usr/share/ublue-os/homebrew/development.Brewfile" "${COMMAND_LOG}"
}

@test "a failing bundle reports a nonzero exit" {
    _run_recipe "install-default-apps" MOCK_BREW_STATUS=1

    [ "${status}" -ne 0 ]
}

@test "every Brewfile referenced by a recipe is shipped by custom/brew" {
    # Guards against a Brewfile rename that would leave ujust pointing at a path
    # the image never ships. Recipes here only bundle files the template owns;
    # anything the shared layer ships is used directly, not wrapped.
    local referenced
    referenced="$(grep -o '/usr/share/ublue-os/homebrew/[A-Za-z0-9._-]*\.Brewfile' "${APPS_JUST}" | sort -u)"
    [ -n "${referenced}" ]
    while IFS= read -r path; do
        [ -f "${BREW_DIR}/$(basename "${path}")" ]
    done <<< "${referenced}"
}

@test "every custom-apps recipe declares a just group" {
    # ujust renders its menu by group; an ungrouped recipe disappears from it.
    local ungrouped
    ungrouped="$(awk '
        /^\[group\(/ { grouped=1; next }
        /^[a-z][A-Za-z0-9_-]*([ ][A-Za-z_]+)*:$/ {
            if (!grouped) print $0
            grouped=0
            next
        }
        /^[^[:space:]]/ { grouped=0 }
    ' "${APPS_JUST}")"
    [ -z "${ungrouped}" ]
}
