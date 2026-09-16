#!/usr/bin/env bats
# Contract gate for the Containerfile ARG / Justfile --build-arg relationship.
#
# `just build` stamps a fixed set of `--build-arg NAME=value` pairs into
# `podman build`, and a build arg whose name is never declared with `ARG` in
# the Containerfile is silently discarded by the builder: it reaches no RUN
# layer and Podman/Buildah emits a "one or more build args were not consumed"
# warning. That warning is the repo's only signal for a genuinely misspelled
# build arg, so an undeclared arg is not a silent no-op — it is noise that
# drowns the real signal.
#
# The two sides cannot read each other: the Justfile lists the `--build-arg`
# names in the `build` recipe, and the Containerfile lists the `ARG`s in its
# identity block. A new arg added to one side without the other therefore
# ships (or warns) with no cross-check.
#
# These tests fail the moment any `--build-arg` name the Justfile passes is
# missing an `ARG` declaration in the Containerfile, so a fourth undeclared
# arg cannot appear silently.
#
# Run with: bats tests/unit/justfile-build-arg-gate_test.bats

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
CONTAINERFILE="${REPO_ROOT}/Containerfile"
JUSTFILE="${REPO_ROOT}/Justfile"

# Every `--build-arg` NAME the Justfile passes, one per line.
passed_build_args() {
    grep -oE '"--build-arg"[[:space:]]+"[A-Za-z_][A-Za-z0-9_]*=' "${JUSTFILE}" \
        | sed -E 's/^"--build-arg"[[:space:]]+"([A-Za-z_][A-Za-z0-9_]*)=$/\1/'
}

# Every `ARG NAME` the Containerfile declares, one per line.
declared_args() {
    grep -E '^ARG ' "${CONTAINERFILE}" \
        | sed -E 's/^ARG ([A-Za-z_][A-Za-z0-9_]*)=.*/\1/'
}

@test "the Justfile passes at least one --build-arg" {
    [ "$(passed_build_args | grep -c .)" -ge 1 ]
}

@test "the Containerfile declares at least one ARG" {
    [ "$(declared_args | grep -c .)" -ge 1 ]
}

@test "every --build-arg the Justfile passes is declared as an ARG in the Containerfile" {
    while IFS= read -r name; do
        [ -n "${name}" ] || continue
        [[ "$(declared_args)" == *"${name}"* ]] \
            || { echo "FAIL: --build-arg ${name} has no ARG declaration"; return 1; }
    done < <(passed_build_args)
}

@test "no --build-arg the Justfile passes is missing from the Containerfile" {
    missing=0
    while IFS= read -r name; do
        [ -n "${name}" ] || continue
        grep -qxF "${name}" <(declared_args) || {
            echo "undeclared --build-arg: ${name}"
            missing=1
        }
    done < <(passed_build_args)
    [ "${missing}" -eq 0 ]
}
