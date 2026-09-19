#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# Image identity
###############################################################################
# This is the first mutable image phase. It writes the identity consumed by
# bootc tooling and makes the installed operating system identify itself as
# this image rather than as its upstream base.
#
# The Containerfile is the source of truth for IMAGE_NAME, IMAGE_VENDOR and
# UBLUE_IMAGE_TAG. BASE_IMAGE_NAME and FEDORA_MAJOR_VERSION both describe the
# base image, whose FROM line is their source of truth. A normal downstream fork
# only needs to change its image name and vendor.
###############################################################################

: "${IMAGE_NAME:?IMAGE_NAME must be set}"
: "${IMAGE_VENDOR:?IMAGE_VENDOR must be set}"
: "${UBLUE_IMAGE_TAG:?UBLUE_IMAGE_TAG must be set}"
: "${BASE_IMAGE_NAME:?BASE_IMAGE_NAME must be set}"

VERSION="${VERSION:-${UBLUE_IMAGE_TAG}}"
HOME_URL="${HOME_URL:-https://github.com/${IMAGE_VENDOR}/${IMAGE_NAME}}"
DOCUMENTATION_URL="${DOCUMENTATION_URL:-${HOME_URL}/blob/main/README.md}"
SUPPORT_URL="${SUPPORT_URL:-${HOME_URL}/issues}"
BUG_REPORT_URL="${BUG_REPORT_URL:-${SUPPORT_URL}/new}"

# ROOT_DIR is a test seam. It is empty in the Containerfile build, where these
# paths correctly resolve to the image root.
ROOT_DIR="${ROOT_DIR:-}"
IMAGE_INFO="${ROOT_DIR}/usr/share/ublue-os/image-info.json"
OS_RELEASE="${ROOT_DIR}/usr/lib/os-release"

# The base image owns the Fedora major; the Containerfile declares no ARG for
# it. VERSION_ID is never rewritten below, so a repeat run agrees. An explicit
# FEDORA_MAJOR_VERSION still wins, matching the URL overrides above.
if [[ -z "${FEDORA_MAJOR_VERSION:-}" && -r "${OS_RELEASE}" ]]; then
    FEDORA_MAJOR_VERSION="$(sed -n 's/^VERSION_ID="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "${OS_RELEASE}")"
fi
: "${FEDORA_MAJOR_VERSION:?FEDORA_MAJOR_VERSION must be set or derivable from ${OS_RELEASE}}"

IMAGE_REF="ostree-image-signed:docker://ghcr.io/${IMAGE_VENDOR}/${IMAGE_NAME}"

json_escape() {
    local value=$1

    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}
    printf '%s' "${value}"
}

set_os_release_value() {
    local key=$1
    local value=$2
    local escaped_value

    if grep -q "^${key}=" "${OS_RELEASE}"; then
        # These escapes are for the sed replacement only. The append branch
        # writes the value verbatim, so it must not see them.
        escaped_value=${value//\\/\\\\}
        escaped_value=${escaped_value//\"/\\\"}
        escaped_value=${escaped_value//&/\\&}
        escaped_value=${escaped_value//|/\\|}
        sed -i "s|^${key}=.*|${key}=\"${escaped_value}\"|" "${OS_RELEASE}"
    else
        printf '%s="%s"\n' "${key}" "${value}" >>"${OS_RELEASE}"
    fi
}

###############################################################################
# /usr/share/ublue-os/image-info.json
###############################################################################
# Preserve Bluefin's generic schema: bootc image builders and ISO tooling read
# image-ref, while UBlue-aware runtime tools use the remaining identity fields.
install -d "$(dirname "${IMAGE_INFO}")"
cat >"${IMAGE_INFO}" <<EOF
{
  "image-name": "$(json_escape "${IMAGE_NAME}")",
  "image-vendor": "$(json_escape "${IMAGE_VENDOR}")",
  "image-ref": "$(json_escape "${IMAGE_REF}")",
  "image-tag": "$(json_escape "${UBLUE_IMAGE_TAG}")",
  "base-image-name": "$(json_escape "${BASE_IMAGE_NAME}")",
  "fedora-version": "$(json_escape "${FEDORA_MAJOR_VERSION}")"
}
EOF

###############################################################################
# /usr/lib/os-release
###############################################################################
# Unlike the previous append-only implementation, replace existing base-image
# values. Fedora Silverblue already has VARIANT_ID, so appending only when it
# was absent left installed Finpilot images reporting themselves as Fedora.
if [[ -f "${OS_RELEASE}" ]]; then
    set_os_release_value "VARIANT_ID" "${IMAGE_NAME}"
    set_os_release_value "PRETTY_NAME" "${IMAGE_NAME} (Version: ${VERSION})"
    set_os_release_value "NAME" "${IMAGE_NAME}"
    set_os_release_value "HOME_URL" "${HOME_URL}"
    set_os_release_value "DOCUMENTATION_URL" "${DOCUMENTATION_URL}"
    set_os_release_value "SUPPORT_URL" "${SUPPORT_URL}"
    set_os_release_value "BUG_REPORT_URL" "${BUG_REPORT_URL}"
    set_os_release_value "VERSION" "${VERSION} (${BASE_IMAGE_NAME})"
    set_os_release_value "OSTREE_VERSION" "${VERSION}"
    set_os_release_value "IMAGE_ID" "${IMAGE_NAME}"
    set_os_release_value "IMAGE_VERSION" "${VERSION}"

    # The build commit is deliberately not written here. SHA_HEAD_SHORT is
    # declared late in the Containerfile so a new commit only invalidates the
    # label layer, and this phase runs first, so the value is not available.
    # The commit ships as org.opencontainers.image.revision instead.
fi

printf 'Wrote %s\n' "${IMAGE_INFO}"
printf '  image-name: %s\n' "${IMAGE_NAME}"
printf '  image-vendor: %s\n' "${IMAGE_VENDOR}"
