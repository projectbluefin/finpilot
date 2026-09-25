#!/usr/bin/env bats
#
# Unit tests for the root Justfile workspace-cleanup recipes: `clean`,
# `sudo-clean` and the `sudoif` privilege dispatcher they share.
#
# `clean` is the only recipe in the repository that runs `rm -rf` against the
# working tree, and `sudoif` is the only one that decides whether a command is
# escalated. Neither had ever been executed by a test, so the blast radius of
# `clean` (which top-level entries it deletes, and which it must leave alone)
# and the fail-closed behaviour of `sudoif` were unverified.
#
# Every recipe runs through the real `just` binary against a sandbox copy of
# the Justfile with `--working-directory` pointed at the sandbox, so the
# deletions only ever touch throwaway files. The fail-closed `sudoif` cases run
# with a PATH that deliberately contains no `sudo`; the whitespace argument test
# runs against a stub `sudo` that only records argv, so the escalating branches
# are exercised safely without ever gaining privileges.

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	SANDBOX="$(mktemp -d)"
	cp "${REPO_ROOT}/Justfile" "${SANDBOX}/Justfile"

	# A PATH that holds everything the recipes need except `sudo`, so the
	# "no sudo available" branch is reached on any host, including CI images
	# that do ship sudo.
	SUDOLESS_BIN="${SANDBOX}/sudoless-bin"
	mkdir -p "${SUDOLESS_BIN}"
	local tool resolved
	for tool in just bash sh find rm ls cat mktemp env grep sed; do
		resolved="$(command -v "${tool}" || true)"
		[[ -n "${resolved}" ]] && ln -sf "${resolved}" "${SUDOLESS_BIN}/${tool}"
	done
}

teardown() {
	rm -rf "${SANDBOX}"
}

run_recipe() {
	run just --justfile "${SANDBOX}/Justfile" --working-directory "${SANDBOX}" "$@"
}

# Same as run_recipe, but with a PATH from which `sudo` is absent.
run_recipe_without_sudo() {
	run env "PATH=${SUDOLESS_BIN}" \
		just --justfile "${SANDBOX}/Justfile" --working-directory "${SANDBOX}" "$@"
}

@test "clean: removes top-level entries whose name contains _build" {
	mkdir -p "${SANDBOX}/finpilot_build/layer"
	touch "${SANDBOX}/finpilot_build/layer/blob" \
		"${SANDBOX}/my_build.log" \
		"${SANDBOX}/_build"

	run_recipe clean
	[ "$status" -eq 0 ]

	[ ! -e "${SANDBOX}/finpilot_build" ]
	[ ! -e "${SANDBOX}/my_build.log" ]
	[ ! -e "${SANDBOX}/_build" ]
}

@test "clean: does not descend below the top level to find _build matches" {
	mkdir -p "${SANDBOX}/keepdir/nested_build"
	touch "${SANDBOX}/keepdir/nested_build/blob" \
		"${SANDBOX}/keepdir/inner_build.log"

	run_recipe clean
	[ "$status" -eq 0 ]

	[ -f "${SANDBOX}/keepdir/nested_build/blob" ]
	[ -f "${SANDBOX}/keepdir/inner_build.log" ]
}

@test "clean: removes output/ and everything under it" {
	mkdir -p "${SANDBOX}/output/qcow2"
	touch "${SANDBOX}/output/qcow2/disk.qcow2" "${SANDBOX}/output/manifest"

	run_recipe clean
	[ "$status" -eq 0 ]

	[ ! -e "${SANDBOX}/output" ]
}

@test "clean: leaves unrelated top-level files and directories alone" {
	mkdir -p "${SANDBOX}/build" "${SANDBOX}/custom"
	touch "${SANDBOX}/build/20-packages-and-services.sh" \
		"${SANDBOX}/custom/keep" \
		"${SANDBOX}/Containerfile" \
		"${SANDBOX}/README.md"

	run_recipe clean
	[ "$status" -eq 0 ]

	[ -f "${SANDBOX}/build/20-packages-and-services.sh" ]
	[ -f "${SANDBOX}/custom/keep" ]
	[ -f "${SANDBOX}/Containerfile" ]
	[ -f "${SANDBOX}/README.md" ]
	[ -f "${SANDBOX}/Justfile" ]
}

@test "clean: succeeds on an already-clean tree and is repeatable" {
	mkdir -p "${SANDBOX}/finpilot_build"

	run_recipe clean
	[ "$status" -eq 0 ]
	[ ! -e "${SANDBOX}/finpilot_build" ]

	run_recipe clean
	[ "$status" -eq 0 ]
	[ -f "${SANDBOX}/Justfile" ]
}

@test "clean: does not delete the working directory itself" {
	run_recipe clean
	[ "$status" -eq 0 ]
	[ -d "${SANDBOX}" ]
	[ -f "${SANDBOX}/Justfile" ]
}

@test "sudoif: fails closed when sudo is not available and the caller is not root" {
	if [[ "${UID}" -eq 0 ]]; then
		skip "root takes the direct-exec branch; this asserts the unprivileged path"
	fi

	printf '#!/usr/bin/env bash\ntouch %s/ran-marker\n' "${SANDBOX}" \
		>"${SUDOLESS_BIN}/escalated-command"
	chmod +x "${SUDOLESS_BIN}/escalated-command"

	run_recipe_without_sudo sudoif escalated-command
	[ "$status" -ne 0 ]

	# Refusing to escalate must mean refusing to run the command at all.
	[ ! -e "${SANDBOX}/ran-marker" ]
}

@test "sudo-clean: propagates the sudoif failure instead of cleaning unprivileged" {
	if [[ "${UID}" -eq 0 ]]; then
		skip "root takes the direct-exec branch; this asserts the unprivileged path"
	fi

	mkdir -p "${SANDBOX}/finpilot_build" "${SANDBOX}/output"
	touch "${SANDBOX}/finpilot_build/blob" "${SANDBOX}/output/manifest"

	run_recipe_without_sudo sudo-clean
	[ "$status" -ne 0 ]

	# The whole point of sudo-clean is that the removals happen as root; if
	# escalation is impossible nothing may be deleted as the calling user.
	[ -d "${SANDBOX}/finpilot_build" ]
	[ -d "${SANDBOX}/output" ]
}

@test "sudoif: reports the failure through just rather than exiting silently" {
	if [[ "${UID}" -eq 0 ]]; then
		skip "root takes the direct-exec branch; this asserts the unprivileged path"
	fi

	run_recipe_without_sudo sudoif ls
	[ "$status" -ne 0 ]
	[[ "$output" == *"sudoif"* ]]
}

@test "sudoif: passes whitespace-containing arguments through as single words" {
	# The dispatcher used to be invoked as `sudoif {{ command }} {{ args }}`,
	# which word-split every argument before the function saw it. Escalation
	# here goes through a stub `sudo` that only records its argv, so the test
	# exercises the invocation without ever gaining privileges.
	local stub_bin="${SANDBOX}/stub-bin"
	mkdir -p "${stub_bin}"
	ln -sf "${SUDOLESS_BIN}"/* "${stub_bin}/"

	printf '#!/usr/bin/env bash\nprintf "[%%s]\\n" "$@" >%s/argv\n' "${SANDBOX}" \
		>"${stub_bin}/sudo"
	chmod +x "${stub_bin}/sudo"

	run env -u SSH_ASKPASS -u DISPLAY -u WAYLAND_DISPLAY "PATH=${stub_bin}" \
		just --justfile "${SANDBOX}/Justfile" --working-directory "${SANDBOX}" \
		sudoif echo "hello world" plain
	[ "$status" -eq 0 ]

	if [[ "${UID}" -eq 0 ]]; then
		skip "root takes the direct-exec branch and never reaches the sudo stub"
	fi

	[ -f "${SANDBOX}/argv" ]
	run cat "${SANDBOX}/argv"
	[ "${lines[0]}" = "[echo]" ]
	[ "${lines[1]}" = "[hello world]" ]
	[ "${lines[2]}" = "[plain]" ]
	[ "${#lines[@]}" -eq 3 ]
}
