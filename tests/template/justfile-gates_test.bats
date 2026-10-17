#!/usr/bin/env bats
#
# Unit tests for the root Justfile recipes that are themselves gates:
#
#   check / fix / _format-justfiles   the `validate-justfiles.yml` status check
#   _bats (via test-contract, test-template, test-unit)
#                                     the runner behind `unit-tests.yml`
#   shell-sources / lint / format     the shellcheck and shfmt scope
#
# CI only ever runs these against the committed tree, which passes, so their
# failure branches never execute. A regression that made `check` rewrite files
# instead of reporting drift, or made `_bats` exit 0 when it found no tests,
# would turn a required check green without anyone noticing.
#
# Every recipe runs through the real `just` binary against a sandbox copy of
# the Justfile in a scratch git repository. shellcheck, shfmt and bats are
# replaced by stubs that record their argv, and "tool missing" cases run with a
# PATH that holds only the tools the recipes need, so results do not depend on
# what the host has installed.

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	SANDBOX="$(mktemp -d)"
	cp "${REPO_ROOT}/Justfile" "${SANDBOX}/Justfile"

	# Keep the scratch repository independent of the host's git config.
	export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
	git -C "${SANDBOX}" init -q

	# A PATH with the base tools the recipes use and none of the tools under
	# test, so each test opts in to exactly the stubs it wants.
	BASE_BIN="${SANDBOX}/.base-bin"
	mkdir -p "${BASE_BIN}"
	local tool resolved
	for tool in just sh bash env find sort git cat mktemp rm; do
		resolved="$(command -v "${tool}" || true)"
		[[ -n "${resolved}" ]] && ln -sf "${resolved}" "${BASE_BIN}/${tool}"
	done
	STUB_BIN="${SANDBOX}/.stub-bin"
	mkdir -p "${STUB_BIN}"
}

teardown() {
	rm -rf "${SANDBOX}"
}

run_recipe() {
	run env "PATH=${STUB_BIN}:${BASE_BIN}" \
		just --justfile "${SANDBOX}/Justfile" --working-directory "${SANDBOX}" "$@"
}

# A stub that appends one "[arg]" line per argument to <name>.argv and exits
# with the given status.
make_stub() {
	local name="$1" status="${2:-0}"
	cat >"${STUB_BIN}/${name}" <<EOF
#!/usr/bin/env bash
printf '[%s]\n' "\$@" >>"${SANDBOX}/${name}.argv"
exit ${status}
EOF
	chmod +x "${STUB_BIN}/${name}"
}

track() {
	local path
	for path in "$@"; do
		mkdir -p "$(dirname "${SANDBOX}/${path}")"
		printf '#!/usr/bin/env bash\ntrue\n' >"${SANDBOX}/${path}"
	done
	git -C "${SANDBOX}" add -- "$@"
}

FORMATTED_JUST=$'hello:\n    echo hello\n'
DRIFTED_JUST=$'hello:\n        echo hello\n'

# --- check / fix -----------------------------------------------------------

@test "check: passes on the committed Justfile and every committed .just file" {
	run just --justfile "${REPO_ROOT}/Justfile" --working-directory "${REPO_ROOT}" check
	[ "$status" -eq 0 ]
	[[ "$output" == *"Checking syntax: Justfile"* ]]
	[[ "$output" == *"custom-apps.just"* ]]
	[[ "$output" == *"custom-system.just"* ]]
}

@test "check: fails on a drifted .just file and names it" {
	mkdir -p "${SANDBOX}/custom/ujust"
	printf '%s' "${FORMATTED_JUST}" >"${SANDBOX}/custom/ujust/good.just"
	printf '%s' "${DRIFTED_JUST}" >"${SANDBOX}/custom/ujust/bad.just"

	run_recipe check
	[ "$status" -ne 0 ]
	[[ "$output" == *"Checking syntax: ./custom/ujust/bad.just"* ]]
}

@test "check: reports drift without rewriting the file" {
	mkdir -p "${SANDBOX}/custom/ujust"
	printf '%s' "${DRIFTED_JUST}" >"${SANDBOX}/custom/ujust/bad.just"

	run_recipe check
	[ "$status" -ne 0 ]
	[ "$(cat "${SANDBOX}/custom/ujust/bad.just")" = "${DRIFTED_JUST%$'\n'}" ]
}

@test "check: finds .just files below the top level" {
	mkdir -p "${SANDBOX}/a/b/c"
	printf '%s' "${DRIFTED_JUST}" >"${SANDBOX}/a/b/c/deep.just"

	run_recipe check
	[ "$status" -ne 0 ]
	[[ "$output" == *"./a/b/c/deep.just"* ]]
}

@test "check: fails when the root Justfile itself has drifted" {
	printf '\n\n\n' >>"${SANDBOX}/Justfile"

	run_recipe check
	[ "$status" -ne 0 ]
}

@test "check: a .just file with a space in its path is checked as one file" {
	mkdir -p "${SANDBOX}/with space"
	printf '%s' "${FORMATTED_JUST}" >"${SANDBOX}/with space/ok.just"

	run_recipe check
	[ "$status" -eq 0 ]
	[[ "$output" == *"Checking syntax: ./with space/ok.just"* ]]
}

@test "fix: rewrites a drifted .just file so check then passes" {
	mkdir -p "${SANDBOX}/custom/ujust"
	printf '%s' "${DRIFTED_JUST}" >"${SANDBOX}/custom/ujust/bad.just"

	run_recipe fix
	[ "$status" -eq 0 ]
	[ "$(cat "${SANDBOX}/custom/ujust/bad.just")" = "${FORMATTED_JUST%$'\n'}" ]

	run_recipe check
	[ "$status" -eq 0 ]
}

# --- _bats and the suites that call it ----------------------------------------

@test "_bats: fails closed when bats is not installed" {
	mkdir -p "${SANDBOX}/tests"
	touch "${SANDBOX}/tests/a_test.bats"

	run_recipe _bats tests
	[ "$status" -ne 0 ]
	[[ "$output" == *"bats not found"* ]]
}

@test "_bats: fails when the directory holds no *_test.bats files" {
	make_stub bats
	mkdir -p "${SANDBOX}/tests"
	touch "${SANDBOX}/tests/helper.bash" "${SANDBOX}/tests/notes_test.bats.bak"

	run_recipe _bats tests
	[ "$status" -ne 0 ]
	[[ "$output" == *"No *_test.bats files found under tests"* ]]
	[ ! -e "${SANDBOX}/bats.argv" ]
}

@test "_bats: passes every *_test.bats file, recursively and sorted, to bats" {
	make_stub bats
	mkdir -p "${SANDBOX}/tests/template" "${SANDBOX}/tests/contract"
	touch "${SANDBOX}/tests/template/z_test.bats" \
		"${SANDBOX}/tests/contract/a_test.bats" \
		"${SANDBOX}/tests/template/helper.bash"

	run_recipe _bats tests
	[ "$status" -eq 0 ]
	[[ "$output" == *"Running 2 test files..."* ]]

	run cat "${SANDBOX}/bats.argv"
	[ "${lines[0]}" = "[--print-output-on-failure]" ]
	[ "${lines[1]}" = "[tests/contract/a_test.bats]" ]
	[ "${lines[2]}" = "[tests/template/z_test.bats]" ]
	[ "${#lines[@]}" -eq 3 ]
}

@test "_bats: propagates a failing bats run" {
	make_stub bats 1
	mkdir -p "${SANDBOX}/tests"
	touch "${SANDBOX}/tests/a_test.bats"

	run_recipe _bats tests
	[ "$status" -ne 0 ]
}

@test "test-contract, test-template and test-unit each scope _bats to their directory" {
	make_stub bats
	mkdir -p "${SANDBOX}/tests/contract" "${SANDBOX}/tests/template"
	touch "${SANDBOX}/tests/contract/c_test.bats" "${SANDBOX}/tests/template/t_test.bats"

	run_recipe test-contract
	[ "$status" -eq 0 ]
	run_recipe test-template
	[ "$status" -eq 0 ]
	run_recipe test-unit
	[ "$status" -eq 0 ]

	run cat "${SANDBOX}/bats.argv"
	[ "${lines[1]}" = "[tests/contract/c_test.bats]" ]
	[ "${lines[3]}" = "[tests/template/t_test.bats]" ]
	[ "${lines[5]}" = "[tests/contract/c_test.bats]" ]
	[ "${lines[6]}" = "[tests/template/t_test.bats]" ]
	[ "${#lines[@]}" -eq 7 ]
}

@test "test-template fails when a fork deletes tests/template" {
	make_stub bats
	mkdir -p "${SANDBOX}/tests/contract"
	touch "${SANDBOX}/tests/contract/c_test.bats"

	run_recipe test-template
	[ "$status" -ne 0 ]
}

# --- shell-sources / lint / format -----------------------------------------------

@test "shell-sources: lists tracked *.sh files only" {
	track build/10-overlay.sh "dir with space/x.sh"
	printf 'x\n' >"${SANDBOX}/untracked.sh"
	printf 'x\n' >"${SANDBOX}/build/30-tailscale.sh.example"
	git -C "${SANDBOX}" add build/30-tailscale.sh.example

	run_recipe shell-sources
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "build/10-overlay.sh" ]
	[ "${lines[1]}" = "dir with space/x.sh" ]
	[ "${#lines[@]}" -eq 2 ]
}

@test "lint: fails closed when shellcheck is not installed" {
	track build/10-overlay.sh

	run_recipe lint
	[ "$status" -ne 0 ]
	[[ "$output" == *"shellcheck could not be found"* ]]
}

@test "lint: fails when git tracks no *.sh files" {
	make_stub shellcheck
	printf 'x\n' >"${SANDBOX}/untracked.sh"

	run_recipe lint
	[ "$status" -ne 0 ]
	[[ "$output" == *"No shell scripts found"* ]]
	[ ! -e "${SANDBOX}/shellcheck.argv" ]
}

@test "lint: fails outside a git work tree instead of linting nothing" {
	make_stub shellcheck
	rm -rf "${SANDBOX}/.git"
	printf 'x\n' >"${SANDBOX}/a.sh"

	run_recipe lint
	[ "$status" -ne 0 ]
	[ ! -e "${SANDBOX}/shellcheck.argv" ]
}

@test "lint: hands shellcheck exactly the shell-sources list, one argument per path" {
	make_stub shellcheck
	track build/10-overlay.sh "dir with space/x.sh"

	run_recipe lint
	[ "$status" -eq 0 ]
	[[ "$output" == *"Shellchecking 2 scripts:"* ]]

	run cat "${SANDBOX}/shellcheck.argv"
	[ "${lines[0]}" = "[build/10-overlay.sh]" ]
	[ "${lines[1]}" = "[dir with space/x.sh]" ]
	[ "${#lines[@]}" -eq 2 ]
}

@test "lint: propagates shellcheck findings" {
	make_stub shellcheck 1
	track build/10-overlay.sh

	run_recipe lint
	[ "$status" -ne 0 ]
}

@test "format: fails closed when shfmt is not installed" {
	track build/10-overlay.sh

	run_recipe format
	[ "$status" -ne 0 ]
	[[ "$output" == *"shfmt could not be found"* ]]
}

@test "format: fails when git tracks no *.sh files" {
	make_stub shfmt

	run_recipe format
	[ "$status" -ne 0 ]
	[[ "$output" == *"No shell scripts found"* ]]
	[ ! -e "${SANDBOX}/shfmt.argv" ]
}

@test "format: runs shfmt --write over the same list lint checks" {
	make_stub shfmt
	make_stub shellcheck
	track build/10-overlay.sh "dir with space/x.sh"

	run_recipe format
	[ "$status" -eq 0 ]
	run_recipe lint
	[ "$status" -eq 0 ]

	run cat "${SANDBOX}/shfmt.argv"
	[ "${lines[0]}" = "[--write]" ]
	[ "${lines[1]}" = "[build/10-overlay.sh]" ]
	[ "${lines[2]}" = "[dir with space/x.sh]" ]
	[ "${#lines[@]}" -eq 3 ]
	[ "$(tail -n 2 "${SANDBOX}/shfmt.argv")" = "$(cat "${SANDBOX}/shellcheck.argv")" ]
}

@test "format: propagates an shfmt failure" {
	make_stub shfmt 1
	track build/10-overlay.sh

	run_recipe format
	[ "$status" -ne 0 ]
}
