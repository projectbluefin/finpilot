#!/usr/bin/env bats
# Unit tests for `_rootful_load_image` and the escalating branches of `sudoif`.
#
# Every disk recipe (`build-qcow2`, `build-raw`, `build-iso` and their rebuild
# variants) runs `_rootful_load_image` first. Bootc Image Builder runs under
# rootful podman, but `just build` leaves the image in the caller's rootless
# store, so this recipe decides whether to copy the image across with
# `podman image scp`, leave root's copy alone, or pull it from the registry.
# Getting that wrong builds a disk from a stale root-side image or from the
# published one instead of the image the developer just built.
#
# justfile-build-bib_test.bats runs inside a uid-0 user namespace, where this
# recipe exits on its first line, so none of those decisions ran. These cases
# run as an ordinary user with stub `podman` and `sudo` binaries on PATH: the
# `sudo` stub records its argv and re-execs the command with STUB_AS_ROOT=1, and
# the `podman` stub answers `images -q` differently for the user and root
# stores. Nothing is escalated and no container is touched.
#
# Run with: bats tests/template/justfile-rootful-load_test.bats

setup() {
	if ! command -v just &>/dev/null; then
		skip "just is not installed"
	fi
	if [[ "${UID}" -eq 0 ]]; then
		skip "root takes the direct-exec branches; these cases need an unprivileged caller"
	fi

	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	SANDBOX="$(mktemp -d)"
	STUB_BIN="${SANDBOX}/stub-bin"
	PODMAN_LOG="${SANDBOX}/podman.log"
	SUDO_LOG="${SANDBOX}/sudo.log"
	mkdir -p "${STUB_BIN}"
	cp "${REPO_ROOT}/Justfile" "${SANDBOX}/Justfile"
	: >"${PODMAN_LOG}"
	: >"${SUDO_LOG}"

	export PODMAN_LOG SUDO_LOG
	# Image IDs the two stores report, and whether the image exists locally.
	export STUB_USER_ID="sha256:user1111"
	export STUB_ROOT_ID="sha256:root2222"
	export STUB_INSPECT_STATUS=0
	export STUB_SCP_STATUS=0

	cat >"${STUB_BIN}/podman" <<'EOF'
#!/usr/bin/env bash
store=user
[[ -n "${STUB_AS_ROOT:-}" ]] && store=root
printf '%s: %s\n' "${store}" "$*" >>"${PODMAN_LOG}"
case "$1" in
	inspect) exit "${STUB_INSPECT_STATUS}" ;;
	images)
		if [[ "${store}" == root ]]; then
			printf '%s\n' "${STUB_ROOT_ID}"
		else
			printf '%s\n' "${STUB_USER_ID}"
		fi
		;;
	image)
		if [[ "$2" == scp ]]; then
			printf 'scp-tmpdir: %s exists=%s\n' "${TMPDIR:-}" "$([[ -d "${TMPDIR:-/nonexistent}" ]] && echo yes || echo no)" >>"${PODMAN_LOG}"
			exit "${STUB_SCP_STATUS}"
		fi
		;;
esac
exit 0
EOF

	cat >"${STUB_BIN}/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${SUDO_LOG}"
[[ "$1" == --askpass ]] && shift
exec env STUB_AS_ROOT=1 "$@"
EOF

	chmod +x "${STUB_BIN}"/*
	export PATH="${STUB_BIN}:${PATH}"
}

teardown() {
	[[ -n "${SANDBOX:-}" ]] && rm -rf "${SANDBOX}"
}

# Runs a recipe as the unprivileged caller with no ambient sudo or askpass
# state, so `_rootful_load_image` takes its non-root path and `sudoif` reaches
# the plain `sudo` branch unless a test opts in.
run_recipe() {
	run env -u SUDO_USER -u SSH_ASKPASS -u DISPLAY -u WAYLAND_DISPLAY "$@"
}

# Fails when the log records a line matching the pattern. A bare `! grep` does
# not fail a bats test unless it is the last command.
refute_logged() {
	if grep -q -- "$1" "$2"; then
		printf 'unexpected log entry matching %s in %s:\n' "$1" "$2" >&2
		cat "$2" >&2
		return 1
	fi
}

@test "_rootful_load_image: exits without touching podman when SUDO_USER is set" {
	run env SUDO_USER=someone \
		just --justfile "${SANDBOX}/Justfile" --working-directory "${SANDBOX}" \
		_rootful_load_image localhost/finpilot stable
	[ "$status" -eq 0 ]
	[[ "$output" == *"Already root or running under sudo"* ]]
	[ ! -s "${PODMAN_LOG}" ]
	[ ! -s "${SUDO_LOG}" ]
}

@test "_rootful_load_image: copies the user image to root when root holds a different ID" {
	run_recipe just --justfile "${SANDBOX}/Justfile" --working-directory "${SANDBOX}" \
		_rootful_load_image localhost/finpilot stable
	[ "$status" -eq 0 ]

	grep -qx 'user: inspect -t image localhost/finpilot:stable' "${PODMAN_LOG}"
	grep -qx 'root: images -q --filter reference=localhost/finpilot:stable' "${PODMAN_LOG}"
	grep -qx "root: image scp ${UID}@localhost::localhost/finpilot:stable root@localhost::localhost/finpilot:stable" "${PODMAN_LOG}"
	refute_logged ' pull ' "${PODMAN_LOG}"
}

@test "_rootful_load_image: escalates the scp with TMPDIR inside the repository" {
	run_recipe just --justfile "${SANDBOX}/Justfile" --working-directory "${SANDBOX}" \
		_rootful_load_image localhost/finpilot stable
	[ "$status" -eq 0 ]

	# The scp stages a full image export; /tmp is often a small tmpfs, so the
	# recipe points TMPDIR at a scratch directory beside the Justfile.
	grep -qE "^TMPDIR=${SANDBOX}/_build_podman_scp\.[A-Za-z0-9]+ podman image scp " "${SUDO_LOG}"
	grep -qE "^scp-tmpdir: ${SANDBOX}/_build_podman_scp\.[A-Za-z0-9]+ exists=yes$" "${PODMAN_LOG}"
}

@test "_rootful_load_image: removes its scp scratch directory after a successful copy" {
	run_recipe just --justfile "${SANDBOX}/Justfile" --working-directory "${SANDBOX}" \
		_rootful_load_image localhost/finpilot stable
	[ "$status" -eq 0 ]

	run compgen -G "${SANDBOX}/_build_podman_scp.*"
	[ "$status" -ne 0 ]
}

@test "_rootful_load_image: does not copy when root already holds the same image ID" {
	export STUB_ROOT_ID="${STUB_USER_ID}"
	run_recipe just --justfile "${SANDBOX}/Justfile" --working-directory "${SANDBOX}" \
		_rootful_load_image localhost/finpilot stable
	[ "$status" -eq 0 ]

	refute_logged 'image scp' "${PODMAN_LOG}"
	refute_logged ' pull ' "${PODMAN_LOG}"
	run compgen -G "${SANDBOX}/_build_podman_scp.*"
	[ "$status" -ne 0 ]
}

@test "_rootful_load_image: pulls into root when the image is not in the user store" {
	export STUB_INSPECT_STATUS=125
	run_recipe just --justfile "${SANDBOX}/Justfile" --working-directory "${SANDBOX}" \
		_rootful_load_image ghcr.io/projectbluefin/finpilot stable
	[ "$status" -eq 0 ]

	grep -qx 'root: pull ghcr.io/projectbluefin/finpilot:stable' "${PODMAN_LOG}"
	grep -qx 'podman pull ghcr.io/projectbluefin/finpilot:stable' "${SUDO_LOG}"
	refute_logged 'image scp' "${PODMAN_LOG}"
	refute_logged '^root: images' "${PODMAN_LOG}"
}

@test "_rootful_load_image: fails when the escalated scp fails" {
	export STUB_SCP_STATUS=1
	run_recipe just --justfile "${SANDBOX}/Justfile" --working-directory "${SANDBOX}" \
		_rootful_load_image localhost/finpilot stable
	[ "$status" -ne 0 ]
}

@test "_rootful_load_image: uses the IMAGE_NAME and DEFAULT_TAG defaults" {
	run_recipe IMAGE_NAME=myimage DEFAULT_TAG=testing \
		just --justfile "${SANDBOX}/Justfile" --working-directory "${SANDBOX}" \
		_rootful_load_image
	[ "$status" -eq 0 ]

	grep -qx 'user: inspect -t image myimage:testing' "${PODMAN_LOG}"
}

@test "sudoif: uses sudo --askpass when SSH_ASKPASS and DISPLAY are set" {
	run env -u SUDO_USER -u WAYLAND_DISPLAY SSH_ASKPASS=/usr/bin/ksshaskpass DISPLAY=:0 \
		just --justfile "${SANDBOX}/Justfile" --working-directory "${SANDBOX}" \
		sudoif true
	[ "$status" -eq 0 ]
	grep -qx -- '--askpass true' "${SUDO_LOG}"
}

@test "sudoif: uses sudo --askpass when SSH_ASKPASS and WAYLAND_DISPLAY are set" {
	run env -u SUDO_USER -u DISPLAY SSH_ASKPASS=/usr/bin/ksshaskpass WAYLAND_DISPLAY=wayland-0 \
		just --justfile "${SANDBOX}/Justfile" --working-directory "${SANDBOX}" \
		sudoif true
	[ "$status" -eq 0 ]
	grep -qx -- '--askpass true' "${SUDO_LOG}"
}

@test "sudoif: falls back to plain sudo when SSH_ASKPASS is set but no display is" {
	# A headless SSH session with an inherited SSH_ASKPASS has nowhere to show
	# the prompt; sudo must ask on the terminal instead.
	run env -u SUDO_USER -u DISPLAY -u WAYLAND_DISPLAY SSH_ASKPASS=/usr/bin/ksshaskpass \
		just --justfile "${SANDBOX}/Justfile" --working-directory "${SANDBOX}" \
		sudoif true
	[ "$status" -eq 0 ]
	grep -qx 'true' "${SUDO_LOG}"
}

@test "sudoif: uses plain sudo when a display is set but SSH_ASKPASS is not" {
	run env -u SUDO_USER -u SSH_ASKPASS -u WAYLAND_DISPLAY DISPLAY=:0 \
		just --justfile "${SANDBOX}/Justfile" --working-directory "${SANDBOX}" \
		sudoif true
	[ "$status" -eq 0 ]
	grep -qx 'true' "${SUDO_LOG}"
}

@test "sudoif: exits 1 when the escalated command fails" {
	run_recipe just --justfile "${SANDBOX}/Justfile" --working-directory "${SANDBOX}" \
		sudoif false
	[ "$status" -ne 0 ]
	grep -qx 'false' "${SUDO_LOG}"
}

@test "sudoif: exits 1 when the askpass-escalated command fails" {
	run env -u SUDO_USER -u WAYLAND_DISPLAY SSH_ASKPASS=/usr/bin/ksshaskpass DISPLAY=:0 \
		just --justfile "${SANDBOX}/Justfile" --working-directory "${SANDBOX}" \
		sudoif false
	[ "$status" -ne 0 ]
	grep -qx -- '--askpass false' "${SUDO_LOG}"
}
