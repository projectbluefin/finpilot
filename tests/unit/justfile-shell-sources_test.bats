#!/usr/bin/env bats
# Unit tests for the private `shell-sources` recipe and its only consumer,
# `lint`, in the root Justfile.
#
# `.shellcheck-scope` is the single source of truth for "which shell scripts
# this repo lints" (see #324). tests/unit/shellcheck-scope_test.bats asserts on
# the *content* of that manifest, but it re-implements the expansion inline and
# never executes the recipe, so the recipe's own parsing rules — comment
# stripping, whitespace trimming, nullglob/globstar expansion, the missing-file
# guard, and the empty-scope guard in `lint` — have no coverage at all. A
# regression in that parser silently narrows what CI shellchecks.
#
# The recipes are exercised against a sandbox copy of the Justfile with a
# synthetic .shellcheck-scope, so the real repository is never read or linted,
# and `shellcheck` is replaced by a stub on PATH that records its argv.
#
# Run with: bats tests/unit/justfile-shell-sources_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."

setup() {
    if ! command -v just &>/dev/null; then
        skip "just is not installed"
    fi

    TEST_ROOT="${BATS_TEST_TMPDIR:-${BATS_TMPDIR}}/shell-sources.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/stub-bin"
    SANDBOX="${TEST_ROOT}/repo"
    SHELLCHECK_LOG="${TEST_ROOT}/logs/shellcheck.log"

    mkdir -p "${STUB_BIN}" "${TEST_ROOT}/logs" "${SANDBOX}"
    cp "${REPO_ROOT}/Justfile" "${SANDBOX}/Justfile"

    cat >"${STUB_BIN}/shellcheck" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${SHELLCHECK_LOG}"
exit "${STUB_SHELLCHECK_STATUS:-0}"
EOF
    chmod +x "${STUB_BIN}/shellcheck"

    export PATH="${STUB_BIN}:${PATH}"
    export SHELLCHECK_LOG
}

# Write the sandbox manifest verbatim from stdin.
write_scope() {
    cat >"${SANDBOX}/.shellcheck-scope"
}

# Create empty shell scripts (parents included) inside the sandbox.
make_scripts() {
    local path
    for path in "$@"; do
        mkdir -p "${SANDBOX}/$(dirname "${path}")"
        : >"${SANDBOX}/${path}"
    done
}

# Run a recipe in the sandbox. stdout lands in $output/$lines as usual;
# stderr is captured separately in $stderr so the two can be asserted apart.
run_just() {
    local err_log="${TEST_ROOT}/stderr.log"
    : >"${err_log}"
    run bash -c "cd '${SANDBOX}' && just $* 2>'${err_log}'"
    stderr="$(cat "${err_log}")"
}

@test "shell-sources expands declared globs into the matching files" {
    make_scripts a.sh nested/b.sh nested/deep/c.sh
    write_scope <<'EOF'
a.sh
nested/**/*.sh
EOF

    run_just shell-sources

    [ "$status" -eq 0 ]
    [[ "$output" == *"a.sh"* ]]
    [[ "$output" == *"nested/b.sh"* ]]
    [[ "$output" == *"nested/deep/c.sh"* ]]
}

@test "shell-sources emits one path per line so lint can mapfile it" {
    make_scripts a.sh nested/b.sh
    write_scope <<'EOF'
a.sh
nested/b.sh
EOF

    run_just shell-sources

    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[0]}" = "a.sh" ]
    [ "${lines[1]}" = "nested/b.sh" ]
}

@test "shell-sources strips whole-line comments, inline comments and blank lines" {
    make_scripts a.sh b.sh
    write_scope <<'EOF'
# the credential-handling script lives here
a.sh

b.sh # trailing comment
EOF

    run_just shell-sources

    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[0]}" = "a.sh" ]
    [ "${lines[1]}" = "b.sh" ]
}

@test "shell-sources trims leading and trailing whitespace from a pattern" {
    make_scripts a.sh
    write_scope <<'EOF'
   a.sh	
EOF

    run_just shell-sources

    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "a.sh" ]
}

@test "shell-sources reads a final pattern that has no trailing newline" {
    make_scripts a.sh b.sh
    printf 'a.sh\nb.sh' >"${SANDBOX}/.shellcheck-scope"

    run_just shell-sources

    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[1]}" = "b.sh" ]
}

@test "shell-sources drops patterns that match nothing instead of emitting the glob" {
    make_scripts a.sh
    write_scope <<'EOF'
a.sh
does/not/exist/*.sh
EOF

    run_just shell-sources

    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [ "${lines[0]}" = "a.sh" ]
    [[ "$output" != *"does/not/exist"* ]]
}

@test "shell-sources does not deduplicate paths matched by two patterns" {
    # lint passes the list straight to shellcheck; a duplicate is harmless but
    # is part of the contract the drift gate in shellcheck-scope_test.bats
    # assumes, so pin it.
    make_scripts a.sh
    write_scope <<'EOF'
a.sh
*.sh
EOF

    run_just shell-sources

    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[0]}" = "a.sh" ]
    [ "${lines[1]}" = "a.sh" ]
}

@test "shell-sources fails with a diagnostic when the manifest is missing" {
    make_scripts a.sh
    rm -f "${SANDBOX}/.shellcheck-scope"

    run_just shell-sources

    [ "$status" -ne 0 ]
    [[ "$stderr" == *".shellcheck-scope is missing"* ]]
}

@test "shell-sources emits nothing for a manifest of only comments" {
    make_scripts a.sh
    write_scope <<'EOF'
# nothing declared yet
EOF

    run_just shell-sources

    [ -z "$output" ]
}

@test "BUG: shell-sources exits non-zero when a glob matches a non-regular file" {
    # `[[ -f "$f" ]] && printf ...` is the last command in the loop body, so
    # when the final expansion ends on a match that is not a regular file (a
    # directory named *.sh, a dangling symlink) the while loop — the last
    # command in the recipe — carries status 1 and, under `set -euo pipefail`,
    # the recipe reports failure even though it printed the complete list.
    # This pins the current behaviour; it must be updated when the recipe stops
    # leaking the test result (e.g. an explicit `continue` or `|| true`).
    make_scripts a.sh late.sh
    mkdir -p "${SANDBOX}/zz.sh"
    write_scope <<'EOF'
*.sh
EOF

    run_just shell-sources

    [ "$status" -ne 0 ]
    # The list itself is complete — only the exit status is wrong.
    [ "${lines[0]}" = "a.sh" ]
    [ "${lines[1]}" = "late.sh" ]
}

@test "BUG: lint masks the shell-sources failure instead of failing closed" {
    # lint reads the recipe through `mapfile -t sources < <(just shell-sources)`,
    # which discards the process substitution's status. Today that accidentally
    # hides the bug above; it would equally hide a genuinely truncated list, so
    # a fix should propagate the failure rather than keep swallowing it.
    make_scripts a.sh late.sh
    mkdir -p "${SANDBOX}/zz.sh"
    write_scope <<'EOF'
*.sh
EOF

    run_just lint

    [ "$status" -eq 0 ]
    run cat "${SHELLCHECK_LOG}"
    [ "$output" = "a.sh late.sh" ]
}

@test "lint passes exactly the manifest sources to shellcheck" {
    make_scripts a.sh nested/b.sh
    write_scope <<'EOF'
a.sh
nested/b.sh
EOF

    run_just lint

    [ "$status" -eq 0 ]
    run cat "${SHELLCHECK_LOG}"
    [ "$output" = "a.sh nested/b.sh" ]
}

@test "lint fails when the manifest matches no shell script" {
    write_scope <<'EOF'
# every pattern was removed
EOF

    run_just lint

    [ "$status" -ne 0 ]
    [[ "$stderr" == *"No shell scripts matched .shellcheck-scope"* ]]
    [ ! -f "${SHELLCHECK_LOG}" ]
}

@test "lint propagates a shellcheck failure" {
    make_scripts a.sh
    write_scope <<'EOF'
a.sh
EOF
    export STUB_SHELLCHECK_STATUS=1

    run_just lint

    [ "$status" -ne 0 ]
}

@test "lint aborts with a diagnostic when shellcheck is not installed" {
    make_scripts a.sh
    write_scope <<'EOF'
a.sh
EOF
    rm -f "${STUB_BIN}/shellcheck"

    run_just lint

    [ "$status" -ne 0 ]
    [[ "$output" == *"shellcheck could not be found"* ]]
}
