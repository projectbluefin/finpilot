export IMAGE_NAME := env("IMAGE_NAME", "finpilot")
export DEFAULT_TAG := env("DEFAULT_TAG", "stable")
export PODMAN := env("PODMAN", "podman")
export REPO_ORG := env("GITHUB_REPOSITORY_OWNER", "projectbluefin")
export bib_image := env("BIB_IMAGE", "quay.io/centos-bootc/bootc-image-builder:latest@sha256:2b52843ea2bfda73b0a08d97e76b734393b1d3a804681b9fabb26723bd3a2f0b")

alias build-vm := build-qcow2
alias rebuild-vm := rebuild-qcow2
alias run-vm := run-vm-qcow2

[private]
default:
    @just --list

# Check Just Syntax
[group('Just')]
check:
    #!/usr/bin/bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt --check -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt --check -f Justfile

# Fix Just Syntax
[group('Just')]
fix:
    #!/usr/bin/bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt -f Justfile || { exit 1; }

# Clean Repo
[group('Utility')]
clean:
    #!/usr/bin/bash
    set -eoux pipefail
    touch _build
    find *_build* -exec rm -rf {} \;
    rm -f previous.manifest.json
    rm -f changelog.md
    rm -f output.env
    rm -f output/

# Sudo Clean Repo
[group('Utility')]
[private]
sudo-clean:
    just sudoif just clean

# sudoif bash function
[group('Utility')]
[private]
sudoif command *args:
    #!/usr/bin/bash
    function sudoif(){
        if [[ "${UID}" -eq 0 ]]; then
            "$@"
        elif [[ "$(command -v sudo)" && -n "${SSH_ASKPASS:-}" ]] && [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
            /usr/bin/sudo --askpass "$@" || exit 1
        elif [[ "$(command -v sudo)" ]]; then
            /usr/bin/sudo "$@" || exit 1
        else
            exit 1
        fi
    }
    sudoif {{ command }} {{ args }}

# This Justfile recipe builds a container image using Podman.
#
# Arguments:
#   $target_image - The tag you want to apply to the image (default: $IMAGE_NAME).
#   $tag - The tag for the image (default: $DEFAULT_TAG).
#
# The script constructs the version string using the Fedora major version, tag,
# and the current date. If the git working directory is clean, it also includes
# the short SHA of the current HEAD.
#
# just build $target_image $tag
#
# Example usage:
#   just build aurora lts
#
# This will build an image 'aurora:lts' with DX and GDX enabled.
#

# Build the image using the specified parameters
build $target_image=IMAGE_NAME $tag=DEFAULT_TAG:
    #!/usr/bin/env bash

    # Read the Fedora major version from Containerfile (single source of truth).
    # The base image itself is pinned in the Containerfile FROM line.
    fedora_version=$(grep -E '^ARG FEDORA_MAJOR_VERSION=' Containerfile | head -n1 | sed -E 's/^ARG FEDORA_MAJOR_VERSION="?([^"]+)"?/\1/')
    if [[ -z "${fedora_version:-}" ]]; then
        echo "ERROR: Could not extract FEDORA_MAJOR_VERSION from Containerfile"
        exit 1
    fi

    # Bluefin-style version string: <fedora-version>.<date> for stable,
    # <tag>-<fedora-version>.<date> for everything else.
    if [[ "${tag}" =~ stable ]]; then
        ver="${fedora_version}.$(date +%Y%m%d)"
    else
        ver="${tag}-${fedora_version}.$(date +%Y%m%d)"
    fi

    # Avoid tag collisions when rebuilding on the same day
    if command -v skopeo &>/dev/null; then
        skopeo list-tags "docker://ghcr.io/${IMAGE_VENDOR:-${REPO_ORG}}/${target_image}" >/tmp/repotags.json 2>/dev/null \
            || echo '{"Tags":[]}' >/tmp/repotags.json
        if [[ $(jq "any(.Tags[]; contains(\"${ver}\"))" /tmp/repotags.json) == "true" ]]; then
            POINT=1
            while [[ $(jq "any(.Tags[]; contains(\"${ver}.${POINT}\"))" /tmp/repotags.json) == "true" ]]; do
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

    # Image identity ARGs - these define how bootc/ublue ecosystem recognizes the image
    # Override via env vars: IMAGE_NAME, IMAGE_VENDOR, UBLUE_IMAGE_TAG
    BUILD_ARGS+=("--build-arg" "IMAGE_NAME=${IMAGE_NAME:-${target_image}}")
    BUILD_ARGS+=("--build-arg" "IMAGE_VENDOR=${IMAGE_VENDOR:-${REPO_ORG}}")
    BUILD_ARGS+=("--build-arg" "UBLUE_IMAGE_TAG=${UBLUE_IMAGE_TAG:-${tag}}")

    # Add GitHub token as build secret if available (for CI/CD)
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        echo "Adding GitHub token as build secret"
        BUILD_ARGS+=("--secret" "id=GITHUB_TOKEN,env=GITHUB_TOKEN")
    fi

    # Labels for ArtifactHub and OCI metadata
    LABELS=()
    LABELS+=("--label" "org.opencontainers.image.title=${target_image}")
    LABELS+=("--label" "org.opencontainers.image.version=${ver}")
    LABELS+=("--label" "org.opencontainers.image.description=${IMAGE_DESC:-My Customized Universal Blue Image}")
    LABELS+=("--label" "org.opencontainers.image.source=https://github.com/${GITHUB_REPOSITORY_OWNER:-}/${target_image}/blob/${GITHUB_SHA:-}/Containerfile")
    LABELS+=("--label" "org.opencontainers.image.url=https://github.com/${GITHUB_REPOSITORY_OWNER:-}/${target_image}")
    LABELS+=("--label" "org.opencontainers.image.vendor=${IMAGE_VENDOR:-${REPO_ORG}}")
    LABELS+=("--label" "org.opencontainers.image.created=$(date -u +%Y\-%m\-%d\T%H\:%M\:%S\Z)")
    LABELS+=("--label" "io.artifacthub.package.readme-url=https://raw.githubusercontent.com/${GITHUB_REPOSITORY_OWNER:-}/${target_image}/refs/heads/main/README.md")
    LABELS+=("--label" "io.artifacthub.package.logo-url=${IMAGE_LOGO_URL:-https://avatars.githubusercontent.com/u/120078124?s=200&v=4}")
    LABELS+=("--label" "io.artifacthub.package.keywords=${IMAGE_KEYWORDS:-bootc,ublue,universal-blue}")
    LABELS+=("--label" "io.artifacthub.package.license=Apache-2.0")
    LABELS+=("--label" "io.artifacthub.package.deprecated=false")
    LABELS+=("--label" "containers.bootc=1")

    # Registry layer cache - speeds up rebuilds by reusing unchanged layers from GHCR
    # Cache write (REGISTRY_CACHE_WRITE=1) is set by CI for non-PR builds only
    # PR builds and local builds are read-only to prevent cache poisoning
    CACHE_ARGS=()
    cache_ref="ghcr.io/${IMAGE_VENDOR:-${REPO_ORG}}/${target_image}"
    if skopeo list-tags "docker://${cache_ref}" >/dev/null 2>&1; then
        CACHE_ARGS+=("--cache-from" "${cache_ref}")
        if [[ "${REGISTRY_CACHE_WRITE:-0}" == "1" ]]; then
            CACHE_ARGS+=("--cache-to" "${cache_ref}")
        fi
    fi

    ${PODMAN} build \
        "${BUILD_ARGS[@]}" \
        "${LABELS[@]}" \
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

# Command: _rootful_load_image
# Description: This script checks if the current user is root or running under sudo. If not, it attempts to resolve the image tag using podman inspect.
#              If the image is found, it loads it into rootful podman. If the image is not found, it pulls it from the repository.
#
# Parameters:
#   $target_image - The name of the target image to be loaded or pulled.
#   $tag - The tag of the target image to be loaded or pulled. Default is 'default_tag'.
#
# Example usage:
#   _rootful_load_image my_image latest
#
# Steps:
# 1. Check if the script is already running as root or under sudo.
# 2. Check if target image is in the non-root podman container storage)
# 3. If the image is found, load it into rootful podman using podman scp.
# 4. If the image is not found, pull it from the remote repository into reootful podman.

_rootful_load_image $target_image=IMAGE_NAME $tag=DEFAULT_TAG:
    #!/usr/bin/bash
    set -eoux pipefail

    # Check if already running as root or under sudo
    if [[ -n "${SUDO_USER:-}" || "${UID}" -eq "0" ]]; then
        echo "Already root or running under sudo, no need to load image from user podman."
        exit 0
    fi

    # Try to resolve the image tag using podman inspect
    set +e
    resolved_tag=$(podman inspect -t image "${target_image}:${tag}" | jq -r '.[].RepoTags.[0]')
    return_code=$?
    set -e

    USER_IMG_ID=$(podman images --filter reference="${target_image}:${tag}" --format "'{{ '{{.ID}}' }}'")

    if [[ $return_code -eq 0 ]]; then
        # If the image is found, load it into rootful podman
        ID=$(just sudoif podman images --filter reference="${target_image}:${tag}" --format "'{{ '{{.ID}}' }}'")
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

# Build a bootc bootable image using Bootc Image Builder (BIB)
# Converts a container image to a bootable image
# Parameters:
#   target_image: The name of the image to build (ex. localhost/fedora)
#   tag: The tag of the image to build (ex. latest)
#   type: The type of image to build (ex. qcow2, raw, iso)
#   config: The configuration file to use for the build (default: iso/disk.toml)

# Example: just _rebuild-bib localhost/fedora latest qcow2 iso/disk.toml
_build-bib $target_image $tag $type $config: (_rootful_load_image target_image tag)
    #!/usr/bin/env bash
    set -euo pipefail

    args="--type ${type} "
    args+="--use-librepo=True "
    args+="--rootfs=btrfs"

    BUILDTMP=$(mktemp -p "${PWD}" -d -t _build-bib.XXXXXXXXXX)

    sudo podman run \
      --rm \
      -it \
      --privileged \
      --pull=newer \
      --net=host \
      --security-opt label=type:unconfined_t \
      -v $(pwd)/${config}:/config.toml:ro \
      -v $BUILDTMP:/output \
      -v /var/lib/containers/storage:/var/lib/containers/storage \
      "${bib_image}" \
      ${args} \
      "${target_image}:${tag}"

    mkdir -p output
    sudo mv -f $BUILDTMP/* output/
    sudo rmdir $BUILDTMP
    sudo chown -R $USER:$USER output/

# Podman builds the image from the Containerfile and creates a bootable image
# Parameters:
#   target_image: The name of the image to build (ex. localhost/fedora)
#   tag: The tag of the image to build (ex. latest)
#   type: The type of image to build (ex. qcow2, raw, iso)
#   config: The configuration file to use for the build (default: iso/disk.toml)

# Example: just _rebuild-bib localhost/fedora latest qcow2 iso/disk.toml
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

# Run a virtual machine with the specified image type and configuration
_run-vm $target_image $tag $type $config:
    #!/usr/bin/bash
    set -eoux pipefail

    # Determine the image file based on the type
    image_file="output/${type}/disk.${type}"
    if [[ $type == iso ]]; then
        image_file="output/bootiso/install.iso"
    fi

    # Build the image if it does not exist
    if [[ ! -f "${image_file}" ]]; then
        just "build-${type}" "$target_image" "$tag"
    fi

    # Determine an available port to use
    port=8006
    while grep -q :${port} <<< $(ss -tunalp); do
        port=$(( port + 1 ))
    done
    echo "Using Port: ${port}"
    echo "Connect to http://localhost:${port}"

    # Set up the arguments for running the VM
    run_args=()
    run_args+=(--rm --privileged)
    run_args+=(--pull=newer)
    run_args+=(--publish "127.0.0.1:${port}:8006")
    run_args+=(--env "CPU_CORES=4")
    run_args+=(--env "RAM_SIZE=8G")
    run_args+=(--env "DISK_SIZE=64G")
    run_args+=(--env "TPM=Y")
    run_args+=(--env "GPU=Y")
    run_args+=(--device=/dev/kvm)
    run_args+=(--volume "${PWD}/${image_file}":"/boot.${type}")
    run_args+=(docker.io/qemux/qemu)

    # Run the VM and open the browser to connect
    (sleep 30 && xdg-open http://localhost:"$port") &
    podman run "${run_args[@]}"

# Run a virtual machine from a QCOW2 image
[group('Run Virtual Machine')]
run-vm-qcow2 $target_image=("localhost/" + IMAGE_NAME) $tag=DEFAULT_TAG: && (_run-vm target_image tag "qcow2" "iso/disk.toml")

# Run a virtual machine from a RAW image
[group('Run Virtual Machine')]
run-vm-raw $target_image=("localhost/" + IMAGE_NAME) $tag=DEFAULT_TAG: && (_run-vm target_image tag "raw" "iso/disk.toml")

# Run a virtual machine from an ISO
[group('Run Virtual Machine')]
run-vm-iso $target_image=("localhost/" + IMAGE_NAME) $tag=DEFAULT_TAG: && (_run-vm target_image tag "iso" "iso/iso.toml")

# Run a virtual machine using systemd-vmspawn
[group('Run Virtual Machine')]
spawn-vm rebuild="0" type="qcow2" ram="6G":
    #!/usr/bin/env bash

    set -euo pipefail

    [ "{{ rebuild }}" -eq 1 ] && echo "Rebuilding the ISO" && just build-vm {{ rebuild }} {{ type }}

    systemd-vmspawn \
      -M "bootc-image" \
      --console=gui \
      --cpus=2 \
      --ram=$(echo {{ ram }}| /usr/bin/numfmt --from=iec) \
      --network-user-mode \
      --vsock=false --pass-ssh-key=false \
      -i ./output/**/*.{{ type }}

# Runs shell check on all Bash scripts
lint:
    #!/usr/bin/env bash
    set -eoux pipefail
    # Check if shellcheck is installed
    if ! command -v shellcheck &> /dev/null; then
        echo "shellcheck could not be found. Please install it."
        exit 1
    fi
    # Run shellcheck on all Bash scripts
    /usr/bin/find . -iname "*.sh" -type f -exec shellcheck "{}" ';'

# Runs shfmt on all Bash scripts
format:
    #!/usr/bin/env bash
    set -eoux pipefail
    # Check if shfmt is installed
    if ! command -v shfmt &> /dev/null; then
        echo "shfmt could not be found. Please install it."
        exit 1
    fi
    # Run shfmt on all Bash scripts
    /usr/bin/find . -iname "*.sh" -type f -exec shfmt --write "{}" ';'
