#!/usr/bin/env bats
# Contract gate for the base-image pin.
#
# "Which base image this repo builds on, and which Fedora major release that
# is" is restated in five places that cannot read each other:
#
#   1. Containerfile          FROM quay.io/fedora-ostree-desktops/silverblue:<tag>@sha256:...
#   2. Containerfile          ARG BASE_IMAGE_NAME="<name>"
#   3. Containerfile          ARG FEDORA_MAJOR_VERSION="<tag>"
#   4. .agents/skills/**.md   literal restatements of 1-3
#   5. Justfile:build         greps ARG FEDORA_MAJOR_VERSION out of the Containerfile
#
# Only site 1 is maintained by Renovate. Sites 2 and 3 are the ones
# build/00-image-info.sh writes into /usr/share/ublue-os/image-info.json and
# /usr/lib/os-release, and site 3 is what Justfile:build stamps into the image
# version string and the OCI version label. A Fedora major bump that edits the
# FROM line alone therefore ships an image that reports the wrong base image
# and the wrong Fedora release, with no build-time signal.
#
# These tests fail when any restatement drifts from the FROM line.
#
# Run with: bats tests/unit/containerfile-base-pin_test.bats

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
CONTAINERFILE="${REPO_ROOT}/Containerfile"
JUSTFILE="${REPO_ROOT}/Justfile"
SKILLS_DIR="${REPO_ROOT}/.agents/skills"

# The single FROM line that is not an aliased context stage.
base_from_ref() {
    grep -E '^FROM[[:space:]]' "${CONTAINERFILE}" | grep -viE '[[:space:]]AS[[:space:]]' | awk '{print $2}'
}

# Value of `ARG <name>="<value>"` (quotes optional) in the Containerfile.
arg_value() {
    sed -nE "s/^ARG $1=\"?([^\"[:space:]]*)\"?[[:space:]]*\$/\1/p" "${CONTAINERFILE}"
}

# quay.io/fedora-ostree-desktops/silverblue:44@sha256:... -> silverblue
base_image_short_name() {
    local ref name_and_tag
    ref="$(base_from_ref)"
    name_and_tag="${ref%%@*}"
    printf '%s\n' "$(basename "${name_and_tag%:*}")"
}

# quay.io/fedora-ostree-desktops/silverblue:44@sha256:... -> 44
base_image_tag() {
    local ref name_and_tag
    ref="$(base_from_ref)"
    name_and_tag="${ref%%@*}"
    printf '%s\n' "${name_and_tag##*:}"
}

@test "Containerfile declares exactly one non-aliased base FROM" {
    run base_from_ref
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
}

@test "base FROM is pinned by digest" {
    [[ "$(base_from_ref)" == *"@sha256:"* ]]
}

@test "base FROM carries an explicit tag alongside the digest" {
    local name_and_tag
    name_and_tag="$(base_from_ref)"
    name_and_tag="${name_and_tag%%@*}"
    # A tag is present only if the last path segment contains a colon.
    [[ "$(basename "${name_and_tag}")" == *:* ]]
}

@test "ARG BASE_IMAGE_NAME is declared exactly once" {
    [ "$(arg_value BASE_IMAGE_NAME | grep -c .)" -eq 1 ]
}

@test "ARG FEDORA_MAJOR_VERSION is declared exactly once" {
    [ "$(arg_value FEDORA_MAJOR_VERSION | grep -c .)" -eq 1 ]
}

@test "ARG BASE_IMAGE_NAME matches the base FROM image name" {
    [ "$(arg_value BASE_IMAGE_NAME)" = "$(base_image_short_name)" ]
}

@test "ARG FEDORA_MAJOR_VERSION matches the base FROM tag" {
    [ "$(arg_value FEDORA_MAJOR_VERSION)" = "$(base_image_tag)" ]
}

@test "Justfile:build still extracts FEDORA_MAJOR_VERSION from the Containerfile" {
    grep -qF "grep -E '^ARG FEDORA_MAJOR_VERSION=' Containerfile" "${JUSTFILE}"
}

@test "the Justfile extraction pipeline yields the base FROM tag" {
    local extracted
    extracted=$(grep -E '^ARG FEDORA_MAJOR_VERSION=' "${CONTAINERFILE}" | head -n1 |
        sed -E 's/^ARG FEDORA_MAJOR_VERSION="?([^"]+)"?/\1/')
    [ -n "${extracted}" ]
    [ "${extracted}" = "$(base_image_tag)" ]
}

@test "build/00-image-info.sh consumes both base-image ARGs" {
    grep -qF '${BASE_IMAGE_NAME}' "${REPO_ROOT}/build/00-image-info.sh"
    grep -qF '${FEDORA_MAJOR_VERSION}' "${REPO_ROOT}/build/00-image-info.sh"
}

@test "skills docs do not restate a stale FEDORA_MAJOR_VERSION" {
    local expected stale
    expected="$(base_image_tag)"
    stale=$(grep -rhoE 'ARG FEDORA_MAJOR_VERSION="?[^"[:space:]]+"?' "${SKILLS_DIR}" |
        sed -E 's/.*=("?)([^"]*)\1/\2/' | grep -vx "${expected}" || true)
    [ -z "${stale}" ] || {
        echo "skills docs restate FEDORA_MAJOR_VERSION as: ${stale} (Containerfile: ${expected})"
        false
    }
}

@test "skills docs do not restate a stale BASE_IMAGE_NAME" {
    local expected stale
    expected="$(base_image_short_name)"
    stale=$(grep -rhoE 'ARG BASE_IMAGE_NAME="?[^"[:space:]]+"?' "${SKILLS_DIR}" |
        sed -E 's/.*=("?)([^"]*)\1/\2/' | grep -vx "${expected}" || true)
    [ -z "${stale}" ] || {
        echo "skills docs restate BASE_IMAGE_NAME as: ${stale} (Containerfile: ${expected})"
        false
    }
}

@test "skills docs do not restate a stale base image reference" {
    local expected stale
    expected="$(base_image_short_name):$(base_image_tag)"
    stale=$(grep -rhoE 'fedora-ostree-desktops/[A-Za-z0-9._-]+:[A-Za-z0-9._-]+' "${SKILLS_DIR}" |
        sed -E 's#.*/##' | sort -u | grep -vx "${expected}" || true)
    [ -z "${stale}" ] || {
        echo "skills docs reference base images: ${stale} (Containerfile: ${expected})"
        false
    }
}
