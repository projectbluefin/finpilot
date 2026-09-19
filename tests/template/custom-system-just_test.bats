#!/usr/bin/env bats
# Tests for custom/ujust/custom-system.just recipes:
#   configure-dev-groups, install-config.
#
# Each recipe body is extracted out of the justfile into a standalone bash
# script and run against PATH mocks, so nothing runs against the host.
#
# configure-dev-groups inspects the invoking user with `id` and `getent`, and
# decides who to change from those answers. install-config takes its source and
# target from SKEL_CONFIG and USER_CONFIG, so its tests drive real files in a
# sandbox instead of a mock.

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
    ' "${SYSTEM_JUST}" > "${out_file}"
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

    # gum confirm honours MOCK_CONFIRM (0 = yes, 1 = no).
    _write_mock "gum" <<'MOCK'
#!/usr/bin/bash
echo "gum $*" >> "${COMMAND_LOG}"
[ "$1" = "confirm" ] && exit "${MOCK_CONFIRM:-0}"
exit 0
MOCK

    for cmd in sudo groupadd usermod; do
        _write_mock "${cmd}" <<MOCK
#!/usr/bin/bash
echo "${cmd} \$*" >> "\${COMMAND_LOG}"
exit "\${MOCK_${cmd//-/_}_STATUS:-0}"
MOCK
    done

    # getent reports a missing group unless MOCK_GETENT_STATUS=0.
    _write_mock "getent" <<'MOCK'
#!/usr/bin/bash
echo "getent $*" >> "${COMMAND_LOG}"
exit "${MOCK_GETENT_STATUS:-1}"
MOCK

    # id answers for the invoking user; MOCK_GROUPS is that user's group list.
    _write_mock "id" <<'MOCK'
#!/usr/bin/bash
echo "id $*" >> "${COMMAND_LOG}"
case "$1" in
    -un) echo "${MOCK_USER:-tester}" ;;
    -nG) echo "${MOCK_GROUPS:-tester}" ;;
esac
MOCK

    export COMMAND_LOG
    export HOME="${WORKDIR}/home"
    mkdir -p "${HOME}"
    # A minimal PATH keeps a real id/getent on the runner from leaking in.
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

@test "configure-dev-groups creates missing groups and adds the user" {
    _run_recipe "configure-dev-groups" MOCK_GETENT_STATUS=1 MOCK_GROUPS="tester wheel"

    [ "${status}" -eq 0 ]
    grep -qF "sudo groupadd --system docker" "${COMMAND_LOG}"
    grep -qF "sudo groupadd --system libvirt" "${COMMAND_LOG}"
    grep -qF "sudo usermod --append --groups docker,libvirt tester" "${COMMAND_LOG}"
}

@test "configure-dev-groups does not recreate groups that already exist" {
    _run_recipe "configure-dev-groups" MOCK_GETENT_STATUS=0 MOCK_GROUPS="tester wheel"

    [ "${status}" -eq 0 ]
    [ "$(grep -cF "groupadd" "${COMMAND_LOG}")" -eq 0 ]
    grep -qF "sudo usermod --append --groups docker,libvirt tester" "${COMMAND_LOG}"
}

@test "configure-dev-groups adds only the groups the user is missing" {
    _run_recipe "configure-dev-groups" MOCK_GETENT_STATUS=0 MOCK_GROUPS="tester docker"

    [ "${status}" -eq 0 ]
    grep -qF "Add tester to: libvirt?" "${COMMAND_LOG}"
    grep -qF "sudo usermod --append --groups libvirt tester" "${COMMAND_LOG}"
}

@test "configure-dev-groups changes nothing when access is already complete" {
    _run_recipe "configure-dev-groups" MOCK_GETENT_STATUS=0 MOCK_GROUPS="tester docker libvirt"

    [ "${status}" -eq 0 ]
    [ "$(grep -cF "usermod" "${COMMAND_LOG}")" -eq 0 ]
    [ "$(grep -cF "gum confirm" "${COMMAND_LOG}")" -eq 0 ]
    [[ "${output}" == *"tester is already in: docker libvirt"* ]]
}

@test "configure-dev-groups cancels without changing anything" {
    _run_recipe "configure-dev-groups" MOCK_GETENT_STATUS=0 MOCK_GROUPS="tester" MOCK_CONFIRM=1

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Cancelled."* ]]
    [ "$(grep -cF "usermod" "${COMMAND_LOG}")" -eq 0 ]
}

@test "configure-dev-groups escalates only its mutating commands" {
    # The checks must run as the invoking user, so there is no pkexec shebang;
    # groupadd and usermod are the only things that need root.
    local shebang
    shebang="$(awk '/^configure-dev-groups:$/ { in_recipe=1; next }
        in_recipe { print; exit }' "${SYSTEM_JUST}" | sed 's/^[[:space:]]*//')"
    [ "${shebang}" = "#!/usr/bin/env bash" ]

    _run_recipe "configure-dev-groups" MOCK_GETENT_STATUS=1 MOCK_GROUPS="tester"
    [ "$(grep -cvE '^sudo (groupadd|usermod) |^(id|getent|gum) ' "${COMMAND_LOG}")" -eq 0 ]
}

@test "install-config copies the seeded config into the user's home" {
    mkdir -p "${WORKDIR}/skel/app" "${WORKDIR}/skel/environment.d"
    printf 'default\n' > "${WORKDIR}/skel/app/config.conf"
    printf 'env\n' > "${WORKDIR}/skel/environment.d/10-example.conf"

    _run_recipe "install-config" SKEL_CONFIG="${WORKDIR}/skel"

    [ "${status}" -eq 0 ]
    [ "$(cat "${HOME}/.config/app/config.conf")" = "default" ]
    [ "$(cat "${HOME}/.config/environment.d/10-example.conf")" = "env" ]
}

@test "install-config backs up a file instead of overwriting it" {
    mkdir -p "${WORKDIR}/skel/app" "${HOME}/.config/app"
    printf 'default\n' > "${WORKDIR}/skel/app/config.conf"
    printf 'mine\n' > "${HOME}/.config/app/config.conf"

    _run_recipe "install-config" SKEL_CONFIG="${WORKDIR}/skel"

    [ "${status}" -eq 0 ]
    [ "$(cat "${HOME}/.config/app/config.conf")" = "default" ]
    backup="$(ls "${HOME}/.config/app/"config.conf.backup.* 2>/dev/null | head -n1)"
    [ -n "${backup}" ]
    [ "$(cat "${backup}")" = "mine" ]
}

@test "install-config lists the conflicts it is about to back up" {
    mkdir -p "${WORKDIR}/skel/app" "${HOME}/.config/app"
    printf 'default\n' > "${WORKDIR}/skel/app/config.conf"
    printf 'mine\n' > "${HOME}/.config/app/config.conf"

    _run_recipe "install-config" SKEL_CONFIG="${WORKDIR}/skel"

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Already present, and will be backed up first:"* ]]
    [[ "${output}" == *"- app/config.conf"* ]]
}

@test "install-config cancels without touching anything" {
    mkdir -p "${WORKDIR}/skel/app"
    printf 'default\n' > "${WORKDIR}/skel/app/config.conf"

    _run_recipe "install-config" SKEL_CONFIG="${WORKDIR}/skel" MOCK_CONFIRM=1

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Cancelled."* ]]
    [ ! -e "${HOME}/.config/app/config.conf" ]
}

@test "install-config fails when the seed directory is absent" {
    _run_recipe "install-config" SKEL_CONFIG="${WORKDIR}/nope"

    [ "${status}" -eq 1 ]
    [[ "${output}" == *"does not exist"* ]]
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
