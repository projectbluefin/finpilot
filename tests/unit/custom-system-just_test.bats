#!/usr/bin/env bats
# Tests for custom/ujust/custom-system.just recipes:
#   benchmark, configure-dev-groups, toggle-example-feature, clean-containers,
#   update-and-reboot.
#
# Each recipe body is extracted out of the justfile into a standalone bash
# script. Absolute host paths that a unit test must not touch are rewritten to
# sandbox equivalents:
#   /usr/lib/ujust/ujust.sh -> ${UJUST_LIB}          (stub providing Choose)
#   /etc/group              -> ${GROUP_FILE}
#   /usr/lib/group          -> ${SYSTEM_GROUP_FILE}
# Everything else (gum, brew, stress-ng, podman, bootc, sudo, systemctl,
# usermod) is a PATH mock, so nothing runs against the host.

SYSTEM_JUST="${BATS_TEST_DIRNAME}/../../custom/ujust/custom-system.just"
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
    ' "${SYSTEM_JUST}" \
        | sed -e 's|/usr/lib/ujust/ujust.sh|${UJUST_LIB}|g' \
              -e 's|/usr/lib/group|${SYSTEM_GROUP_FILE}|g' \
              -e 's|/etc/group|${GROUP_FILE}|g' \
              -e 's|{{ `id -un` }}|$(id -un)|g' > "${out_file}"
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
    mkdir -p "${MOCKDIR}"
    : > "${COMMAND_LOG}"

    # Stand-in for /usr/lib/ujust/ujust.sh: only Choose is used by these recipes.
    cat > "${WORKDIR}/ujust.sh" <<'LIB'
Choose() {
    echo "Choose $*" >> "${COMMAND_LOG}"
    echo "${MOCK_CHOICE:-Cancel}"
}
LIB

    # gum confirm honours MOCK_CONFIRM (0 = yes, 1 = no).
    _write_mock "gum" <<'MOCK'
#!/usr/bin/bash
echo "gum $*" >> "${COMMAND_LOG}"
[ "$1" = "confirm" ] && exit "${MOCK_CONFIRM:-0}"
exit 0
MOCK

    for cmd in brew stress-ng podman bootc systemctl usermod sudo; do
        _write_mock "${cmd}" <<MOCK
#!/usr/bin/bash
echo "${cmd} \$*" >> "\${COMMAND_LOG}"
exit "\${MOCK_${cmd//-/_}_STATUS:-0}"
MOCK
    done

    export COMMAND_LOG
    export UJUST_LIB="${WORKDIR}/ujust.sh"
    export GROUP_FILE="${WORKDIR}/etc-group"
    export SYSTEM_GROUP_FILE="${WORKDIR}/usr-lib-group"
    printf 'root:x:0:\n' > "${GROUP_FILE}"
    printf 'docker:x:970:\nlibvirt:x:971:\n' > "${SYSTEM_GROUP_FILE}"
    export HOME="${WORKDIR}/home"
    mkdir -p "${HOME}"
    # A minimal PATH keeps a real podman/bootc on the runner from leaking in.
    export PATH="${MOCKDIR}:/usr/bin:/bin"
}

teardown() {
    rm -rf "${WORKDIR}"
}

_run_recipe() {
    local recipe="$1"
    shift
    _extract_recipe "${recipe}" "${WORKDIR}/${recipe}.sh"
    run env PATH="${PATH}" HOME="${HOME}" COMMAND_LOG="${COMMAND_LOG}" \
        UJUST_LIB="${UJUST_LIB}" GROUP_FILE="${GROUP_FILE}" \
        SYSTEM_GROUP_FILE="${SYSTEM_GROUP_FILE}" "$@" \
        /usr/bin/bash "${WORKDIR}/${recipe}.sh"
}

_log_line() {
    grep -nF -- "$1" "${COMMAND_LOG}" | head -n1 | cut -d: -f1
}

@test "benchmark runs stress-ng directly when it is already installed" {
    _run_recipe "benchmark"

    [ "${status}" -eq 0 ]
    grep -qF "stress-ng --matrix 0 -t 1m --times" "${COMMAND_LOG}"
    [ "$(grep -cF "brew install" "${COMMAND_LOG}")" -eq 0 ]
    [ "$(grep -cF "gum confirm" "${COMMAND_LOG}")" -eq 0 ]
}

@test "benchmark offers a Homebrew install when stress-ng is missing" {
    rm "${MOCKDIR}/stress-ng"

    _run_recipe "benchmark" MOCK_CONFIRM=0

    grep -qF "gum confirm" "${COMMAND_LOG}"
    install_line="$(_log_line "brew install stress-ng")"
    link_line="$(_log_line "brew link stress-ng")"
    [ -n "${install_line}" ]
    [ -n "${link_line}" ]
    [ "${install_line}" -lt "${link_line}" ]
}

@test "benchmark declining the install exits cleanly without running stress-ng" {
    rm "${MOCKDIR}/stress-ng"

    _run_recipe "benchmark" MOCK_CONFIRM=1

    [ "${status}" -eq 0 ]
    [ "$(grep -cF "brew install" "${COMMAND_LOG}")" -eq 0 ]
    [ "$(grep -cF "stress-ng --matrix" "${COMMAND_LOG}")" -eq 0 ]
}

@test "benchmark fails when neither stress-ng nor brew is available" {
    rm "${MOCKDIR}/stress-ng" "${MOCKDIR}/brew"

    _run_recipe "benchmark"

    [ "${status}" -eq 1 ]
    [ "$(grep -cF "gum confirm" "${COMMAND_LOG}")" -eq 0 ]
    [[ "${output}" == *"Please install stress-ng"* ]]
}

@test "configure-dev-groups adds the user to docker and libvirt" {
    _run_recipe "configure-dev-groups"

    [ "${status}" -eq 0 ]
    grep -qE "usermod -aG docker " "${COMMAND_LOG}"
    grep -qE "usermod -aG libvirt " "${COMMAND_LOG}"
}

@test "configure-dev-groups seeds missing groups from the system group file" {
    _run_recipe "configure-dev-groups"

    [ "${status}" -eq 0 ]
    # /etc/group started with root only; both entries must be copied over.
    grep -q "^docker:" "${GROUP_FILE}"
    grep -q "^libvirt:" "${GROUP_FILE}"
}

@test "configure-dev-groups does not duplicate groups that already exist" {
    printf 'root:x:0:\ndocker:x:970:\nlibvirt:x:971:\n' > "${GROUP_FILE}"

    _run_recipe "configure-dev-groups"

    [ "${status}" -eq 0 ]
    [ "$(grep -c "^docker:" "${GROUP_FILE}")" -eq 1 ]
    [ "$(grep -c "^libvirt:" "${GROUP_FILE}")" -eq 1 ]
}

@test "configure-dev-groups runs under pkexec, not plain bash" {
    # The recipe mutates /etc/group and must keep its privilege-escalation
    # shebang; losing it would make the recipe fail for unprivileged users.
    run awk '
        /^configure-dev-groups:$/ { in_recipe=1; next }
        in_recipe { print; exit }
    ' "${SYSTEM_JUST}"

    [ "$(echo "${output}" | sed 's/^[[:space:]]*//')" = "#!/usr/bin/pkexec bash" ]
}

@test "toggle-example-feature Enable branch reports enabling" {
    _run_recipe "toggle-example-feature" MOCK_CHOICE=Enable

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Enabling feature"* ]]
    [[ "${output}" != *"Disabling feature"* ]]
}

@test "toggle-example-feature Disable branch reports disabling" {
    _run_recipe "toggle-example-feature" MOCK_CHOICE=Disable

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Disabling feature"* ]]
    [[ "${output}" != *"Enabling feature"* ]]
}

@test "toggle-example-feature Cancel branch changes nothing" {
    _run_recipe "toggle-example-feature" MOCK_CHOICE=Cancel

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"No changes made"* ]]
    [[ "${output}" != *"abling feature"* ]]
}

@test "toggle-example-feature offers exactly Enable, Disable and Cancel" {
    _run_recipe "toggle-example-feature" MOCK_CHOICE=Cancel

    grep -qF "Choose Enable Disable Cancel" "${COMMAND_LOG}"
}

@test "clean-containers prunes images before volumes" {
    _run_recipe "clean-containers"

    [ "${status}" -eq 0 ]
    system_line="$(_log_line "podman system prune -af")"
    volume_line="$(_log_line "podman volume prune -f")"
    [ -n "${system_line}" ]
    [ -n "${volume_line}" ]
    [ "${system_line}" -lt "${volume_line}" ]
}

@test "update-and-reboot upgrades then reboots when confirmed" {
    _run_recipe "update-and-reboot" MOCK_CONFIRM=0

    [ "${status}" -eq 0 ]
    upgrade_line="$(_log_line "bootc upgrade")"
    reboot_line="$(_log_line "systemctl reboot")"
    [ -n "${upgrade_line}" ]
    [ -n "${reboot_line}" ]
    [ "${upgrade_line}" -lt "${reboot_line}" ]
}

@test "update-and-reboot upgrades but skips the reboot when declined" {
    _run_recipe "update-and-reboot" MOCK_CONFIRM=1

    [ "${status}" -eq 0 ]
    grep -qF "bootc upgrade" "${COMMAND_LOG}"
    [ "$(grep -cF "systemctl reboot" "${COMMAND_LOG}")" -eq 0 ]
    [[ "${output}" == *"Reboot later"* ]]
}

@test "update-and-reboot escalates the upgrade with sudo" {
    _run_recipe "update-and-reboot" MOCK_CONFIRM=1

    grep -qF "sudo bootc upgrade" "${COMMAND_LOG}"
}

@test "every custom-system recipe declares a just group" {
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
    ' "${SYSTEM_JUST}")"
    [ -z "${ungrouped}" ]
}
