#!/usr/bin/bash

set -euo pipefail

###############################################################################
# Image Info Generation
###############################################################################
# Generates /usr/share/ublue-os/image-info.json and customizes /usr/lib/os-release.
# This script is bluefin-pattern: each consumer provides its own branding.
#
# Required env vars (set as ARGs in Containerfile):
#   IMAGE_NAME          - Image name (e.g. finpilot, my-custom-os)
#   IMAGE_VENDOR        - Image vendor/owner (e.g. github username or org)
#   UBLUE_IMAGE_TAG     - Image tag/stream (e.g. stable, testing, latest)
#   BASE_IMAGE_NAME     - Base image name (e.g. silverblue)
#   FEDORA_MAJOR_VERSION - Fedora version (e.g. 42)
#   VERSION             - Full version string (e.g. stable-42.20250531)
#   SHA_HEAD_SHORT      - Short git SHA (optional, for dev builds)
###############################################################################

# Branding — customize these for your image
IMAGE_PRETTY_NAME="${IMAGE_PRETTY_NAME:-My Custom OS}"
IMAGE_LIKE="${IMAGE_LIKE:-fedora}"
HOME_URL="${HOME_URL:-https://github.com/${IMAGE_VENDOR}/${IMAGE_NAME}}"
DOCUMENTATION_URL="${DOCUMENTATION_URL:-https://github.com/${IMAGE_VENDOR}/${IMAGE_NAME}/blob/main/README.md}"
SUPPORT_URL="${SUPPORT_URL:-https://github.com/${IMAGE_VENDOR}/${IMAGE_NAME}/issues}"
BUG_REPORT_URL="${BUG_REPORT_URL:-https://github.com/${IMAGE_VENDOR}/${IMAGE_NAME}/issues/new}"

# Paths
IMAGE_INFO="/usr/share/ublue-os/image-info.json"
OS_RELEASE="/usr/lib/os-release"

# Derive image flavor from name
if [[ "${IMAGE_NAME}" =~ nvidia ]]; then
	IMAGE_FLAVOR="nvidia"
else
	IMAGE_FLAVOR="main"
fi

# Image ref (used by bootc for upgrade source)
IMAGE_REF="ostree-image-signed:docker://ghcr.io/${IMAGE_VENDOR}/${IMAGE_NAME}"

###############################################################################
# Write image-info.json
###############################################################################
mkdir -p /usr/share/ublue-os
cat >"${IMAGE_INFO}" <<EOF
{
  "image-name": "${IMAGE_NAME}",
  "image-flavor": "${IMAGE_FLAVOR}",
  "image-vendor": "${IMAGE_VENDOR}",
  "image-ref": "${IMAGE_REF}",
  "image-tag": "${UBLUE_IMAGE_TAG}",
  "base-image-name": "${BASE_IMAGE_NAME}",
  "fedora-version": "${FEDORA_MAJOR_VERSION}"
}
EOF

echo "Wrote ${IMAGE_INFO}"
echo "  image-name: ${IMAGE_NAME}"
echo "  image-flavor: ${IMAGE_FLAVOR}"
echo "  image-vendor: ${IMAGE_VENDOR}"

###############################################################################
# Customize /usr/lib/os-release
###############################################################################
# The block below is guarded by its own marker, not by VARIANT_ID: every
# fedora-ostree-desktops base already ships a VARIANT_ID (silverblue, kinoite,
# ...), so keying off it would skip the append on every real build.
OS_RELEASE_MARKER="# ${IMAGE_NAME} image identity"

# Keys this script owns. Stale values inherited from the base image are removed
# before the block is appended, so no key is ever defined twice.
OS_RELEASE_KEYS=(
	VARIANT
	VARIANT_ID
	PRETTY_NAME
	NAME
	IMAGE_ID
	IMAGE_VERSION
	ID_LIKE
	HOME_URL
	DOCUMENTATION_URL
	SUPPORT_URL
	BUG_REPORT_URL
)

if [[ -f "${OS_RELEASE}" ]] && ! grep -qxF "${OS_RELEASE_MARKER}" "${OS_RELEASE}"; then
	# Read existing values
	if [[ -n "${VERSION:-}" ]]; then
		OS_VERSION="${VERSION}"
	else
		OS_VERSION="${UBLUE_IMAGE_TAG}"
	fi

	for key in "${OS_RELEASE_KEYS[@]}"; do
		sed -i "/^${key}=/d" "${OS_RELEASE}"
	done

	# Append our identity
	cat >>"${OS_RELEASE}" <<EOF

${OS_RELEASE_MARKER}
VARIANT="${IMAGE_PRETTY_NAME}"
VARIANT_ID="${IMAGE_FLAVOR}"
PRETTY_NAME="${IMAGE_PRETTY_NAME}"
NAME="${IMAGE_NAME}"
IMAGE_ID="${IMAGE_NAME}"
IMAGE_VERSION="${OS_VERSION}"
ID_LIKE="${IMAGE_LIKE}"
HOME_URL="${HOME_URL}"
DOCUMENTATION_URL="${DOCUMENTATION_URL}"
SUPPORT_URL="${SUPPORT_URL}"
BUG_REPORT_URL="${BUG_REPORT_URL}"
EOF

	echo "Customized ${OS_RELEASE}"
fi
