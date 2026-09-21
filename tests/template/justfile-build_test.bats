#!/usr/bin/env bats
# Unit tests for the root Justfile image recipes: `build` and `tag-images`.
#
# The recipes are exercised against a sandbox copy of the Justfile so the real
# repository is never touched. Every external command the recipes shell out to
# (podman, skopeo, git, date) is replaced by a stub on PATH that records its
# argv, which lets the tests assert on the argument vector `podman build` would
# have received without running a container build.
#
# Run with: bats tests/template/justfile-build_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."

setup() {
    if ! command -v just &>/dev/null; then
        skip "just is not installed"
    fi

    # REPO_ORG falls back to GITHUB_REPOSITORY_OWNER, which GitHub Actions sets
    # to the real repository owner. The assertions below expect the template's
    # documented default, so neutralise the ambient value here. The
    # owner-derived behaviour has its own test.
    unset GITHUB_REPOSITORY_OWNER

    TEST_ROOT="${BATS_TEST_TMPDIR:-${BATS_TMPDIR}}/justfile-build.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/stub-bin"
    SANDBOX="${TEST_ROOT}/repo"
    PODMAN_LOG="${TEST_ROOT}/logs/podman.log"
    SKOPEO_LOG="${TEST_ROOT}/logs/skopeo.log"

    mkdir -p "${STUB_BIN}" "${TEST_ROOT}/logs" "${SANDBOX}"

    cp "${REPO_ROOT}/Justfile" "${SANDBOX}/Justfile"
    printf 'FROM example.invalid/silverblue:44@sha256:deadbeef\n' >"${SANDBOX}/Containerfile"

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

@test "build: reads the base tag from the base FROM line" {
    printf 'FROM example.invalid/silverblue:43@sha256:deadbeef\n' >"${SANDBOX}/Containerfile"
    run_just build finpilot stable
    [ "$status" -eq 0 ]
    [[ "$(podman_build_args)" == *"--build-arg VERSION=43.20260830"* ]]
}

@test "build: reads the base FROM tag, not a context stage's tag" {
    printf 'FROM example.invalid/ctx:99@sha256:deadbeef AS ctx\nFROM example.invalid/silverblue:45@sha256:deadbeef\n' >"${SANDBOX}/Containerfile"
    run_just build finpilot stable
    [ "$status" -eq 0 ]
    [[ "$(podman_build_args)" == *"--build-arg VERSION=45.20260830"* ]]
}

@test "build: accepts a base FROM line without a digest" {
    printf 'FROM example.invalid/silverblue:42\n' >"${SANDBOX}/Containerfile"
    run_just build finpilot stable
    [ "$status" -eq 0 ]
    [[ "$(podman_build_args)" == *"--build-arg VERSION=42.20260830"* ]]
}

@test "build: accepts a non-numeric base tag verbatim" {
    # CentOS and Hummingbird bases tag with something other than a Fedora
    # major, so the tag is used as-is in the version string.
    printf 'FROM example.invalid/centos-bootc:stream10@sha256:deadbeef\n' >"${SANDBOX}/Containerfile"
    run_just build finpilot stable
    [ "$status" -eq 0 ]
    [[ "$(podman_build_args)" == *"--build-arg VERSION=stream10.20260830"* ]]
    [[ "$(podman_build_args)" == *"--build-arg BASE_IMAGE_NAME=centos-bootc"* ]]
}

@test "build: aborts when the base FROM line carries no tag" {
    printf 'FROM example.invalid/silverblue@sha256:deadbeef\n' >"${SANDBOX}/Containerfile"
    run_just build finpilot stable
    [ "$status" -ne 0 ]
    [[ "$output" == *"Could not read the base image"* ]]
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
    [[ "${args}" == *"--build-arg BASE_IMAGE_NAME=silverblue"* ]]
}

@test "build: passes the base image name read from the FROM line" {
    printf 'FROM example.invalid/other-base:44@sha256:deadbeef\n' >"${SANDBOX}/Containerfile"
    run_just build finpilot stable
    [ "$status" -eq 0 ]
    [[ "$(podman_build_args)" == *"--build-arg BASE_IMAGE_NAME=other-base"* ]]
}

@test "build: falls back to the GitHub repository owner for the vendor" {
    # A fork needs no edits: Actions sets GITHUB_REPOSITORY_OWNER, so the image
    # and its layer cache follow the fork's owner.
    GITHUB_REPOSITORY_OWNER="acme-org" run_just build finpilot stable
    [ "$status" -eq 0 ]

    local args
    args="$(podman_build_args)"
    [[ "${args}" == *"--build-arg IMAGE_VENDOR=acme-org"* ]]
    [[ "${args}" == *"--cache-from ghcr.io/acme-org/finpilot"* ]]
}

@test "build: honours IMAGE_VENDOR and UBLUE_IMAGE_TAG overrides" {
    IMAGE_VENDOR="acme" UBLUE_IMAGE_TAG="pinned" run_just build finpilot stable
    [ "$status" -eq 0 ]
    local args
    args="$(podman_build_args)"
    [[ "${args}" == *"--build-arg IMAGE_VENDOR=acme"* ]]
    [[ "${args}" == *"--build-arg UBLUE_IMAGE_TAG=pinned"* ]]
}

# The positional target_image wins for the image identity, minus any local
# registry prefix: `target_image` already defaults to IMAGE_NAME, so the default
# invocation is unchanged while `just build otherimage stable` now labels the
# identity "otherimage".
@test "build: IMAGE_NAME build arg follows the positional target_image" {
    run_just build otherimage stable
    [ "$status" -eq 0 ]
    local args
    args="$(podman_build_args)"
    [[ "${args}" == *"--build-arg IMAGE_NAME=otherimage"* ]]
    [[ "${args}" == *"--tag otherimage:stable"* ]]
}

@test "build: strips a local registry prefix from the image identity" {
    # The VM recipes pass localhost/<name> as target_image. The local tag keeps
    # the prefix; the identity must not, or image-info's image-ref names a
    # registry path that cannot exist and the ISO installs against it.
    run_just build localhost/finpilot stable
    [ "$status" -eq 0 ]
    local args
    args="$(podman_build_args)"
    [[ "${args}" == *"--build-arg IMAGE_NAME=finpilot"* ]]
    [[ "${args}" == *"--tag localhost/finpilot:stable"* ]]
}

@test "build: forwards GITHUB_TOKEN as a build secret when set" {
    GITHUB_TOKEN="s3cret" run_just build finpilot stable
    [ "$status" -eq 0 ]
    [[ "$output" == *"Adding GitHub token as build secret"* ]]
    [[ "$(podman_build_args)" == *"--secret id=GITHUB_TOKEN,env=GITHUB_TOKEN"* ]]
}

@test "build: does not add a build secret when GITHUB_TOKEN is unset" {
    # Do not inherit an exported token from the developer's shell or a workflow
    # that passes one in; the assertion is specifically about the unset case.
    unset GITHUB_TOKEN
    run_just build finpilot stable
    [ "$status" -eq 0 ]
    [[ "$(podman_build_args)" != *"--secret"* ]]
}

@test "build: supplies only dynamic OCI metadata to the Containerfile" {
    run_just build finpilot stable
    [ "$status" -eq 0 ]
    local args
    args="$(podman_build_args)"
    [[ "${args}" == *"--build-arg IMAGE_CREATED=2026-08-30T00:00:00Z"* ]]
    [[ "${args}" != *"IMAGE_DESC="* ]]
    [[ "${args}" != *"IMAGE_SOURCE="* ]]
    [[ "${args}" != *"IMAGE_URL="* ]]
    [[ "${args}" != *"IMAGE_README_URL="* ]]
    [[ "${args}" != *"--label "* ]]
}

@test "build: forwards explicit Containerfile metadata overrides" {
    IMAGE_DESC="Custom image" IMAGE_LOGO_URL="https://example.com/logo.svg" IMAGE_KEYWORDS="bootc,custom" IMAGE_REF="feature" run_just build finpilot stable
    [ "$status" -eq 0 ]
    local args
    args="$(podman_build_args)"
    [[ "${args}" == *"--build-arg IMAGE_DESC=Custom image"* ]]
    [[ "${args}" == *"--build-arg IMAGE_LOGO_URL=https://example.com/logo.svg"* ]]
    [[ "${args}" == *"--build-arg IMAGE_KEYWORDS=bootc,custom"* ]]
    [[ "${args}" == *"--build-arg IMAGE_REF=feature"* ]]
}

@test "Containerfile: owns the OCI and ArtifactHub label schema" {
    run grep -F 'LABEL org.opencontainers.image.title="${IMAGE_NAME}" \' "${REPO_ROOT}/Containerfile"
    [ "$status" -eq 0 ]
    run grep -F 'org.opencontainers.image.version="${VERSION}" \' "${REPO_ROOT}/Containerfile"
    [ "$status" -eq 0 ]
    run grep -F 'org.opencontainers.image.revision="${SHA_HEAD_SHORT}" \' "${REPO_ROOT}/Containerfile"
    [ "$status" -eq 0 ]
    run grep -F 'org.opencontainers.image.vendor="${IMAGE_VENDOR}" \' "${REPO_ROOT}/Containerfile"
    [ "$status" -eq 0 ]
    run grep -F 'org.opencontainers.image.source="https://github.com/${IMAGE_VENDOR}/${IMAGE_NAME}/blob/${IMAGE_REF}/Containerfile" \' "${REPO_ROOT}/Containerfile"
    [ "$status" -eq 0 ]
    run grep -F 'io.artifacthub.package.license="Apache-2.0" \' "${REPO_ROOT}/Containerfile"
    [ "$status" -eq 0 ]
    run grep -F 'containers.bootc="1"' "${REPO_ROOT}/Containerfile"
    [ "$status" -eq 0 ]
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

@test "Containerfile: declares SHA_HEAD_SHORT after the package layers" {
    # The commit changes on every push. Declaring the arg before the package and
    # overlay phases would invalidate those layers each time, so it belongs in
    # the late metadata block with the other volatile values.
    marker=$(grep -n '### IMAGE METADATA' "${REPO_ROOT}/Containerfile" | cut -d: -f1)
    arg=$(grep -n 'ARG SHA_HEAD_SHORT' "${REPO_ROOT}/Containerfile" | cut -d: -f1)
    [ -n "${marker}" ]
    [ -n "${arg}" ]
    [ "${arg}" -gt "${marker}" ]
}

@test "Justfile: the output chown does not read USER" {
    # The BIB recipes run under `set -u` from cron, containers and systemd, where
    # the kernel never exported USER. Reading it aborts the recipe after a 15-25
    # minute build, so ownership comes from id instead.
    line=$(grep -F 'chown -R' "${REPO_ROOT}/Justfile")
    [ -n "${line}" ]
    [[ "${line}" == *'$(id -u):$(id -g)'* ]]
    [[ "${line}" != *'$USER'* ]]
}
