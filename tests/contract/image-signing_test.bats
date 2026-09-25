#!/usr/bin/env bats
# Contract: the update transport in image-info.json and the trust policy the
# image actually ships must agree. They are written in different files that
# cannot read each other, and getting them out of step is silent in both
# directions:
#
#   signed transport, no matching policy scope -> verification "succeeds"
#       against Common's `""` catch-all (insecureAcceptAnything) and checks
#       nothing, while image-info.json and the README claim it does.
#   policy scope, unverified transport -> the scope is never consulted, so a
#       signature the operator believes is enforced is not.
#
# Today the image is signed keyless in CI and verified nowhere on the device,
# so the transport is unverified and the template adds no policy scope. A
# change to either side fails here, which is the point: flipping one is a
# deliberate act that has to flip the other.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
IMAGE_INFO_SRC="${REPO_ROOT}/build/00-image-info.sh"

# Comments in the build scripts discuss the policy at length; only executable
# lines can change what the image ships.
grep_code() {
    grep -nE "$1" "${REPO_ROOT}"/build/*.sh "${REPO_ROOT}"/build/*.sh.example |
        grep -vE ':[0-9]+:[[:space:]]*#'
}

@test "image-signing: the update ref uses an unverified transport" {
    run grep -cE '^IMAGE_REF="ostree-unverified-image:docker://' "${IMAGE_INFO_SRC}"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}

@test "image-signing: no build phase claims a verified transport" {
    # `ostree-image-signed:` and `ostree-remote-image:` both make the client
    # consult /etc/containers/policy.json before deploying.
    run grep_code 'ostree-image-signed:|ostree-remote-image:'
    [ "$status" -ne 0 ]
}

@test "image-signing: the update ref keeps the docker:// spelling" {
    # `just build-iso` recovers the published reference from image-info.json
    # with `sed 's|.*docker://||'`. A registry-shorthand transport such as
    # ostree-unverified-registry: has no docker:// to strip, and the ISO would
    # be built against a reference still carrying the transport prefix.
    run grep -F "sed 's|.*docker://||'" "${REPO_ROOT}/Justfile"
    [ "$status" -eq 0 ]
}

@test "image-signing: the template ships no trust policy of its own" {
    # /etc/containers/policy.json is a single file with no drop-in directory,
    # so shipping one through custom/files would replace Common's wholesale and
    # freeze every scope in it.
    [ ! -e "${REPO_ROOT}/custom/files/etc/containers/policy.json" ]
}

@test "image-signing: the template ships no sigstore registries.d entry" {
    # Without use-sigstore-attachments for this namespace the client does not
    # even fetch the signature, so an entry appearing here means someone
    # intended device-side verification.
    [ ! -d "${REPO_ROOT}/custom/files/etc/containers/registries.d" ]
}

@test "image-signing: no build phase merges a policy scope" {
    run grep_code 'policy\.json|registries\.d'
    [ "$status" -ne 0 ]
}

@test "image-signing: the README says where the signature is checked" {
    run grep -F 'not verified on the device' "${REPO_ROOT}/README.md"
    [ "$status" -eq 0 ]
}
