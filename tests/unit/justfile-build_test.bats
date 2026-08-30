#!/usr/bin/env bats
# Unit tests for the root Justfile image recipes: `build` and `tag-images`.
#
# The recipes are exercised against a sandbox copy of the Justfile so the real
# repository is never touched. Every external command the recipes shell out to
# (podman, skopeo, git, date) is replaced by a stub on PATH that records its
# argv, which lets the tests assert on the argument vector `podman build` would
# have received without running a container build.
#
# Run with: bats tests/unit/justfile-build_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."

setup() {
    if ! command -v just &>/dev/null; then
        skip "just is not installed"
    fi

    TEST_ROOT="${BATS_TEST_TMPDIR:-${BATS_TMPDIR}}/justfile-build.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/stub-bin"
    SANDBOX="${TEST_ROOT}/repo"
    PODMAN_LOG="${TEST_ROOT}/logs/podman.log"
    SKOPEO_LOG="${TEST_ROOT}/logs/skopeo.log"

    mkdir -p "${STUB_BIN}" "${TEST_ROOT}/logs" "${SANDBOX}"

    cp "${REPO_ROOT}/Justfile" "${SANDBOX}/Justfile"
    printf 'ARG FEDORA_MAJOR_VERSION="44"\nFROM scratch\n' >"${SANDBOX}/Containerfile"

    export PATH="${STUB_BIN}:${PATH}"
    export PODMAN_LOG SKOPEO_LOG

    # Deterministic clock: the recipe builds the version string from `date`.
    export STUB_DATE_YMD="20260830"
    # Registry state the skopeo stub reports back for `list-tags`.
    export STUB_SKOPEO_TAGS='{"Tags":[]}'
    # Exit status of `skopeo list-tags`; non-zero disables the layer cache.
    export STUB_SKOPEO_STATUS=0
    # Porcelain output of `git status -s`; empty means a clean worktree.
    export STUB_GIT_STATUS=""
    # JSON `podman inspect` returns; the recipe reads .[].Id out of it.
    export STUB_PODMAN_INSPECT='[{"Id":"sha256:deadbeef"}]'

    cat >"${STUB_BIN}/podman" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${PODMAN_LOG}"
if [[ "$1" == "inspect" ]]; then
    printf '%s\n' "${STUB_PODMAN_INSPECT}"
fi
exit "${STUB_PODMAN_STATUS:-0}"
EOF

    cat >"${STUB_BIN}/skopeo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${SKOPEO_LOG}"
if [[ "${STUB_SKOPEO_STATUS:-0}" -ne 0 ]]; then
    echo "skopeo: stub failure" >&2
    exit "${STUB_SKOPEO_STATUS}"
fi
printf '%s\n' "${STUB_SKOPEO_TAGS}"
EOF

    cat >"${STUB_BIN}/git" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    status) printf '%s' "${STUB_GIT_STATUS:-}" ;;
    rev-parse) printf '%s\n' "abc1234" ;;
esac
exit 0
EOF

    cat >"${STUB_BIN}/date" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-u" ]]; then
    printf '%s\n' "2026-08-30T00:00:00Z"
else
    printf '%s\n' "${STUB_DATE_YMD:-20260830}"
fi
EOF

    chmod +x "${STUB_BIN}"/*
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

run_just() {
    run bash -c "cd '${SANDBOX}' && just \"\$@\"" _ "$@"
}

# Returns the single recorded `podman build` argv line.
podman_build_args() {
    grep -m1 '^build ' "${PODMAN_LOG}"
}

@test "build: derives a bare <fedora>.<date> version for the stable tag" {
    run_just build finpilot stable
    [ "$status" -eq 0 ]
    [[ "$(podman_build_args)" == *"--build-arg VERSION=44.20260830"* ]]
}

@test "build: prefixes the version with the tag for non-stable tags" {
    run_just build finpilot testing
    [ "$status" -eq 0 ]
    [[ "$(podman_build_args)" == *"--build-arg VERSION=testing-44.20260830"* ]]
}

@test "build: treats any tag containing 'stable' as a stable build" {
    run_just build finpilot pre-stable
    [ "$status" -eq 0 ]
    [[ "$(podman_build_args)" == *"--build-arg VERSION=44.20260830"* ]]
}

@test "build: reads the Fedora major version from the Containerfile" {
    printf 'ARG FEDORA_MAJOR_VERSION="43"\nFROM scratch\n' >"${SANDBOX}/Containerfile"
    run_just build finpilot stable
    [ "$status" -eq 0 ]
    [[ "$(podman_build_args)" == *"--build-arg VERSION=43.20260830"* ]]
}

@test "build: accepts an unquoted FEDORA_MAJOR_VERSION ARG" {
    printf 'ARG FEDORA_MAJOR_VERSION=42\nFROM scratch\n' >"${SANDBOX}/Containerfile"
    run_just build finpilot stable
    [ "$status" -eq 0 ]
    [[ "$(podman_build_args)" == *"--build-arg VERSION=42.20260830"* ]]
}

@test "build: aborts when the Containerfile has no FEDORA_MAJOR_VERSION ARG" {
    printf 'FROM scratch\n' >"${SANDBOX}/Containerfile"
    run_just build finpilot stable
    [ "$status" -ne 0 ]
    [[ "$output" == *"Could not extract FEDORA_MAJOR_VERSION"* ]]
    [ ! -s "${PODMAN_LOG}" ] || ! grep -q '^build ' "${PODMAN_LOG}"
}

@test "build: appends a point release when the version tag already exists" {
    export STUB_SKOPEO_TAGS='{"Tags":["44.20260830"]}'
    run_just build finpilot stable
    [ "$status" -eq 0 ]
    [[ "$output" == *"Tag collision detected; using version 44.20260830.1"* ]]
    [[ "$(podman_build_args)" == *"--build-arg VERSION=44.20260830.1"* ]]
}

@test "build: walks past existing point releases to the first free one" {
    export STUB_SKOPEO_TAGS='{"Tags":["44.20260830","44.20260830.1","44.20260830.2"]}'
    run_just build finpilot stable
    [ "$status" -eq 0 ]
    [[ "$(podman_build_args)" == *"--build-arg VERSION=44.20260830.3"* ]]
}

@test "build: leaves the version untouched when the registry lookup fails" {
    export STUB_SKOPEO_STATUS=1
    run_just build finpilot stable
    [ "$status" -eq 0 ]
    [[ "$(podman_build_args)" == *"--build-arg VERSION=44.20260830"* ]]
    [[ "$output" != *"Tag collision detected"* ]]
}

@test "build: stamps SHA_HEAD_SHORT only when the worktree is clean" {
    run_just build finpilot stable
    [ "$status" -eq 0 ]
    [[ "$(podman_build_args)" == *"--build-arg SHA_HEAD_SHORT=abc1234"* ]]
}

@test "build: omits SHA_HEAD_SHORT when the worktree is dirty" {
    export STUB_GIT_STATUS=" M Containerfile"
    run_just build finpilot stable
    [ "$status" -eq 0 ]
    [[ "$(podman_build_args)" != *"SHA_HEAD_SHORT"* ]]
}

@test "build: passes the image identity build args bootc relies on" {
    run_just build finpilot stable
    [ "$status" -eq 0 ]
    local args
    args="$(podman_build_args)"
    [[ "${args}" == *"--build-arg IMAGE_NAME=finpilot"* ]]
    [[ "${args}" == *"--build-arg IMAGE_VENDOR=projectbluefin"* ]]
    [[ "${args}" == *"--build-arg UBLUE_IMAGE_TAG=stable"* ]]
}

@test "build: honours IMAGE_VENDOR and UBLUE_IMAGE_TAG overrides" {
    IMAGE_VENDOR="acme" UBLUE_IMAGE_TAG="pinned" run_just build finpilot stable
    [ "$status" -eq 0 ]
    local args
    args="$(podman_build_args)"
    [[ "${args}" == *"--build-arg IMAGE_VENDOR=acme"* ]]
    [[ "${args}" == *"--build-arg UBLUE_IMAGE_TAG=pinned"* ]]
}

# Characterization test: `IMAGE_NAME` is exported by the Justfile itself with a
# default of "finpilot", so `${IMAGE_NAME:-${target_image}}` can never fall back
# to the positional target_image. Building under a different name therefore
# still labels the image identity "finpilot". Pinned here so a fix is visible.
@test "build: IMAGE_NAME build arg ignores the positional target_image" {
    run_just build otherimage stable
    [ "$status" -eq 0 ]
    local args
    args="$(podman_build_args)"
    [[ "${args}" == *"--build-arg IMAGE_NAME=finpilot"* ]]
    [[ "${args}" == *"--tag otherimage:stable"* ]]
}

@test "build: forwards GITHUB_TOKEN as a build secret when set" {
    GITHUB_TOKEN="s3cret" run_just build finpilot stable
    [ "$status" -eq 0 ]
    [[ "$output" == *"Adding GitHub token as build secret"* ]]
    [[ "$(podman_build_args)" == *"--secret id=GITHUB_TOKEN,env=GITHUB_TOKEN"* ]]
}

@test "build: does not add a build secret when GITHUB_TOKEN is unset" {
    run_just build finpilot stable
    [ "$status" -eq 0 ]
    [[ "$(podman_build_args)" != *"--secret"* ]]
}

@test "build: applies the OCI and ArtifactHub labels" {
    run_just build finpilot stable
    [ "$status" -eq 0 ]
    local args
    args="$(podman_build_args)"
    [[ "${args}" == *"--label org.opencontainers.image.title=finpilot"* ]]
    [[ "${args}" == *"--label org.opencontainers.image.version=44.20260830"* ]]
    [[ "${args}" == *"--label org.opencontainers.image.vendor=projectbluefin"* ]]
    [[ "${args}" == *"--label org.opencontainers.image.created=2026-08-30T00:00:00Z"* ]]
    [[ "${args}" == *"--label io.artifacthub.package.license=Apache-2.0"* ]]
    [[ "${args}" == *"--label containers.bootc=1"* ]]
}

@test "build: reads the layer cache but never writes it by default" {
    run_just build finpilot stable
    [ "$status" -eq 0 ]
    local args
    args="$(podman_build_args)"
    [[ "${args}" == *"--cache-from ghcr.io/projectbluefin/finpilot"* ]]
    [[ "${args}" != *"--cache-to"* ]]
}

@test "build: writes the layer cache when REGISTRY_CACHE_WRITE=1" {
    REGISTRY_CACHE_WRITE=1 run_just build finpilot stable
    [ "$status" -eq 0 ]
    [[ "$(podman_build_args)" == *"--cache-to ghcr.io/projectbluefin/finpilot"* ]]
}

@test "build: skips cache args entirely when the cache ref is unreachable" {
    export STUB_SKOPEO_STATUS=1
    REGISTRY_CACHE_WRITE=1 run_just build finpilot stable
    [ "$status" -eq 0 ]
    local args
    args="$(podman_build_args)"
    [[ "${args}" != *"--cache-from"* ]]
    [[ "${args}" != *"--cache-to"* ]]
}

@test "build: pulls a newer base and tags the result target_image:tag" {
    run_just build finpilot testing
    [ "$status" -eq 0 ]
    local args
    args="$(podman_build_args)"
    [[ "${args}" == *"--pull=newer"* ]]
    [[ "${args}" == *"--tag finpilot:testing"* ]]
}

@test "tag-images: rejects an empty image name" {
    run_just tag-images "" stable "one two"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: just tag-images"* ]]
}

@test "tag-images: rejects an empty default tag" {
    run_just tag-images finpilot "" "one two"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: just tag-images"* ]]
}

@test "tag-images: rejects an empty tag list" {
    run_just tag-images finpilot stable ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: just tag-images"* ]]
}

@test "tag-images: untags the default tag before re-tagging by image id" {
    run_just tag-images finpilot stable "latest 44"
    [ "$status" -eq 0 ]

    mapfile -t calls <"${PODMAN_LOG}"
    [ "${calls[0]}" = "inspect localhost/finpilot:stable" ]
    [ "${calls[1]}" = "untag localhost/finpilot:stable" ]
    [ "${calls[2]}" = "tag sha256:deadbeef finpilot:latest" ]
    [ "${calls[3]}" = "tag sha256:deadbeef finpilot:44" ]
}

@test "tag-images: re-applies the default tag so local lookups still resolve" {
    run_just tag-images finpilot stable "latest"
    [ "$status" -eq 0 ]
    [[ "$(tail -n1 "${PODMAN_LOG}")" = "tag sha256:deadbeef finpilot:stable" ]]
    [[ "$output" == *"Tagged finpilot with: latest"* ]]
}

@test "tag-images: aborts when the image cannot be inspected" {
    export STUB_PODMAN_STATUS=1
    run_just tag-images finpilot stable "latest"
    [ "$status" -ne 0 ]
    ! grep -q '^untag ' "${PODMAN_LOG}"
}
