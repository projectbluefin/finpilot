#!/usr/bin/env bats
# Unit tests for the Bootc Image Builder path: the private `_build-bib` recipe,
# the three public recipes that feed it (`build-qcow2`, `build-raw`,
# `build-iso`), and the two BIB configs in iso/ they name.
#
# `_build-bib` is the only recipe that turns the container image into something
# a machine can boot, and nothing exercised it. Its decisions are invisible
# until an ISO is in a user's hands: an ISO built against the local build tag
# gives the installed system a `bootc switch` origin pointing at
# `localhost/finpilot`, which no host can ever pull an update from, and the
# recipe deliberately re-derives the published reference from the image's own
# image-info.json to avoid exactly that. It also builds under `sudo podman run`
# into a temporary directory inside the repository, so a failure that skips the
# cleanup trap leaves a root-owned `_build-bib.*` tree in the working copy.
#
# The recipes are exercised against a sandbox copy of the Justfile. `podman`,
# `sudo`, `jq` and `mktemp` come from stubs on PATH that record their argv, so
# the tests assert on the argument vector `bootc-image-builder` would have
# received without running a privileged container or building a disk.
#
# The Justfile reaches the privileged commands through its own `sudoif`
# dispatcher, which hardcodes `/usr/bin/sudo` and cannot be stubbed; its root
# branch runs the command directly instead. The suite therefore runs inside a
# `unshare -r` user namespace, where the caller is uid 0 and that root branch is
# taken. Hosts without unprivileged user namespaces skip rather than escalate.
#
# Run with: bats tests/template/justfile-build-bib_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."

setup() {
    if ! command -v just &>/dev/null; then
        skip "just is not installed"
    fi
    if ! command -v unshare &>/dev/null || ! unshare -r true 2>/dev/null; then
        skip "unprivileged user namespaces are unavailable; refusing to run the privileged recipes for real"
    fi

    TEST_ROOT="${BATS_TEST_TMPDIR:-${BATS_TMPDIR}}/justfile-build-bib.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/stub-bin"
    SANDBOX="${TEST_ROOT}/repo"
    PODMAN_LOG="${TEST_ROOT}/logs/podman.log"
    SUDO_LOG="${TEST_ROOT}/logs/sudo.log"

    mkdir -p "${STUB_BIN}" "${TEST_ROOT}/logs" "${SANDBOX}/iso"

    cp "${REPO_ROOT}/Justfile" "${SANDBOX}/Justfile"
    cp "${REPO_ROOT}/iso/disk.toml" "${SANDBOX}/iso/disk.toml"
    cp "${REPO_ROOT}/iso/iso.toml" "${SANDBOX}/iso/iso.toml"

    export PATH="${STUB_BIN}:${PATH}"
    export PODMAN_LOG SUDO_LOG

    # What the `podman run --entrypoint /usr/bin/cat` of image-info.json
    # reports. The ISO path reads the published reference out of this.
    export STUB_IMAGE_INFO='{"image-ref":"ostree-image-signed:docker://ghcr.io/projectbluefin/finpilot","image-tag":"stable"}'
    # Exit status for the BIB `podman run`; non-zero drives the cleanup trap.
    export STUB_BIB_STATUS=0

    cat >"${STUB_BIN}/podman" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${PODMAN_LOG}"
case "$1" in
    images) printf '%s\n' "sha256:deadbeef" ;;
    run)
        # The image-info.json read and the BIB run are both `podman run`.
        if [[ "$*" == *"/usr/share/ublue-os/image-info.json"* ]]; then
            printf '%s\n' "${STUB_IMAGE_INFO}"
            exit 0
        fi
        # Stand in for the disk BIB writes into the bind-mounted /output.
        outdir=""
        prev=""
        for arg in "$@"; do
            [[ "${prev}" == "-v" && "${arg}" == *":/output" ]] && outdir="${arg%%:/output}"
            prev="${arg}"
        done
        if [[ -n "${outdir}" && "${STUB_BIB_STATUS:-0}" -eq 0 ]]; then
            mkdir -p "${outdir}/qcow2"
            printf 'disk\n' >"${outdir}/qcow2/disk.qcow2"
        fi
        exit "${STUB_BIB_STATUS:-0}"
        ;;
esac
exit 0
EOF

    # `sudoif` runs its argument vector directly as uid 0, but `_build-bib`
    # also calls `sudo` by name for the build, the move and the chown.
    cat >"${STUB_BIN}/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${SUDO_LOG}"
exec "$@"
EOF

    chmod +x "${STUB_BIN}"/*
}

teardown() {
    chmod -R u+w "${TEST_ROOT}" 2>/dev/null || true
    rm -rf "${TEST_ROOT}"
}

# Runs a recipe in the sandbox inside a user namespace, so `sudoif` takes its
# uid-0 branch and every privileged command lands on the stubs.
run_just() {
    run unshare -r bash -c "cd '${SANDBOX}' && just \"\$@\"" _ "$@"
}

# The single recorded BIB `podman run` argv line (not the image-info read).
bib_run_args() {
    grep '^run ' "${PODMAN_LOG}" | grep -v 'image-info.json' | head -n1
}

@test "build-qcow2: passes the qcow2 type and the fixed BIB flags" {
    run_just build-qcow2
    [ "$status" -eq 0 ]
    args="$(bib_run_args)"
    [[ "${args}" == *"--type qcow2"* ]]
    # --use-librepo picks BIB's supported repository backend, and the image is
    # btrfs everywhere else in this template; both are recipe-level choices
    # that no config file restates.
    [[ "${args}" == *"--use-librepo=True"* ]]
    [[ "${args}" == *"--rootfs=btrfs"* ]]
}

@test "build-raw: passes the raw type, not the qcow2 one" {
    run_just build-raw
    [ "$status" -eq 0 ]
    args="$(bib_run_args)"
    [[ "${args}" == *"--type raw"* ]]
    [[ "${args}" != *"--type qcow2"* ]]
}

@test "build-iso: passes the iso type" {
    run_just build-iso
    [ "$status" -eq 0 ]
    args="$(bib_run_args)"
    [[ "${args}" == *"--type iso"* ]]
}

@test "build-qcow2 and build-raw mount iso/disk.toml as the BIB config" {
    run_just build-qcow2
    [ "$status" -eq 0 ]
    [[ "$(bib_run_args)" == *"iso/disk.toml:/config.toml:ro"* ]]

    # `sudo mv -f "${BUILDTMP}"/* output/` cannot replace an export directory
    # that is already there, so a second build in the same tree needs the
    # state `just clean` leaves behind.
    : >"${PODMAN_LOG}"
    rm -rf "${SANDBOX}/output"
    run_just build-raw
    [ "$status" -eq 0 ]
    [[ "$(bib_run_args)" == *"iso/disk.toml:/config.toml:ro"* ]]
}

@test "build-iso mounts iso/iso.toml, not the disk config" {
    # The two configs are not interchangeable: iso.toml carries the Anaconda
    # kickstart and module table, disk.toml carries a partition size.
    run_just build-iso
    [ "$status" -eq 0 ]
    args="$(bib_run_args)"
    [[ "${args}" == *"iso/iso.toml:/config.toml:ro"* ]]
    [[ "${args}" != *"disk.toml"* ]]
}

@test "build-iso builds against the published reference from image-info.json" {
    # An ISO built against localhost/finpilot installs a system whose bootc
    # origin is localhost/finpilot, which never updates. The recipe reads the
    # real reference out of the image instead of hardcoding one.
    run_just build-iso
    [ "$status" -eq 0 ]
    args="$(bib_run_args)"
    [[ "${args}" == *"ghcr.io/projectbluefin/finpilot:stable"* ]]
    [[ "${args}" != *"localhost/finpilot:stable"* ]]
}

@test "build-iso strips the ostree transport prefix from image-ref" {
    # image-ref is an ostree source URI; BIB wants a bare registry reference.
    export STUB_IMAGE_INFO='{"image-ref":"ostree-image-signed:docker://ghcr.io/example/img","image-tag":"testing"}'
    run_just build-iso
    [ "$status" -eq 0 ]
    args="$(bib_run_args)"
    [[ "${args}" == *"ghcr.io/example/img:testing"* ]]
    [[ "${args}" != *"docker://"* ]]
    [[ "${args}" != *"ostree-image-signed"* ]]
}

@test "build-iso tags the local image with the published reference first" {
    # BIB is given a reference that must resolve in local storage.
    run_just build-iso
    [ "$status" -eq 0 ]
    grep -qF "tag localhost/finpilot:stable ghcr.io/projectbluefin/finpilot:stable" "${PODMAN_LOG}"
}

@test "build-qcow2 never reads image-info.json and never re-tags" {
    # The published-reference dance is ISO-only; a local disk image is built
    # from the tag the caller named.
    run_just build-qcow2
    [ "$status" -eq 0 ]
    ! grep -q 'image-info.json' "${PODMAN_LOG}"
    ! grep -q '^tag ' "${PODMAN_LOG}"
    [[ "$(bib_run_args)" == *"localhost/finpilot:stable"* ]]
}

@test "build-qcow2 honours an explicit target image and tag" {
    run_just build-qcow2 localhost/fork-image testing
    [ "$status" -eq 0 ]
    [[ "$(bib_run_args)" == *"localhost/fork-image:testing"* ]]
}

@test "_build-bib runs the digest-pinned bootc-image-builder image" {
    # A floating :latest would silently change the disk layout between two
    # builds of the same commit.
    run_just build-qcow2
    [ "$status" -eq 0 ]
    pinned=$(grep -m1 '^export bib_image' "${REPO_ROOT}/Justfile")
    [[ "${pinned}" == *"@sha256:"* ]]
    digest="${pinned##*@}"
    digest="${digest%%\"*}"
    [[ "$(bib_run_args)" == *"@${digest}"* ]]
}

@test "_build-bib honours the BIB_IMAGE override" {
    BIB_IMAGE="example.invalid/bib:pinned" run_just build-qcow2
    [ "$status" -eq 0 ]
    [[ "$(bib_run_args)" == *"example.invalid/bib:pinned"* ]]
}

@test "_build-bib gives BIB the privileges and mounts it needs" {
    run_just build-qcow2
    [ "$status" -eq 0 ]
    args="$(bib_run_args)"
    [[ "${args}" == *"--privileged"* ]]
    [[ "${args}" == *"--net=host"* ]]
    # BIB's osbuild stages are denied by the container policy without this.
    [[ "${args}" == *"--security-opt label=type:unconfined_t"* ]]
    # BIB reads the built image out of the host's root container storage,
    # which is why _rootful_load_image had to put it there first.
    [[ "${args}" == *"/var/lib/containers/storage:/var/lib/containers/storage"* ]]
    [[ "${args}" == *"--rm"* ]]
}

@test "_build-bib escalates the BIB run, the move and the ownership fix" {
    run_just build-qcow2
    [ "$status" -eq 0 ]
    grep -q '^podman run' "${SUDO_LOG}"
    grep -q '^mv -f' "${SUDO_LOG}"
    grep -q '^chown -R' "${SUDO_LOG}"
}

@test "_build-bib moves the artifact into output/ and leaves no temp tree" {
    run_just build-qcow2
    [ "$status" -eq 0 ]
    [ -f "${SANDBOX}/output/qcow2/disk.qcow2" ]
    run bash -c "ls -d '${SANDBOX}'/_build-bib.* 2>/dev/null"
    [ "$status" -ne 0 ]
}

@test "_build-bib removes its temp tree when the build fails" {
    # The temp directory is created inside the repository (BIB needs it on the
    # same filesystem as output/), so a failure that skips the trap leaves a
    # root-owned directory in the working copy for the next `just build` to
    # trip over.
    STUB_BIB_STATUS=1 run_just build-qcow2
    [ "$status" -ne 0 ]
    run bash -c "ls -d '${SANDBOX}'/_build-bib.* 2>/dev/null"
    [ "$status" -ne 0 ]
    [ ! -d "${SANDBOX}/output/qcow2" ]
}

@test "_build-bib completes with USER unset" {
    # These recipes run from cron, containers and systemd under `set -u`,
    # where USER was never exported. Reading it would abort after a 15-25
    # minute build, with the disk already written. The Justfile grep in
    # justfile-build_test.bats states the rule; this runs it.
    run unshare -r env -u USER bash -c "cd '${SANDBOX}' && just build-qcow2"
    [ "$status" -eq 0 ]
    [ -f "${SANDBOX}/output/qcow2/disk.qcow2" ]
}

@test "iso/disk.toml sizes the root filesystem it is the only source of" {
    # disk.toml exists solely to stop BIB defaulting the root to the base
    # container's size; an empty table would build a disk with no room.
    run grep -c 'customizations.filesystem' "${REPO_ROOT}/iso/disk.toml"
    [ "$status" -eq 0 ]
    grep -qE '^mountpoint = "/"$' "${REPO_ROOT}/iso/disk.toml"
    grep -qE '^minsize = "[0-9]+ GiB"$' "${REPO_ROOT}/iso/disk.toml"
}

@test "iso/iso.toml keeps a kickstart table so BIB does not inject clearpart" {
    # With no kickstart table at all, bootc-image-builder writes its own
    # containing clearpart --all, autopart --nohome and reboot --eject, and
    # the ISO wipes the first disk without asking. The table's presence is the
    # whole defence; its contents are deliberately only a comment.
    grep -qF '[customizations.installer.kickstart]' "${REPO_ROOT}/iso/iso.toml"
    grep -qF 'contents = """' "${REPO_ROOT}/iso/iso.toml"
    ! grep -qE '^[^#]*clearpart' "${REPO_ROOT}/iso/iso.toml"
    ! grep -qE '^[^#]*autopart' "${REPO_ROOT}/iso/iso.toml"
}

@test "iso/iso.toml carries no image reference" {
    # The Justfile comment at _build-bib states that the published reference
    # has exactly one source, image-info.json. A reference restated here is a
    # second one that drifts silently on a fork.
    ! grep -qE '^[^#]*(ghcr\.io|quay\.io|docker://|image-ref)' "${REPO_ROOT}/iso/iso.toml"
}

@test "iso/iso.toml disables the Subscription module and enables Timezone" {
    # The module table is the only Anaconda behaviour this template pins. An
    # enabled Subscription module asks a community user to register with a
    # vendor that has no account for them.
    grep -qF 'org.fedoraproject.Anaconda.Modules.Timezone' "${REPO_ROOT}/iso/iso.toml"
    grep -qE '^disable = .*Subscription' "${REPO_ROOT}/iso/iso.toml"
}

@test "every BIB recipe names a config file that exists" {
    # `-v ${PWD}/${config}:/config.toml:ro` with a missing path makes podman
    # create a directory there, and BIB fails deep inside the container with a
    # config parse error instead of at the recipe.
    found=0
    while read -r config; do
        [ -f "${REPO_ROOT}/${config}" ]
        found=$((found + 1))
    done < <(grep -oE '"iso/[a-z]+\.toml"' "${REPO_ROOT}/Justfile" | tr -d '"' | sort -u)
    [ "${found}" -ge 2 ]
}
