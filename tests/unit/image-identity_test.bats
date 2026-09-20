#!/usr/bin/env bats
# Drift gate for the image-identity rename contract (see #291).
#
# The project name is restated in files that cannot read each other. This gate
# makes `Containerfile`'s `ARG IMAGE_NAME` the canonical value and fails if any
# other rename site disagrees, if `.github/workflows/clean.yml` stops deriving
# its package name, or if README's rename checklist stops naming exactly the
# files this gate covers.
#
# Run with: bats tests/unit/image-identity_test.bats

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

# Files that carry the literal project name and are checked below. The README
# checklist is asserted to name exactly this set.
GATED_SITES=(
    "Containerfile"
    "Justfile"
    "README.md"
    "artifacthub-repo.yml"
    "custom/ujust/README.md"
    "iso/iso.toml"
)

canonical_name() {
    sed -n 's/^ARG IMAGE_NAME="\([^"]*\)".*/\1/p' "${REPO_ROOT}/Containerfile" | head -n1
}

canonical_vendor() {
    sed -n 's/^ARG IMAGE_VENDOR="\([^"]*\)".*/\1/p' "${REPO_ROOT}/Containerfile" | head -n1
}

lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# Numbered entries of the "Rename the Project" README section, one path per line.
readme_checklist_paths() {
    awk '
        /^### 2\. Rename the Project/ {inside=1; next}
        inside && /^### / {exit}
        inside && /^[0-9]+\. `/ {
            match($0, /`[^`]+`/)
            print substr($0, RSTART + 1, RLENGTH - 2)
        }
    ' "${REPO_ROOT}/README.md"
}

@test "Containerfile declares a canonical image name and vendor" {
    [ -n "$(canonical_name)" ]
    [ -n "$(canonical_vendor)" ]
}

@test "Containerfile '# Name:' comment matches ARG IMAGE_NAME" {
    name="$(sed -n 's/^# Name: \(.*\)$/\1/p' "${REPO_ROOT}/Containerfile" | head -n1)"
    [ "${name}" = "$(canonical_name)" ]
}

@test "Justfile IMAGE_NAME default matches the canonical name" {
    name="$(sed -n 's/^export IMAGE_NAME := env("IMAGE_NAME", "\([^"]*\)").*/\1/p' "${REPO_ROOT}/Justfile" | head -n1)"
    [ "${name}" = "$(canonical_name)" ]
}

@test "README title matches the canonical name" {
    title="$(sed -n 's/^# \(.*\)$/\1/p' "${REPO_ROOT}/README.md" | head -n1)"
    [ "$(lower "${title}")" = "$(lower "$(canonical_name)")" ]
}

@test "artifacthub-repo.yml repositoryID matches the canonical name" {
    id="$(sed -n 's/^repositoryID: *\([^ #]*\).*/\1/p' "${REPO_ROOT}/artifacthub-repo.yml" | head -n1)"
    [ "${id}" = "$(canonical_name)" ]
}

@test "custom/ujust/README.md bootc switch example matches the canonical name" {
    ref="$(sed -n 's|.*bootc switch --target localhost/\([^:`]*\):stable.*|\1|p' "${REPO_ROOT}/custom/ujust/README.md" | head -n1)"
    [ -n "${ref}" ]
    [ "${ref}" = "$(canonical_name)" ]
}

@test "iso/iso.toml kickstart ref matches the canonical vendor and name" {
    ref="$(sed -n 's|^bootc switch .*--transport registry \(ghcr.io/[^ ]*\).*|\1|p' "${REPO_ROOT}/iso/iso.toml" | head -n1)"
    [ -n "${ref}" ]
    [ "${ref}" = "ghcr.io/$(canonical_vendor)/$(canonical_name):stable" ]
}

@test "iso/iso.toml ships no placeholder registry ref" {
    run grep -nE 'ghcr\.io/(USERNAME|YOUR_USERNAME|<[^>]+>)/' "${REPO_ROOT}/iso/iso.toml"
    [ "$status" -ne 0 ] || [[ "$output" == *"FORK NOTE"* ]]
}

@test "clean.yml derives its package name instead of hardcoding it" {
    run grep -F 'github.event.repository.name' "${REPO_ROOT}/.github/workflows/clean.yml"
    [ "$status" -eq 0 ]
}

@test "clean.yml does not restate the canonical image name" {
    run grep -F "$(canonical_name)" "${REPO_ROOT}/.github/workflows/clean.yml"
    [ "$status" -ne 0 ]
}

@test "README rename checklist names exactly the gated sites" {
    expected="$(printf '%s\n' "${GATED_SITES[@]}" | sort)"
    actual="$(readme_checklist_paths | sort)"
    [ "${actual}" = "${expected}" ]
}

@test "README rename checklist count matches the number of gated sites" {
    run grep -cE '^Important: Change `[^`]+` to your repository name in these '"${#GATED_SITES[@]}"' files:' "${REPO_ROOT}/README.md"
    [ "$output" = "1" ]
}
