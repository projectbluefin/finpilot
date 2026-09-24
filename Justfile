export IMAGE_NAME := env("IMAGE_NAME", "finpilot")
export DEFAULT_TAG := env("DEFAULT_TAG", "stable")
export PODMAN := env("PODMAN", "podman")
export REPO_ORG := env("GITHUB_REPOSITORY_OWNER", "projectbluefin")
export bib_image := env("BIB_IMAGE", "ghcr.io/osbuild/bootc-image-builder:latest@sha256:0daf70630fbd7ef8a94571d3e50a77c3f8a3b812f67ec2d71f52e4c8ba83985c")
export qemu_image := env("QEMU_IMAGE", "ghcr.io/qemus/qemu:7.50@sha256:e7f6fda52503a546fd649670ba46e4bc23dc6dcef275bc3fac48877fbbc430df")
export vm_ram := env("VM_RAM", "8192")
export vm_cpus := env("VM_CPUS", "4")

alias build-vm := build-qcow2
alias rebuild-vm := rebuild-qcow2
alias run-vm := run-vm-qcow2

[private]
default:
    @just --list

# Rewrite every justfile in place, or report drift instead when passed --check.
# `check` and `fix` both call this so the file set has one definition.
[private]
_format-justfiles $mode="":
    #!/usr/bin/bash
    set -euo pipefail
    echo "Checking syntax: Justfile"
    just --unstable --fmt {{ mode }} -f Justfile
    while IFS= read -r -d '' file; do
        echo "Checking syntax: ${file}"
        just --unstable --fmt {{ mode }} -f "${file}"
    done < <(find . -type f -name '*.just' -print0)

# Check Just Syntax
[group('Just')]
check:
    just _format-justfiles "--check"

# Run the contract suite: interfaces the image must satisfy. A fork keeps these.
[group('Just')]
test-contract:
    #!/usr/bin/bash
    set -euo pipefail
    just _bats tests/contract

# Run the template suite: this repository's build wiring. A fork may delete this.
[group('Just')]
test-template:
    #!/usr/bin/bash
    set -euo pipefail
    just _bats tests/template

# Run every unit test (contract + template). CI calls this.
[group('Just')]
test-unit:
    #!/usr/bin/bash
    set -euo pipefail
    just _bats tests

# Single definition of how the suite runs: discover every *_test.bats under the
# given directory, so a fork can add or remove files without editing this file.
[private]
_bats $dir:
    #!/usr/bin/bash
    set -euo pipefail
    if ! command -v bats &>/dev/null; then
        echo "bats not found — install with: sudo apt-get install bats  OR  npm install -g bats"
        exit 1
    fi
    mapfile -t files < <(find "{{ dir }}" -type f -name '*_test.bats' | sort)
    if [[ ${#files[@]} -eq 0 ]]; then
        echo "No *_test.bats files found under {{ dir }}" >&2
        exit 1
    fi
    echo "Running ${#files[@]} test files..."
    bats --print-output-on-failure "${files[@]}"

# Validate Brewfiles without evaluating them as Ruby.
[group('Just')]
validate-brewfiles:
    #!/usr/bin/bash
    set -euo pipefail
    bash build/validate-brewfiles.sh

# Validate flatpak preinstall files against flathub (Branch= key + app existence)
[group('Just')]
validate-flatpaks:
    #!/usr/bin/bash
    set -euo pipefail
    bash build/validate-flatpaks.sh

# Fix Just Syntax
[group('Just')]
fix:
    just _format-justfiles

# Clean Repo
[group('Utility')]
clean:
    #!/usr/bin/bash
    set -eoux pipefail
    find . -maxdepth 1 -name '*_build*' -prune -exec rm -rf {} +
    rm -rf output/

# Sudo Clean Repo
[group('Utility')]
[private]
sudo-clean:
    just sudoif just clean

# sudoif bash function
[group('Utility')]
[positional-arguments]
[private]
sudoif command *args:
    #!/usr/bin/bash
    function sudoif(){
        local sudo_bin
        sudo_bin="$(command -v sudo || true)"
        if [[ "${UID}" -eq 0 ]]; then
            "$@"
        elif [[ -n "${sudo_bin}" && -n "${SSH_ASKPASS:-}" ]] && [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
            "${sudo_bin}" --askpass "$@" || exit 1
        elif [[ -n "${sudo_bin}" ]]; then
            "${sudo_bin}" "$@" || exit 1
        else
            exit 1
        fi
    }
    sudoif "$@"
# Build the container image with Podman.
#
# Arguments:
#   $target_image - the image to build (default: $IMAGE_NAME)
#   $tag          - the image tag (default: $DEFAULT_TAG)
#
# The version string is <base-tag>.<date> for a tag containing "stable" and
# <image-tag>-<base-tag>.<date> otherwise. The base tag comes from the base
# image's FROM line in the Containerfile, a point release is appended when the
# registry already has that version, and a clean worktree also stamps the short
# HEAD SHA.
#
# Example: just build finpilot stable-testing

# Build the image using the specified parameters
[group('Image')]
build $target_image=IMAGE_NAME $tag=DEFAULT_TAG:
    #!/usr/bin/env bash

    # The base image is the source of truth for the base tag and the base image
    # name: it is the FROM line with no stage alias, because every context stage
    # is `FROM ... AS name`. Renovate is what moves its tag, so a bump needs no
    # second edit. The tag is taken verbatim, so Fedora's numeric major and
    # CentOS's `stream10` both work.
    base_from=$(grep -iE '^FROM[[:space:]]' Containerfile | grep -viE '[[:space:]]as[[:space:]]' | head -n1)
    base_tag=$(sed -E 's|^FROM[[:space:]]+[^@:[:space:]]*:([^@[:space:]]+)(@.*)?$|\1|' <<<"${base_from}")
    base_ref=$(sed -E 's|^FROM[[:space:]]+||; s|@.*$||; s|:[^:/]*$||' <<<"${base_from}")
    base_image_name="${base_ref##*/}"
    if [[ -z "${base_from}" || "${base_tag}" == "${base_from}" || -z "${base_image_name}" ]]; then
        echo "ERROR: Could not read the base image from the Containerfile base FROM line"
        exit 1
    fi

    # Image identity, resolved once: an explicit IMAGE_VENDOR wins, otherwise
    # fall back to the repository owner GitHub Actions supplies.
    image_vendor="${IMAGE_VENDOR:-${REPO_ORG}}"

    # target_image names the local image, and the VM recipes pass it with a
    # `localhost/` prefix. The identity must not carry that prefix: image-info
    # composes image-ref from IMAGE_NAME, and the ISO path hands that ref to
    # Bootc Image Builder as the install target, so the prefix would become a
    # registry path that cannot exist.
    image_name="${target_image#localhost/}"

    # Bluefin-style version string: <base-tag>.<date> for stable,
    # <image-tag>-<base-tag>.<date> for everything else.
    if [[ "${tag}" =~ stable ]]; then
        ver="${base_tag}.$(date +%Y%m%d)"
    else
        ver="${tag}-${base_tag}.$(date +%Y%m%d)"
    fi

    # Avoid tag collisions when rebuilding on the same day
    if command -v skopeo &>/dev/null; then
        repotags=$(mktemp -t repotags.XXXXXXXX.json) || { echo "ERROR: mktemp failed to create tag-list temp file"; exit 1; }
        trap 'rm -f "${repotags}"' EXIT
        skopeo list-tags "docker://ghcr.io/${image_vendor}/${image_name}" >"${repotags}" 2>/dev/null \
            || echo '{"Tags":[]}' >"${repotags}"
        if [[ $(jq "any(.Tags[]; contains(\"${ver}\"))" "${repotags}") == "true" ]]; then
            POINT=1
            while [[ $(jq "any(.Tags[]; contains(\"${ver}.${POINT}\"))" "${repotags}") == "true" ]]; do
                ((POINT++))
            done
            ver="${ver}.${POINT}"
            echo "Tag collision detected; using version ${ver}"
        fi
    fi

    BUILD_ARGS=()
    BUILD_ARGS+=("--build-arg" "VERSION=${ver}")
    if [[ -z "$(git status -s)" ]]; then
        BUILD_ARGS+=("--build-arg" "SHA_HEAD_SHORT=$(git rev-parse --short HEAD)")
    fi

    # Image identity ARGs - these define how bootc/ublue ecosystem recognizes the image.
    # Override via env vars: IMAGE_NAME, IMAGE_VENDOR, UBLUE_IMAGE_TAG. The base
    # image name is not an env var: it is derived from the FROM line above.
    BUILD_ARGS+=("--build-arg" "IMAGE_NAME=${image_name}")
    BUILD_ARGS+=("--build-arg" "IMAGE_VENDOR=${image_vendor}")
    BUILD_ARGS+=("--build-arg" "UBLUE_IMAGE_TAG=${UBLUE_IMAGE_TAG:-${tag}}")
    BUILD_ARGS+=("--build-arg" "BASE_IMAGE_NAME=${base_image_name}")

    # The Containerfile owns the OCI/ArtifactHub metadata, including URLs
    # derived from image identity. Pass only explicit metadata overrides.
    BUILD_ARGS+=("--build-arg" "IMAGE_CREATED=$(date -u +%Y\-%m\-%d\T%H\:%M\:%S\Z)")
    for metadata_arg in IMAGE_DESC IMAGE_LOGO_URL IMAGE_KEYWORDS IMAGE_REF; do
        if [[ -n "${!metadata_arg:-}" ]]; then
            BUILD_ARGS+=("--build-arg" "${metadata_arg}=${!metadata_arg}")
        fi
    done

    # Add GitHub token as build secret if available (for CI/CD)
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        echo "Adding GitHub token as build secret"
        BUILD_ARGS+=("--secret" "id=GITHUB_TOKEN,env=GITHUB_TOKEN")
    fi

    # Registry layer cache - speeds up rebuilds by reusing unchanged layers from GHCR
    # CI sets REGISTRY_CACHE_WRITE=1 for candidate builds; local builds stay
    # read-only so a developer never poisons the shared cache
    CACHE_ARGS=()
    cache_ref="ghcr.io/${image_vendor}/${image_name}"
    if skopeo list-tags "docker://${cache_ref}" >/dev/null 2>&1; then
        CACHE_ARGS+=("--cache-from" "${cache_ref}")
        if [[ "${REGISTRY_CACHE_WRITE:-0}" == "1" ]]; then
            CACHE_ARGS+=("--cache-to" "${cache_ref}")
        fi
    fi

    ${PODMAN} build \
        "${BUILD_ARGS[@]}" \
        "${CACHE_ARGS[@]}" \
        --pull=newer \
        --tag "${target_image}:${tag}" \
        .

# Tag images with the generated alias tags
# Bluefin pattern: separate tagging from pushing
[group('Image')]
tag-images $image_name="" $default_tag="" $tags="":
    #!/usr/bin/bash
    set -eou pipefail

    if [[ -z "${image_name}" || -z "${default_tag}" || -z "${tags}" ]]; then
        echo "Usage: just tag-images <image_name> <default_tag> <tags>"
        exit 1
    fi

    IMAGE=$(${PODMAN} inspect "localhost/${image_name}:${default_tag}" | jq -r '.[].Id')
    ${PODMAN} untag "localhost/${image_name}:${default_tag}"

    for tag in ${tags}; do
        ${PODMAN} tag "${IMAGE}" "${image_name}:${tag}"
    done

    # Re-apply default tag so local operations can still find it
    ${PODMAN} tag "${IMAGE}" "${image_name}:${default_tag}"

    echo "Tagged ${image_name} with: ${tags}"

# Make the locally built image visible to rootful podman so Bootc Image Builder
# can read it, copying it across with `podman image scp`. Falls back to pulling
# it from the registry when it only exists there, and no-ops when already root.

_rootful_load_image $target_image=IMAGE_NAME $tag=DEFAULT_TAG:
    #!/usr/bin/bash
    set -eoux pipefail

    # Check if already running as root or under sudo
    if [[ -n "${SUDO_USER:-}" || "${UID}" -eq "0" ]]; then
        echo "Already root or running under sudo, no need to load image from user podman."
        exit 0
    fi

    # Does the image exist locally at all? A non-zero exit means it only lives
    # in the registry, and the else branch below pulls it.
    set +e
    podman inspect -t image "${target_image}:${tag}" >/dev/null 2>&1
    return_code=$?
    set -e

    USER_IMG_ID=$(podman images -q --filter reference="${target_image}:${tag}")

    if [[ $return_code -eq 0 ]]; then
        # If the image is found, load it into rootful podman
        ID=$(just sudoif podman images -q --filter reference="${target_image}:${tag}")
        if [[ "$ID" != "$USER_IMG_ID" ]]; then
            # If the image ID is not found or different from user, copy the image from user podman to root podman
            COPYTMP=$(mktemp -p "${PWD}" -d -t _build_podman_scp.XXXXXXXXXX)
            just sudoif TMPDIR=${COPYTMP} podman image scp ${UID}@localhost::"${target_image}:${tag}" root@localhost::"${target_image}:${tag}"
            rm -rf "${COPYTMP}"
        fi
    else
        # If the image is not found, pull it from the repository
        just sudoif podman pull "${target_image}:${tag}"
    fi

# Convert a container image into a bootable disk with Bootc Image Builder.
# type is qcow2, raw or iso; config is the BIB config file to use
# (iso/disk.toml for qcow2 and raw, iso/iso.toml for iso).
_build-bib $target_image $tag $type $config: (_rootful_load_image target_image tag)
    #!/usr/bin/env bash
    set -euo pipefail

    args="--type ${type} "
    args+="--use-librepo=True "
    args+="--rootfs=btrfs"

    # Bootc Image Builder records the post-install `bootc switch` origin from
    # the image reference it is given, so an ISO has to be built against the
    # published reference instead of the local build tag. The image names
    # itself in image-info.json, which keeps one source of truth for forks and
    # means iso/iso.toml carries no image reference at all.
    build_image="${target_image}:${tag}"
    if [[ "${type}" == "iso" ]]; then
        image_info=$(just sudoif podman run --rm --entrypoint /usr/bin/cat \
            "${target_image}:${tag}" /usr/share/ublue-os/image-info.json)
        image_ref=$(jq -r '."image-ref"' <<<"${image_info}" | sed 's|.*docker://||')
        build_image="${image_ref}:$(jq -r '."image-tag"' <<<"${image_info}")"
        just sudoif podman tag "${target_image}:${tag}" "${build_image}"
    fi

    BUILDTMP=$(mktemp -p "${PWD}" -d -t _build-bib.XXXXXXXXXX)
    # This script exits on the first error, so a failed build would otherwise
    # leave the image BIB already wrote inside BUILDTMP behind in the repo root.
    trap 'sudo rm -rf "${BUILDTMP}"' EXIT

    sudo podman run \
      --rm \
      --privileged \
      --net=host \
      --security-opt label=type:unconfined_t \
      -v "${PWD}/${config}:/config.toml:ro" \
      -v "${BUILDTMP}:/output" \
      -v /var/lib/containers/storage:/var/lib/containers/storage \
      "${bib_image}" \
      ${args} \
      "${build_image}"

    mkdir -p output
    # `mv` cannot replace an existing directory (`-f` only suppresses the
    # overwrite prompt for files), so a second build of the same type would
    # fail here and the EXIT trap would throw the finished disk away. Clear
    # the destination directories for the artifacts we are about to move in.
    for artifact in "${BUILDTMP}"/*; do
        sudo rm -rf "output/$(basename "${artifact}")"
    done
    sudo mv -f "${BUILDTMP}"/* output/
    sudo rmdir "${BUILDTMP}"
    # `id` rather than `$USER`: these recipes run under `set -u` from cron,
    # containers and systemd, where the kernel never exported USER, and aborting
    # here would throw away a completed build.
    sudo chown -R "$(id -u):$(id -g)" output/

# Rebuild the container image first, then convert it (see _build-bib).
_rebuild-bib $target_image $tag $type $config: (build target_image tag) && (_build-bib target_image tag type config)

# Build a QCOW2 virtual machine image
[group('Build Virtual Machine Image')]
build-qcow2 $target_image=("localhost/" + IMAGE_NAME) $tag=DEFAULT_TAG: && (_build-bib target_image tag "qcow2" "iso/disk.toml")

# Build a RAW virtual machine image
[group('Build Virtual Machine Image')]
build-raw $target_image=("localhost/" + IMAGE_NAME) $tag=DEFAULT_TAG: && (_build-bib target_image tag "raw" "iso/disk.toml")

# Build an ISO virtual machine image
[group('Build Virtual Machine Image')]
build-iso $target_image=("localhost/" + IMAGE_NAME) $tag=DEFAULT_TAG: && (_build-bib target_image tag "iso" "iso/iso.toml")

# Rebuild a QCOW2 virtual machine image
[group('Build Virtual Machine Image')]
rebuild-qcow2 $target_image=("localhost/" + IMAGE_NAME) $tag=DEFAULT_TAG: && (_rebuild-bib target_image tag "qcow2" "iso/disk.toml")

# Rebuild a RAW virtual machine image
[group('Build Virtual Machine Image')]
rebuild-raw $target_image=("localhost/" + IMAGE_NAME) $tag=DEFAULT_TAG: && (_rebuild-bib target_image tag "raw" "iso/disk.toml")

# Rebuild an ISO virtual machine image
[group('Build Virtual Machine Image')]
rebuild-iso $target_image=("localhost/" + IMAGE_NAME) $tag=DEFAULT_TAG: && (_rebuild-bib target_image tag "iso" "iso/iso.toml")

# The artifact Bootc Image Builder writes for a given --type, as a path from
# the repository root. The directory is osbuild's export name, which is not
# always the type name: see osbuild/image-builder internal/bibimg/imagetypes.go,
# where raw exports as "image" while qcow2 exports as "qcow2" and the ISO types
# export as "bootiso". Every VM recipe resolves its input through here.
[private]
vm-artifact $type:
    #!/usr/bin/env bash
    set -euo pipefail
    case "${type}" in
        qcow2) echo "output/qcow2/disk.qcow2" ;;
        raw) echo "output/image/disk.raw" ;;
        iso) echo "output/bootiso/install.iso" ;;
        *)
            echo "ERROR: unknown image type '${type}' (expected qcow2, raw or iso)" >&2
            exit 1
            ;;
    esac

# Run a built artifact in a virtual machine.
#
# Native QEMU first, the shape projectbluefin/dakota's boot-vm uses: no
# container pull, a real window on a desktop host, and 2222 forwarded to the
# guest's sshd. Hosts without qemu-system-x86_64 fall back to
# ghcr.io/qemus/qemu, which serves the same VM over a browser console and
# provisions its own disk.
#
# The ISO needs a disk to install onto, so it gets a scratch qcow2 target at
# output/iso/target.qcow2, created on first use. Disk images are booted as they
# are, so the guest writes to the built artifact; `just build-<type>` restores
# it and `just clean` removes the scratch target.
_run-vm $target_image $tag $type:
    #!/usr/bin/env bash
    set -euo pipefail

    artifact=$(just vm-artifact "${type}")

    # Build the artifact if it is not there yet.
    if [[ ! -f "${artifact}" ]]; then
        just "build-${type}" "${target_image}" "${tag}"
    fi

    if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
        just _run-vm-container "${type}" "${artifact}"
        exit 0
    fi

    # OVMF lives at a different path on every distro, and the vars file has to
    # be a writable copy: UEFI saves boot state into it.
    ovmf_code=""
    for f in \
        /usr/share/edk2/ovmf/OVMF_CODE.fd \
        /usr/share/OVMF/OVMF_CODE.fd \
        /usr/share/OVMF/OVMF_CODE_4M.fd \
        /usr/share/edk2/x64/OVMF_CODE.4m.fd \
        /usr/share/qemu/OVMF_CODE.fd; do
        [[ -f "${f}" ]] && { ovmf_code="${f}"; break; }
    done
    if [[ -z "${ovmf_code}" ]]; then
        echo "ERROR: OVMF firmware not found — install edk2-ovmf (Fedora) or ovmf (Debian/Ubuntu)" >&2
        exit 1
    fi

    ovmf_vars_src=""
    for f in \
        /usr/share/edk2/ovmf/OVMF_VARS.fd \
        /usr/share/OVMF/OVMF_VARS.fd \
        /usr/share/OVMF/OVMF_VARS_4M.fd \
        /usr/share/edk2/x64/OVMF_VARS.4m.fd \
        /usr/share/qemu/OVMF_VARS.fd; do
        [[ -f "${f}" ]] && { ovmf_vars_src="${f}"; break; }
    done
    ovmf_vars=$(mktemp /tmp/OVMF_VARS.XXXXXX.fd)
    [[ -n "${ovmf_vars_src}" ]] && cp "${ovmf_vars_src}" "${ovmf_vars}"
    trap 'rm -f "${ovmf_vars}"' EXIT

    # 2222 is the conventional host port for the guest's sshd, but it is only
    # free until the first VM takes it.
    ssh_port=2222
    while ss -tunalp 2>/dev/null | grep -q ":${ssh_port} "; do
        ssh_port=$(( ssh_port + 1 ))
    done

    args=(
        -machine q35
        -accel kvm
        -cpu host
        -smp "${vm_cpus}"
        -m "${vm_ram}"
        -device virtio-vga
        -device virtio-keyboard
        -device virtio-mouse
        -device virtio-net-pci,netdev=net0
        -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:${ssh_port}-:22"
        -drive "if=pflash,format=raw,readonly=on,file=${ovmf_code}"
        -drive "if=pflash,format=raw,file=${ovmf_vars}"
    )

    if [[ "${type}" == iso ]]; then
        target="output/iso/target.qcow2"
        if [[ ! -f "${target}" ]]; then
            echo "==> Creating the ISO's scratch target disk: ${target} (64G sparse)"
            mkdir -p output/iso
            qemu-img create -f qcow2 "${target}" 64G >/dev/null
        fi
        args+=(-drive "file=${artifact},media=cdrom,readonly=on,format=raw")
        args+=(-drive "file=$(realpath "${target}"),if=virtio,format=qcow2")
        args+=(-boot order=d)
    else
        args+=(-drive "file=${artifact},if=virtio,format=${type}")
        args+=(-boot order=c)
    fi

    # No display (an ssh session, say): fall back to the serial console. Serial
    # output only appears if the guest's kernel cmdline asks for it.
    if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
        args+=(-display gtk)
    else
        echo "==> No display detected: serial console on stdio (Ctrl-A X to quit)"
        args+=(-display none -serial mon:stdio)
    fi

    echo "==> Booting ${artifact}"
    echo "    RAM: ${vm_ram}M, CPUs: ${vm_cpus}, ssh: ssh -p ${ssh_port} <user>@127.0.0.1"
    qemu-system-x86_64 "${args[@]}"

# Containerised fallback for _run-vm, for hosts with no qemu-system-x86_64.
# qemus/qemu boots the image and serves a web console; it provisions its own
# disk, so the ISO needs no scratch target here. Disk images are booted with
# -snapshot so the container never writes to the built artifact.
[private]
_run-vm-container $type $artifact:
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ ! -f "${artifact}" ]]; then
        echo "ERROR: ${artifact} not found — run: just build-${type}" >&2
        exit 1
    fi

    case "${type}" in
        qcow2)
            boot_mount="/boot.qcow2"
            arguments="-snapshot"
            ;;
        raw)
            boot_mount="/boot.img"
            arguments="-snapshot"
            ;;
        iso)
            boot_mount="/boot.iso"
            arguments=""
            ;;
    esac

    port=8006
    while ss -tunalp 2>/dev/null | grep -q ":${port} "; do
        port=$(( port + 1 ))
    done
    echo "==> Web console: http://localhost:${port}"

    run_args=(
        --rm --privileged
        --device=/dev/kvm
        --publish "127.0.0.1:${port}:8006"
        --env "CPU_CORES=${vm_cpus}"
        --env "RAM_SIZE=${vm_ram}M"
        --env "DISK_SIZE=64G"
        --env "BOOT_MODE=uefi"
        --env "TPM=Y"
        --env "GPU=Y"
    )
    [[ -n "${arguments}" ]] && run_args+=(--env "ARGUMENTS=${arguments}")
    run_args+=(--volume "$(realpath "${artifact}"):${boot_mount}" "${qemu_image}")

    (sleep 15 && xdg-open "http://localhost:${port}") >/dev/null 2>&1 &
    podman run "${run_args[@]}"

# Run a virtual machine from a QCOW2 image
[group('Run Virtual Machine')]
run-vm-qcow2 $target_image=("localhost/" + IMAGE_NAME) $tag=DEFAULT_TAG: && (_run-vm target_image tag "qcow2")

# Run a virtual machine from a RAW image
[group('Run Virtual Machine')]
run-vm-raw $target_image=("localhost/" + IMAGE_NAME) $tag=DEFAULT_TAG: && (_run-vm target_image tag "raw")

# Run a virtual machine from an ISO
[group('Run Virtual Machine')]
run-vm-iso $target_image=("localhost/" + IMAGE_NAME) $tag=DEFAULT_TAG: && (_run-vm target_image tag "iso")

# Run a virtual machine using systemd-vmspawn. Disk images only; for an ISO use run-vm-iso.
[group('Run Virtual Machine')]
spawn-vm rebuild="0" type="qcow2" ram="6G":
    #!/usr/bin/env bash
    set -euo pipefail

    # vmspawn shells out to qemu and needs KVM. Left unchecked it fails with a
    # generic error after doing work, so name what is missing up front.
    for dep in systemd-vmspawn qemu-system-x86_64; do
        if ! command -v "${dep}" >/dev/null 2>&1; then
            echo "ERROR: ${dep} not found — use 'just run-vm-{{ type }}' instead" >&2
            exit 1
        fi
    done
    if [[ ! -w /dev/kvm ]]; then
        echo "ERROR: /dev/kvm is missing or not writable — add your user to the kvm group, or use 'just run-vm-{{ type }}'" >&2
        exit 1
    fi

    if [[ "{{ type }}" == "iso" ]]; then
        echo "ERROR: systemd-vmspawn boots disk images; use 'just run-vm-iso' for an ISO" >&2
        exit 1
    fi

    if [[ "{{ rebuild }}" -eq 1 ]]; then
        echo "Rebuilding the {{ type }} image"
        just "build-{{ type }}"
    fi

    artifact=$(just vm-artifact "{{ type }}")
    if [[ ! -f "${artifact}" ]]; then
        echo "ERROR: ${artifact} not found — run: just build-{{ type }}" >&2
        exit 1
    fi

    systemd-vmspawn \
      -M "bootc-image" \
      --console=gui \
      --cpus=2 \
      --ram=$(echo {{ ram }}| /usr/bin/numfmt --from=iec) \
      --network-user-mode \
      --vsock=false --pass-ssh-key=false \
      -i "$(realpath "${artifact}")"

# The repository's shell scripts: the *.sh files git tracks. Single definition
# of the lint and format scope, and of the glob CI hands to validate-pr.
[private]
shell-sources:
    #!/usr/bin/env bash
    set -euo pipefail
    git ls-files '*.sh'

# Runs shell check on the shell scripts git tracks
[group('Just')]
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    # Check if shellcheck is installed
    if ! command -v shellcheck &> /dev/null; then
        echo "shellcheck could not be found. Please install it."
        exit 1
    fi
    # git is the single source of truth for lint scope; CI resolves the same
    # list into validate-pr's shellcheck-glob input.
    mapfile -t sources < <(just shell-sources)
    if [[ ${#sources[@]} -eq 0 ]]; then
        echo "No shell scripts found: git tracks no *.sh files" >&2
        exit 1
    fi
    printf 'Shellchecking %s scripts:\n' "${#sources[@]}"
    printf '  %s\n' "${sources[@]}"
    shellcheck "${sources[@]}"

# Runs shfmt on the shell scripts git tracks
[group('Just')]
format:
    #!/usr/bin/env bash
    set -euo pipefail
    # Check if shfmt is installed
    if ! command -v shfmt &> /dev/null; then
        echo "shfmt could not be found. Please install it."
        exit 1
    fi
    # Format exactly the files lint checks.
    mapfile -t sources < <(just shell-sources)
    if [[ ${#sources[@]} -eq 0 ]]; then
        echo "No shell scripts found: git tracks no *.sh files" >&2
        exit 1
    fi
    printf 'Formatting %s scripts:\n' "${#sources[@]}"
    printf '  %s\n' "${sources[@]}"
    shfmt --write "${sources[@]}"
