#!/usr/bin/env bats
# Drift gate for .shellcheck-scope (see #324).
#
# .shellcheck-scope is the single source of truth for "which shell scripts this
# repo lints". Two consumers read it:
#   - Justfile:lint (via the private `shell-sources` recipe)
#   - .github/workflows/pr-validation.yml, which resolves it into the
#     `shellcheck-glob` input of bootc-build/validate-pr
#
# Before it existed, the scope was stated twice with divergent values and
# .github/actions/check-token-health/check_token_health.sh — the one shell
# script in the repo that handles a credential — was never shellchecked in CI.
# These tests fail if the scope drifts away from the tree again, or if a
# consumer stops reading the manifest and re-hardcodes a glob.
#
# Run with: bats tests/unit/shellcheck-scope_test.bats

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
SCOPE="${REPO_ROOT}/.shellcheck-scope"
WORKFLOW="${REPO_ROOT}/.github/workflows/pr-validation.yml"
JUSTFILE="${REPO_ROOT}/Justfile"

# Declared glob patterns, comments and blank lines stripped.
scope_patterns() {
    sed 's/#.*//' "${SCOPE}" | tr -d '[:blank:]' | grep -v '^$'
}

# Files matched by the declared patterns, expanded from the repository root.
scope_matches() {
    (
        cd "${REPO_ROOT}" || exit 1
        shopt -s globstar nullglob
        while IFS= read -r pattern; do
            for f in $pattern; do
                [[ -f "$f" ]] && printf '%s\n' "$f"
            done
        done < <(scope_patterns) | sort -u
    )
}

# Every shell script git tracks.
tracked_shell_scripts() {
    (cd "${REPO_ROOT}" && git ls-files -- '*.sh' | sort -u)
}

@test ".shellcheck-scope exists and declares at least one pattern" {
    [ -f "${SCOPE}" ]
    run scope_patterns
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "no declared pattern contains whitespace" {
    # The workflow joins patterns with spaces into a single shellcheck-glob
    # input, and validate-pr word-splits it. A pattern with an embedded space
    # would silently split into two wrong patterns.
    run bash -c "sed 's/#.*//' '${SCOPE}' | grep -v '^[[:space:]]*$' | grep -n '[^[:space:]][[:space:]]\\+[^[:space:]]'"
    [ "$status" -ne 0 ]
}

@test "every declared pattern matches at least one file" {
    while IFS= read -r pattern; do
        run bash -c "cd '${REPO_ROOT}' && shopt -s globstar nullglob && files=($pattern) && echo \${#files[@]}"
        [ "$status" -eq 0 ]
        [ "$output" -gt 0 ] || {
            echo "stale pattern (matches nothing): ${pattern}"
            false
        }
    done < <(scope_patterns)
}

@test "every tracked *.sh file is covered by the declared scope" {
    uncovered="$(comm -23 <(tracked_shell_scripts) <(scope_matches))"
    if [ -n "${uncovered}" ]; then
        echo "shell scripts tracked by git but not covered by .shellcheck-scope:"
        echo "${uncovered}"
        false
    fi
}

@test "the credential-handling composite-action script is in scope" {
    # Regression guard for the specific gap #324 was filed for: this script is
    # invoked by .github/workflows/renovate.yml and inspects the Renovate PAT.
    run scope_matches
    [ "$status" -eq 0 ]
    [[ "$output" == *".github/actions/check-token-health/check_token_health.sh"* ]]
}

@test "the CI shellcheck-glob is still the known-narrow value (documents the open gap)" {
    # pr-validation.yml cannot be edited by this change: the hive GitHub App
    # has no `workflows` permission, so the CI half of #324 must be applied by
    # a maintainer. This test pins the current value so the follow-up is not
    # forgotten and so a *different* narrowing cannot slip in unnoticed.
    #
    # When a maintainer wires the workflow to .shellcheck-scope, replace this
    # test with the assertion in the block comment below.
    #
    #   run grep -n 'shellcheck-glob' "${WORKFLOW}"
    #   [ "$status" -eq 0 ]
    #   [[ "$output" == *'steps.shell-scope.outputs.glob'* ]]
    run grep -n 'shellcheck-glob:' "${WORKFLOW}"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"build/*.sh"'* || "$output" == *'steps.shell-scope.outputs.glob'* ]]
}

@test "Justfile:lint reads the manifest instead of walking the tree" {
    run grep -c '\.shellcheck-scope' "${JUSTFILE}"
    [ "$status" -eq 0 ]
    # The old implementation was `find . -iname "*.sh" -type f -exec shellcheck`.
    run grep -n 'find \. -iname "\*\.sh" -type f -exec shellcheck' "${JUSTFILE}"
    [ "$status" -ne 0 ]
}
