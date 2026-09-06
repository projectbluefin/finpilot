#!/usr/bin/env bats
# Unit tests for build/00-image-info.sh.
#
# The script writes to two hardcoded absolute paths (/usr/share/ublue-os and
# /usr/lib/os-release) and has no filesystem-prefix hook, so each test rewrites
# a throwaway copy of the script to point at a sandbox root before running it.
# Production behaviour is never modified; the rewrite is asserted below so the
# suite fails loudly if the paths in the script ever drift.
#
# Run with: bats tests/unit/00-image-info_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
IMAGE_INFO_SRC="${SCRIPT_DIR}/../../build/00-image-info.sh"

setup() {
    TEST_ROOT="${BATS_TEST_TMPDIR:-${BATS_TMPDIR}}/image-info.${BATS_TEST_NUMBER:-0}.$$"
    SANDBOX="${TEST_ROOT}/root"
    SCRIPT="${TEST_ROOT}/00-image-info.sh"

    mkdir -p "${SANDBOX}/usr/lib"

    IMAGE_INFO_JSON="${SANDBOX}/usr/share/ublue-os/image-info.json"
    OS_RELEASE="${SANDBOX}/usr/lib/os-release"

    sed \
        -e "s#^IMAGE_INFO=\"/usr/share/ublue-os/image-info.json\"#IMAGE_INFO=\"${SANDBOX}/usr/share/ublue-os/image-info.json\"#" \
        -e "s#^OS_RELEASE=\"/usr/lib/os-release\"#OS_RELEASE=\"${SANDBOX}/usr/lib/os-release\"#" \
        -e "s#^mkdir -p /usr/share/ublue-os\$#mkdir -p ${SANDBOX}/usr/share/ublue-os#" \
        "${IMAGE_INFO_SRC}" >"${SCRIPT}"

    # Required env vars, per the header contract of the script.
    export IMAGE_NAME="finpilot"
    export IMAGE_VENDOR="projectbluefin"
    export UBLUE_IMAGE_TAG="latest"
    export BASE_IMAGE_NAME="silverblue"
    export FEDORA_MAJOR_VERSION="42"

    # A stock os-release with no VARIANT_ID, matching a fresh Fedora base image.
    cat >"${OS_RELEASE}" <<'EOF'
NAME="Fedora Linux"
ID=fedora
VERSION_ID=42
EOF
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

json_field() {
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "${IMAGE_INFO_JSON}" "$1"
}

@test "00-image-info: sandbox rewrite left no writes to the host filesystem" {
    # Guards the rewrite above: if the script's paths change, the sed no longer
    # matches and every other test in this file would silently write to the host.
    run grep -nE '^IMAGE_INFO="/usr/|^OS_RELEASE="/usr/|^mkdir -p /usr/' "${SCRIPT}"
    [ "$status" -ne 0 ]

    grep -q "^IMAGE_INFO=\"${SANDBOX}/usr/share/ublue-os/image-info.json\"$" "${SCRIPT}"
    grep -q "^OS_RELEASE=\"${SANDBOX}/usr/lib/os-release\"$" "${SCRIPT}"
    grep -q "^mkdir -p ${SANDBOX}/usr/share/ublue-os$" "${SCRIPT}"
}

@test "00-image-info: writes image-info.json and exits cleanly" {
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]
    [ -f "${IMAGE_INFO_JSON}" ]
}

@test "00-image-info: image-info.json is valid JSON with the documented fields" {
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]

    run python3 -m json.tool "${IMAGE_INFO_JSON}"
    [ "$status" -eq 0 ]

    [ "$(json_field image-name)" = "finpilot" ]
    [ "$(json_field image-vendor)" = "projectbluefin" ]
    [ "$(json_field image-tag)" = "latest" ]
    [ "$(json_field base-image-name)" = "silverblue" ]
    [ "$(json_field fedora-version)" = "42" ]
}

@test "00-image-info: image-ref is the signed ghcr ref bootc upgrades from" {
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]
    [ "$(json_field image-ref)" = "ostree-image-signed:docker://ghcr.io/projectbluefin/finpilot" ]
}

@test "00-image-info: image flavor is main for a non-nvidia image name" {
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]
    [ "$(json_field image-flavor)" = "main" ]
}

@test "00-image-info: image flavor is nvidia when the name contains nvidia" {
    export IMAGE_NAME="finpilot-nvidia"
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]
    [ "$(json_field image-flavor)" = "nvidia" ]
    [ "$(json_field image-ref)" = "ostree-image-signed:docker://ghcr.io/projectbluefin/finpilot-nvidia" ]
}

@test "00-image-info: nvidia match is a substring match, not a suffix match" {
    export IMAGE_NAME="finpilot-nvidia-open"
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]
    [ "$(json_field image-flavor)" = "nvidia" ]
}

@test "00-image-info: reports the derived identity on stdout" {
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"image-name: finpilot"* ]]
    [[ "$output" == *"image-flavor: main"* ]]
    [[ "$output" == *"image-vendor: projectbluefin"* ]]
}

@test "00-image-info: appends image identity to os-release" {
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Customized"* ]]

    run grep -c '^VARIANT_ID="main"$' "${OS_RELEASE}"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]

    grep -q '^NAME="finpilot"$' "${OS_RELEASE}"
    grep -q '^IMAGE_ID="finpilot"$' "${OS_RELEASE}"
    grep -q '^ID_LIKE="fedora"$' "${OS_RELEASE}"
}

@test "00-image-info: os-release URLs default to the vendor/name GitHub repo" {
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]

    grep -q '^HOME_URL="https://github.com/projectbluefin/finpilot"$' "${OS_RELEASE}"
    grep -q '^DOCUMENTATION_URL="https://github.com/projectbluefin/finpilot/blob/main/README.md"$' "${OS_RELEASE}"
    grep -q '^SUPPORT_URL="https://github.com/projectbluefin/finpilot/issues"$' "${OS_RELEASE}"
    grep -q '^BUG_REPORT_URL="https://github.com/projectbluefin/finpilot/issues/new"$' "${OS_RELEASE}"
}

@test "00-image-info: branding env vars override the defaults" {
    export IMAGE_PRETTY_NAME="Finpilot OS"
    export IMAGE_LIKE="fedora rhel"
    export HOME_URL="https://finpilot.example"
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]

    grep -q '^PRETTY_NAME="Finpilot OS"$' "${OS_RELEASE}"
    grep -q '^ID_LIKE="fedora rhel"$' "${OS_RELEASE}"
    grep -q '^HOME_URL="https://finpilot.example"$' "${OS_RELEASE}"
}

@test "00-image-info: IMAGE_VERSION uses VERSION when it is set" {
    export VERSION="stable-42.20250531"
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]
    grep -q '^IMAGE_VERSION="stable-42.20250531"$' "${OS_RELEASE}"
}

@test "00-image-info: IMAGE_VERSION falls back to the image tag when VERSION is unset" {
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]
    grep -q '^IMAGE_VERSION="latest"$' "${OS_RELEASE}"
}

@test "00-image-info: IMAGE_VERSION falls back to the image tag when VERSION is empty" {
    export VERSION=""
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]
    grep -q '^IMAGE_VERSION="latest"$' "${OS_RELEASE}"
}

@test "00-image-info: os-release append is idempotent across two runs" {
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]

    run grep -c '^VARIANT_ID=' "${OS_RELEASE}"
    [ "$output" -eq 1 ]
    run grep -c '^IMAGE_ID="finpilot"$' "${OS_RELEASE}"
    [ "$output" -eq 1 ]
}

@test "00-image-info: pre-existing VARIANT_ID suppresses the os-release append" {
    printf 'VARIANT_ID="preset"\n' >>"${OS_RELEASE}"
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Customized"* ]]

    run grep -c '^VARIANT_ID=' "${OS_RELEASE}"
    [ "$output" -eq 1 ]
    grep -q '^VARIANT_ID="preset"$' "${OS_RELEASE}"
}

@test "00-image-info: image-info.json is still written when os-release is absent" {
    rm -f "${OS_RELEASE}"
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]
    [ -f "${IMAGE_INFO_JSON}" ]
    [ ! -f "${OS_RELEASE}" ]
}

@test "00-image-info: image-info.json is rewritten, not appended, on a second run" {
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]
    export IMAGE_NAME="finpilot-nvidia"
    run bash "${SCRIPT}"
    [ "$status" -eq 0 ]

    run python3 -m json.tool "${IMAGE_INFO_JSON}"
    [ "$status" -eq 0 ]
    [ "$(json_field image-name)" = "finpilot-nvidia" ]
}

@test "00-image-info: fails fast when a required env var is missing" {
    unset IMAGE_NAME
    run bash "${SCRIPT}"
    [ "$status" -ne 0 ]
    [ ! -f "${IMAGE_INFO_JSON}" ]
}

@test "00-image-info: fails fast when the image tag is missing" {
    unset UBLUE_IMAGE_TAG
    run bash "${SCRIPT}"
    [ "$status" -ne 0 ]
}
