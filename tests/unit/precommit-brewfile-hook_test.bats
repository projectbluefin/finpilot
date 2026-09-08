#!/usr/bin/env bats
# Contract gate for .pre-commit-config.yaml (see #323).
#
# build/validate-brewfiles.sh is the single implementation of Brewfile
# validation. It exists because Brewfiles are a Ruby DSL: handing a
# PR-controlled Brewfile to `brew bundle` / `brew bundle check` executes it.
# `pre-commit run --all-files` runs in CI (pr-validation.yml ->
# projectbluefin/actions/bootc-build/validate-pr), so a local hook that
# re-implements Brewfile handling re-opens that path by a second route.
#
# These tests fail if the hook stops being a caller of the single
# implementation, or starts evaluating repository Brewfiles again.
#
# Run with: bats tests/unit/precommit-brewfile-hook_test.bats

CONFIG="${BATS_TEST_DIRNAME}/../../.pre-commit-config.yaml"
SCRIPT="${BATS_TEST_DIRNAME}/../../build/validate-brewfiles.sh"

# The `entry:` line of the local validate-brewfiles hook.
hook_entry() {
    awk '
        /^[[:space:]]*-[[:space:]]*id:[[:space:]]*validate-brewfiles[[:space:]]*$/ { found = 1; next }
        found && /^[[:space:]]*entry:/ { sub(/^[[:space:]]*entry:[[:space:]]*/, ""); print; exit }
        found && /^[[:space:]]*-[[:space:]]*id:/ { exit }
    ' "${CONFIG}"
}

@test "pre-commit config exists and declares a validate-brewfiles hook" {
    [ -f "${CONFIG}" ]
    run hook_entry
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "validate-brewfiles hook delegates to build/validate-brewfiles.sh" {
    run hook_entry
    [ "$status" -eq 0 ]
    [[ "$output" == *"build/validate-brewfiles.sh"* ]]
}

@test "the delegated script is present" {
    [ -f "${SCRIPT}" ]
}

@test "the hook invokes the script the same way the Justfile does" {
    # Justfile:validate-brewfiles runs `bash build/validate-brewfiles.sh`.
    # The script is not committed with the executable bit, so the hook must
    # invoke it through bash too or pre-commit fails with EACCES.
    run hook_entry
    [ "$status" -eq 0 ]
    [[ "$output" == *"bash build/validate-brewfiles.sh"* ]]
    run grep -c 'bash build/validate-brewfiles.sh' "${BATS_TEST_DIRNAME}/../../Justfile"
    [ "$status" -eq 0 ]
}

@test "no pre-commit hook feeds a repository Brewfile to brew bundle" {
    # Any `brew bundle` (with or without `check`) in the config is a
    # re-implementation: the sole legitimate `brew bundle` call lives inside
    # build/validate-brewfiles.sh and runs on a generated literal-taps file,
    # never on a file from custom/brew/.
    # Strip full-line comments first so the rationale comment above the hook
    # does not trip its own gate.
    run bash -c "grep -v '^[[:space:]]*#' '${CONFIG}' | grep -n 'brew[[:space:]]\\+bundle'"
    [ "$status" -ne 0 ]
}

@test "no pre-commit hook globs custom/brew Brewfiles into a shell loop" {
    run bash -c "grep -v '^[[:space:]]*#' '${CONFIG}' | grep -n 'custom/brew/\\*'"
    [ "$status" -ne 0 ]
}

@test "the hook still skips cleanly when Homebrew is absent" {
    run hook_entry
    [ "$status" -eq 0 ]
    [[ "$output" == *"command -v brew"* ]]
}
