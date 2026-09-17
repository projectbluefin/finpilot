#!/usr/bin/env bats
# Unit tests for the root Justfile virtual-machine recipes:
#   _rootful_load_image, _build-bib and _run-vm
#
# These three recipes carry every decision the disk/ISO image pipeline makes —
# whether to copy a user-podman image into rootful storage or pull it fresh,
# which bootc-image-builder argv is assembled, where the artifacts land, which
# image file a VM type maps to, and which host port the VM is published on.
# None of it was executed by the suite before, so a regression in any of them
# only surfaced when a maintainer ran a real 20-minute image build.
#
# The recipes are exercised against a sandbox copy of the Justfile so the real
# repository is never touched, and every external command they shell out to
# (podman, sudo, chown, jq, ss, xdg-open, sleep, and the nested `just`
# invocations) is replaced by a stub on PATH that records its argv. Nothing
# here starts a container, escalates privileges or touches the network.
#
# Run with: bats tests/unit/justfile-vm-recipes_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."

setup() {
    if ! command -v just &>/dev/null; then
        skip "just is not installed"
    fi
    # Resolved before PATH is shadowed: the tests drive the real `just`, while
    # the recipes' own nested `just ...` calls hit the stub.
    JUST_BIN="$(command -v just)"

    TEST_ROOT="${BATS_TEST_TMPDIR:-${BATS_TMPDIR}}/justfile-vm.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/stub-bin"
    SANDBOX="${TEST_ROOT}/repo"
    PODMAN_LOG="${TEST_ROOT}/logs/podman.log"
    JUST_LOG="${TEST_ROOT}/logs/just.log"
    SUDO_LOG="${TEST_ROOT}/logs/sudo.log"
    OPEN_LOG="${TEST_ROOT}/logs/xdg-open.log"

    mkdir -p "${STUB_BIN}" "${TEST_ROOT}/logs" "${SANDBOX}/iso"
    : >"${PODMAN_LOG}"
    : >"${JUST_LOG}"
    : >"${SUDO_LOG}"
    : >"${OPEN_LOG}"

    cp "${REPO_ROOT}/Justfile" "${SANDBOX}/Justfile"
    printf 'dummy = "disk"\n' >"${SANDBOX}/iso/disk.toml"
    printf 'dummy = "iso"\n' >"${SANDBOX}/iso/iso.toml"

    export PODMAN_LOG JUST_LOG SUDO_LOG OPEN_LOG

    # `podman inspect` exit status decides scp-vs-pull in _rootful_load_image.
    export STUB_PODMAN_INSPECT_STATUS=0
    # Image ID reported for the calling user's podman storage.
    export STUB_USER_IMG_ID="sha256:user"
    # Image ID the nested `just sudoif podman images` (root storage) reports.
    export STUB_ROOT_IMG_ID="sha256:user"
    # Sockets `ss -tunalp` claims are already bound; drives port selection.
    export STUB_SS_OUTPUT=""

    cat >"${STUB_BIN}/podman" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${PODMAN_LOG}"
case "$1" in
    inspect)
        if [[ "${STUB_PODMAN_INSPECT_STATUS:-0}" -ne 0 ]]; then
            echo "podman: stub: no such image" >&2
            exit "${STUB_PODMAN_INSPECT_STATUS}"
        fi
        printf '%s\n' '[{"RepoTags":["stub:latest"]}]'
        ;;
    images)
        printf '%s\n' "${STUB_USER_IMG_ID:-}"
        ;;
    run)
        # Emulate bootc-image-builder writing into the bind-mounted /output.
        for arg in "$@"; do
            if [[ "${arg}" == *":/output" ]]; then
                mkdir -p "${arg%%:/output}/qcow2"
                printf 'disk\n' >"${arg%%:/output}/qcow2/disk.qcow2"
            fi
        done
        ;;
esac
exit 0
EOF

    # Nested `just` calls made from inside a recipe body. The root-storage image
    # lookup must answer with an ID so the scp-vs-skip branch can be asserted.
    cat >"${STUB_BIN}/just" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${JUST_LOG}"
if [[ "$*" == *"podman images"* ]]; then
    printf '%s\n' "${STUB_ROOT_IMG_ID:-}"
fi
exit 0
EOF

    # `sudo` is recorded and then transparently executes its argv, so the
    # stubbed podman/mv/rmdir/chown underneath still run.
    cat >"${STUB_BIN}/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${SUDO_LOG}"
exec "$@"
EOF

    # Real chown would need privileges the test runner does not have.
    cat >"${STUB_BIN}/chown" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

    cat >"${STUB_BIN}/jq" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf '%s\n' "stub:latest"
EOF

    cat >"${STUB_BIN}/ss" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${STUB_SS_OUTPUT:-}"
EOF

    cat >"${STUB_BIN}/xdg-open" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${OPEN_LOG}"
EOF

    # The recipe backgrounds `sleep 30` before opening a browser; the tests must
    # not pay for it.
    cat >"${STUB_BIN}/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

    chmod +x "${STUB_BIN}"/*
    export PATH="${STUB_BIN}:${PATH}"
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

run_just() {
    run bash -c "cd '${SANDBOX}' && '${JUST_BIN}' \"\$@\"" _ "$@"
}

# --- _rootful_load_image ------------------------------------------------------

@test "_rootful_load_image: short-circuits under sudo without inspecting podman" {
    SUDO_USER="tester" run_just _rootful_load_image localhost/finpilot stable
    [ "$status" -eq 0 ]
    [[ "$output" == *"Already root or running under sudo"* ]]
    [ ! -s "${PODMAN_LOG}" ]
    [ ! -s "${JUST_LOG}" ]
}

@test "_rootful_load_image: skips the copy when root storage already has the image" {
    export STUB_USER_IMG_ID="sha256:same"
    export STUB_ROOT_IMG_ID="sha256:same"
    run_just _rootful_load_image localhost/finpilot stable
    [ "$status" -eq 0 ]
    ! grep -q 'podman image scp' "${JUST_LOG}"
    ! grep -q 'podman pull' "${JUST_LOG}"
}

@test "_rootful_load_image: copies user storage to root when the IDs differ" {
    export STUB_USER_IMG_ID="sha256:user"
    export STUB_ROOT_IMG_ID="sha256:root"
    run_just _rootful_load_image localhost/finpilot stable
    [ "$status" -eq 0 ]
    grep -q "podman image scp ${UID}@localhost::localhost/finpilot:stable root@localhost::localhost/finpilot:stable" "${JUST_LOG}"
    ! grep -q 'podman pull' "${JUST_LOG}"
}

@test "_rootful_load_image: routes the copy through a TMPDIR it cleans up" {
    export STUB_USER_IMG_ID="sha256:user"
    export STUB_ROOT_IMG_ID="sha256:root"
    run_just _rootful_load_image localhost/finpilot stable
    [ "$status" -eq 0 ]
    grep -qE "sudoif TMPDIR=${SANDBOX}/_build_podman_scp\.[A-Za-z0-9]+ podman image scp " "${JUST_LOG}"
    # The staging directory must not survive the recipe.
    run bash -c "ls -d '${SANDBOX}'/_build_podman_scp.* 2>/dev/null"
    [ "$status" -ne 0 ]
}

@test "_rootful_load_image: pulls into root storage when the image is unknown locally" {
    export STUB_PODMAN_INSPECT_STATUS=1
    run_just _rootful_load_image localhost/finpilot stable
    [ "$status" -eq 0 ]
    grep -qFx 'sudoif podman pull localhost/finpilot:stable' "${JUST_LOG}"
    ! grep -q 'podman image scp' "${JUST_LOG}"
}

# --- _build-bib ---------------------------------------------------------------

# The dependency recipe is short-circuited via SUDO_USER so these tests only
# assert on the bootc-image-builder invocation itself.
#
# USER is exported explicitly: `_build-bib` ends with `sudo chown -R $USER:$USER
# output/` under `set -u`, so the recipe only completes in an environment that
# already defines USER.
run_build_bib() {
    SUDO_USER="tester" USER="tester" run_just _build-bib "$@"
}

bib_run_args() {
    grep -m1 '^run ' "${PODMAN_LOG}"
}

@test "_build-bib: passes the requested type and the fixed librepo/btrfs flags" {
    run_build_bib localhost/finpilot stable qcow2 iso/disk.toml
    [ "$status" -eq 0 ]
    [[ "$(bib_run_args)" == *"--type qcow2 --use-librepo=True --rootfs=btrfs"* ]]
}

@test "_build-bib: mounts the requested config read-only at /config.toml" {
    run_build_bib localhost/finpilot stable iso iso/iso.toml
    [ "$status" -eq 0 ]
    [[ "$(bib_run_args)" == *"-v ${SANDBOX}/iso/iso.toml:/config.toml:ro"* ]]
    [[ "$(bib_run_args)" == *"--type iso"* ]]
}

@test "_build-bib: builds the requested image reference and shares host storage" {
    run_build_bib localhost/finpilot testing raw iso/disk.toml
    [ "$status" -eq 0 ]
    [[ "$(bib_run_args)" == *"-v /var/lib/containers/storage:/var/lib/containers/storage"* ]]
    [[ "$(bib_run_args)" == *"localhost/finpilot:testing"* ]]
}

@test "_build-bib: honours the BIB_IMAGE override for the builder image" {
    BIB_IMAGE="example.invalid/bib:pinned" run_build_bib localhost/finpilot stable qcow2 iso/disk.toml
    [ "$status" -eq 0 ]
    [[ "$(bib_run_args)" == *"example.invalid/bib:pinned"* ]]
}

@test "_build-bib: defaults to the digest-pinned bootc-image-builder" {
    run_build_bib localhost/finpilot stable qcow2 iso/disk.toml
    [ "$status" -eq 0 ]
    [[ "$(bib_run_args)" == *"quay.io/centos-bootc/bootc-image-builder:latest@sha256:"* ]]
}

@test "_build-bib: runs the builder privileged with an unconfined label" {
    run_build_bib localhost/finpilot stable qcow2 iso/disk.toml
    [ "$status" -eq 0 ]
    [[ "$(bib_run_args)" == *"--privileged"* ]]
    [[ "$(bib_run_args)" == *"--security-opt label=type:unconfined_t"* ]]
}

@test "_build-bib: relocates artifacts into output/ and removes the staging dir" {
    run_build_bib localhost/finpilot stable qcow2 iso/disk.toml
    [ "$status" -eq 0 ]
    [ -f "${SANDBOX}/output/qcow2/disk.qcow2" ]
    run bash -c "ls -d '${SANDBOX}'/_build-bib.* 2>/dev/null"
    [ "$status" -ne 0 ]
}

@test "_build-bib: escalates only for the container run and the artifact move" {
    run_build_bib localhost/finpilot stable qcow2 iso/disk.toml
    [ "$status" -eq 0 ]
    grep -q '^podman run ' "${SUDO_LOG}"
    grep -q '^mv -f ' "${SUDO_LOG}"
    grep -q '^chown -R tester:tester output/' "${SUDO_LOG}"
}

@test "_build-bib: currently aborts with 'USER: unbound variable' when USER is undefined" {
    # Characterization test for a live defect, not a desired behavior: the final
    # `sudo chown -R $USER:$USER output/` runs under `set -u`, so in an
    # environment without USER (container, cron, systemd unit) the recipe fails
    # AFTER the image has been built, leaving output/ owned by root.
    # Update this test when the recipe learns a fallback for USER.
    SUDO_USER="tester" run bash -c "cd '${SANDBOX}' && unset USER && '${JUST_BIN}' _build-bib localhost/finpilot stable qcow2 iso/disk.toml"
    [ "$status" -ne 0 ]
    [[ "$output" == *"USER: unbound variable"* ]]
}

# --- _run-vm ------------------------------------------------------------------

vm_run_args() {
    grep -m1 '^run ' "${PODMAN_LOG}"
}

@test "_run-vm: builds the disk image first when it is missing" {
    run_just _run-vm localhost/finpilot stable qcow2 iso/disk.toml
    [ "$status" -eq 0 ]
    grep -qFx 'build-qcow2 localhost/finpilot stable' "${JUST_LOG}"
}

@test "_run-vm: does not rebuild when the disk image already exists" {
    mkdir -p "${SANDBOX}/output/qcow2"
    printf 'disk\n' >"${SANDBOX}/output/qcow2/disk.qcow2"
    run_just _run-vm localhost/finpilot stable qcow2 iso/disk.toml
    [ "$status" -eq 0 ]
    ! grep -q '^build-' "${JUST_LOG}"
}

@test "_run-vm: maps the iso type to output/bootiso/install.iso" {
    mkdir -p "${SANDBOX}/output/bootiso"
    printf 'iso\n' >"${SANDBOX}/output/bootiso/install.iso"
    run_just _run-vm localhost/finpilot stable iso iso/iso.toml
    [ "$status" -eq 0 ]
    ! grep -q '^build-' "${JUST_LOG}"
    [[ "$(vm_run_args)" == *"--volume ${SANDBOX}/output/bootiso/install.iso:/boot.iso"* ]]
}

@test "_run-vm: maps a non-iso type to output/<type>/disk.<type>" {
    mkdir -p "${SANDBOX}/output/raw"
    printf 'disk\n' >"${SANDBOX}/output/raw/disk.raw"
    run_just _run-vm localhost/finpilot stable raw iso/disk.toml
    [ "$status" -eq 0 ]
    [[ "$(vm_run_args)" == *"--volume ${SANDBOX}/output/raw/disk.raw:/boot.raw"* ]]
}

@test "_run-vm: publishes 8006 on loopback when nothing is bound" {
    mkdir -p "${SANDBOX}/output/qcow2"
    printf 'disk\n' >"${SANDBOX}/output/qcow2/disk.qcow2"
    run_just _run-vm localhost/finpilot stable qcow2 iso/disk.toml
    [ "$status" -eq 0 ]
    [[ "$output" == *"Using Port: 8006"* ]]
    [[ "$(vm_run_args)" == *"--publish 127.0.0.1:8006:8006"* ]]
}

@test "_run-vm: walks past ports already in use" {
    mkdir -p "${SANDBOX}/output/qcow2"
    printf 'disk\n' >"${SANDBOX}/output/qcow2/disk.qcow2"
    export STUB_SS_OUTPUT="tcp LISTEN 0 4096 127.0.0.1:8006 0.0.0.0:* users:((x,pid=1,fd=3))
tcp LISTEN 0 4096 127.0.0.1:8007 0.0.0.0:* users:((y,pid=2,fd=3))"
    run_just _run-vm localhost/finpilot stable qcow2 iso/disk.toml
    [ "$status" -eq 0 ]
    [[ "$output" == *"Using Port: 8008"* ]]
    [[ "$(vm_run_args)" == *"--publish 127.0.0.1:8008:8006"* ]]
}

@test "_run-vm: requests KVM, TPM, GPU and the documented VM sizing" {
    mkdir -p "${SANDBOX}/output/qcow2"
    printf 'disk\n' >"${SANDBOX}/output/qcow2/disk.qcow2"
    run_just _run-vm localhost/finpilot stable qcow2 iso/disk.toml
    [ "$status" -eq 0 ]
    [[ "$(vm_run_args)" == *"--device=/dev/kvm"* ]]
    [[ "$(vm_run_args)" == *"--env TPM=Y"* ]]
    [[ "$(vm_run_args)" == *"--env GPU=Y"* ]]
    [[ "$(vm_run_args)" == *"--env CPU_CORES=4"* ]]
    [[ "$(vm_run_args)" == *"--env RAM_SIZE=8G"* ]]
    [[ "$(vm_run_args)" == *"--env DISK_SIZE=64G"* ]]
}

@test "_run-vm: runs the qemu image ephemerally and opens the console URL" {
    mkdir -p "${SANDBOX}/output/qcow2"
    printf 'disk\n' >"${SANDBOX}/output/qcow2/disk.qcow2"
    run_just _run-vm localhost/finpilot stable qcow2 iso/disk.toml
    [ "$status" -eq 0 ]
    [[ "$(vm_run_args)" == *"--rm --privileged"* ]]
    [[ "$(vm_run_args)" == *"docker.io/qemux/qemu"* ]]
    [[ "$output" == *"Connect to http://localhost:8006"* ]]
}
