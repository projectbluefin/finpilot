#!/usr/bin/env bats
# Tests for custom/ujust/custom-apps.just recipes:
#   install-default-apps, install-dev-tools, install-fonts, install-all-brew,
#   install-flatpak, install-jetbrains-toolbox, and the plain delegating
#   recipes (jetbrains-toolbox, install-vscode, install-gimp).
#
# Each shebang recipe body is extracted out of the justfile into a standalone
# bash script and run against PATH mocks (brew/flatpak/curl/jq/tar/sha256sum),
# so Brewfile paths, Flathub remote ordering and the JetBrains checksum gate
# are exercised without touching the host or the network.

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
    ' "${APPS_JUST}" \
        | sed 's|{{ APP_ID }}|${APP_ID}|g' > "${out_file}"
    chmod +x "${out_file}"
    # Guard against a recipe rename silently producing an empty test subject.
    [ -s "${out_file}" ]
}

_write_mock() {
    local name="$1"
    cat > "${MOCKDIR}/${name}"
    chmod +x "${MOCKDIR}/${name}"
}

setup() {
    WORKDIR="$(mktemp -d)"
    MOCKDIR="${WORKDIR}/bin"
    COMMAND_LOG="${WORKDIR}/commands.log"
    mkdir -p "${MOCKDIR}" "${WORKDIR}/home"
    : > "${COMMAND_LOG}"

    _write_mock "brew" <<'MOCK'
#!/usr/bin/bash
echo "brew $*" >> "${COMMAND_LOG}"
exit "${MOCK_BREW_STATUS:-0}"
MOCK

    _write_mock "flatpak" <<'MOCK'
#!/usr/bin/bash
echo "flatpak $*" >> "${COMMAND_LOG}"
exit 0
MOCK

    _write_mock "ujust" <<'MOCK'
#!/usr/bin/bash
echo "ujust $*" >> "${COMMAND_LOG}"
exit 0
MOCK

    # curl serves the JetBrains releases feed, the tarball and the checksum.
    _write_mock "curl" <<'MOCK'
#!/usr/bin/bash
echo "curl $*" >> "${COMMAND_LOG}"
for arg in "$@"; do
    case "${arg}" in
        releases.json)
            cat > releases.json <<'JSON'
{"TBA":[{"build":"1.2.3","downloads":{"linux":{"link":"https://example.invalid/jetbrains-toolbox-1.2.3.tar.gz","checksumLink":"https://example.invalid/jetbrains-toolbox-1.2.3.tar.gz.sha256"}}}]}
JSON
            exit 0
            ;;
        *.tar.gz.sha256)
            echo "deadbeef  jetbrains-toolbox-1.2.3.tar.gz"
            exit 0
            ;;
        *.tar.gz)
            echo "tarball" > jetbrains-toolbox-1.2.3.tar.gz
            exit 0
            ;;
    esac
done
exit 0
MOCK

    # sha256sum -c is the integrity gate; MOCK_SHA_OK=0 makes it fail.
    _write_mock "sha256sum" <<'MOCK'
#!/usr/bin/bash
cat > /dev/null
echo "sha256sum $*" >> "${COMMAND_LOG}"
[ "${MOCK_SHA_OK:-1}" = "1" ] || { echo "checksum mismatch" >&2; exit 1; }
exit 0
MOCK

    # tar unpacks a fake toolbox tree so the final launch step has a binary.
    _write_mock "tar" <<'MOCK'
#!/usr/bin/bash
echo "tar $*" >> "${COMMAND_LOG}"
/usr/bin/mkdir -p jetbrains-toolbox-1.2.3/bin
{
    echo '#!/usr/bin/bash'
    echo 'echo "jetbrains-toolbox launched" >> "${COMMAND_LOG}"'
} > jetbrains-toolbox-1.2.3/bin/jetbrains-toolbox
/usr/bin/chmod +x jetbrains-toolbox-1.2.3/bin/jetbrains-toolbox
exit 0
MOCK

    export COMMAND_LOG
    export HOME="${WORKDIR}/home"
    # A minimal PATH keeps a real brew/flatpak on the runner from leaking in.
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

_log_line() {
    grep -nF -- "$1" "${COMMAND_LOG}" | head -n1 | cut -d: -f1
}

@test "install-default-apps bundles only the default Brewfile" {
    _run_recipe "install-default-apps"

    [ "${status}" -eq 0 ]
    grep -qF "brew bundle --file /usr/share/ublue-os/homebrew/default.Brewfile" "${COMMAND_LOG}"
    [ "$(grep -cF "brew bundle" "${COMMAND_LOG}")" -eq 1 ]
}

@test "install-dev-tools bundles only the development Brewfile" {
    _run_recipe "install-dev-tools"

    [ "${status}" -eq 0 ]
    grep -qF "brew bundle --file /usr/share/ublue-os/homebrew/development.Brewfile" "${COMMAND_LOG}"
    [ "$(grep -cF "brew bundle" "${COMMAND_LOG}")" -eq 1 ]
}

@test "install-fonts bundles only the fonts Brewfile" {
    _run_recipe "install-fonts"

    [ "${status}" -eq 0 ]
    grep -qF "brew bundle --file /usr/share/ublue-os/homebrew/fonts.Brewfile" "${COMMAND_LOG}"
    [ "$(grep -cF "brew bundle" "${COMMAND_LOG}")" -eq 1 ]
}

@test "install-all-brew bundles default, development and fonts in order" {
    _run_recipe "install-all-brew"

    [ "${status}" -eq 0 ]
    [ "$(grep -cF "brew bundle" "${COMMAND_LOG}")" -eq 3 ]
    default_line="$(_log_line "default.Brewfile")"
    dev_line="$(_log_line "development.Brewfile")"
    fonts_line="$(_log_line "fonts.Brewfile")"
    [ "${default_line}" -lt "${dev_line}" ]
    [ "${dev_line}" -lt "${fonts_line}" ]
}

@test "install-all-brew reports a failing bundle as a nonzero exit" {
    _run_recipe "install-all-brew" MOCK_BREW_STATUS=1

    [ "${status}" -ne 0 ]
    # No `set -e` in the recipe body: later bundles are still attempted, and the
    # exit status is that of the last brew invocation.
    [ "$(grep -cF "brew bundle" "${COMMAND_LOG}")" -eq 3 ]
}

@test "every Brewfile referenced by a recipe exists in custom/brew" {
    # Guards against a Brewfile rename that would leave ujust pointing at a
    # path the image never ships.
    local referenced
    referenced="$(grep -o '/usr/share/ublue-os/homebrew/[A-Za-z0-9._-]*\.Brewfile' "${APPS_JUST}" | sort -u)"
    [ -n "${referenced}" ]
    while IFS= read -r path; do
        [ -f "${BREW_DIR}/$(basename "${path}")" ]
    done <<< "${referenced}"
}

@test "install-flatpak adds the Flathub remote before installing" {
    _run_recipe "install-flatpak" APP_ID=org.example.App

    [ "${status}" -eq 0 ]
    remote_line="$(_log_line "flatpak remote-add --if-not-exists flathub")"
    install_line="$(_log_line "flatpak install -y flathub org.example.App")"
    [ -n "${remote_line}" ]
    [ -n "${install_line}" ]
    [ "${remote_line}" -lt "${install_line}" ]
}

@test "install-flatpak passes the app id through unmodified" {
    _run_recipe "install-flatpak" APP_ID=com.visualstudio.code

    [ "${status}" -eq 0 ]
    grep -qF "flatpak install -y flathub com.visualstudio.code" "${COMMAND_LOG}"
}

@test "install-jetbrains-toolbox verifies the checksum before extracting" {
    _run_recipe "install-jetbrains-toolbox"

    [ "${status}" -eq 0 ]
    sha_line="$(_log_line "sha256sum -c")"
    tar_line="$(_log_line "tar zxf")"
    [ -n "${sha_line}" ]
    [ -n "${tar_line}" ]
    [ "${sha_line}" -lt "${tar_line}" ]
}

@test "install-jetbrains-toolbox installs into HOME and launches the binary" {
    _run_recipe "install-jetbrains-toolbox"

    [ "${status}" -eq 0 ]
    [ -x "${HOME}/.local/share/JetBrains/ToolboxApp/bin/jetbrains-toolbox" ]
    grep -qF "jetbrains-toolbox launched" "${COMMAND_LOG}"
}

@test "install-jetbrains-toolbox: characterizes the un-gated checksum failure" {
    # KNOWN GAP (characterization test, not an endorsement): the recipe body
    # has no `set -euo pipefail`, so a failing `sha256sum -c` does not stop the
    # recipe — the unverified tarball is still extracted and executed. This test
    # pins the current behaviour so a future fix that adds the guard shows up as
    # an intentional, reviewed change to this assertion rather than a silent one.
    _run_recipe "install-jetbrains-toolbox" MOCK_SHA_OK=0

    grep -qF "sha256sum -c" "${COMMAND_LOG}"
    [ "$(grep -cF "tar zxf" "${COMMAND_LOG}")" -eq 1 ]
    [ -x "${HOME}/.local/share/JetBrains/ToolboxApp/bin/jetbrains-toolbox" ]
}

@test "install-jetbrains-toolbox resolves the build version from the releases feed" {
    _run_recipe "install-jetbrains-toolbox"

    [ "${status}" -eq 0 ]
    grep -qF "tar zxf jetbrains-toolbox-1.2.3.tar.gz" "${COMMAND_LOG}"
}

@test "delegating recipes call ujust with the documented targets" {
    # jetbrains-toolbox / install-vscode / install-gimp are plain (non-shebang)
    # recipes, so assert the command line each one delegates to.
    _recipe_body() {
        awk -v recipe="$1" '
            $0 ~ ("^" recipe ":$") { in_recipe=1; next }
            in_recipe && /^[^[:space:]]/ { exit }
            in_recipe { sub(/^[[:space:]@]+/, ""); if (length($0)) print }
        ' "${APPS_JUST}"
    }

    [ "$(_recipe_body "jetbrains-toolbox")" = "ujust install-jetbrains-toolbox" ]
    [ "$(_recipe_body "install-vscode")" = "ujust install-flatpak com.visualstudio.code" ]
    [ "$(_recipe_body "install-gimp")" = "ujust install-flatpak org.gimp.GIMP" ]
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
