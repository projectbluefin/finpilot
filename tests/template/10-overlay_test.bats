#!/usr/bin/env bats
# Unit tests for build/10-overlay.sh.
#
# The script overlays the Common/Brew OCI payloads and writes the template's
# custom declarations under /usr/share and /etc/skel, so each test rewrites a
# throwaway copy to point at a sandbox root and stubs the binaries it shells
# out to (rsync, systemctl, curl). Production behaviour is never modified; the
# rewrite is asserted below so the suite fails loudly if the paths in the
# script ever drift.
#
# Run with: bats tests/template/10-overlay_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OVERLAY_SRC="${REPO_ROOT}/build/10-overlay.sh"

setup() {
	TEST_ROOT="${BATS_TEST_TMPDIR:-${BATS_TMPDIR}}/10-overlay.${BATS_TEST_NUMBER:-0}.$$"
	SANDBOX="${TEST_ROOT}/root"
	CTX="${SANDBOX}/ctx"
	STUB_BIN="${TEST_ROOT}/stub-bin"
	SCRIPT="${TEST_ROOT}/10-overlay.sh"

	RSYNC_LOG="${TEST_ROOT}/logs/rsync.log"
	SYSTEMCTL_LOG="${TEST_ROOT}/logs/systemctl.log"
	CURL_LOG="${TEST_ROOT}/logs/curl.log"

	HOMEBREW_DIR="${SANDBOX}/usr/share/ublue-os/homebrew"
	JUST_DIR="${SANDBOX}/usr/share/ublue-os/just"
	PREINSTALL_DIR="${SANDBOX}/usr/share/flatpak/preinstall.d"

	mkdir -p "${STUB_BIN}" "${TEST_ROOT}/logs"
	mkdir -p "${CTX}/oci/common/shared" "${CTX}/oci/brew"
	mkdir -p "${CTX}/custom/brew" "${CTX}/custom/ujust" "${CTX}/custom/flatpaks"

	# Representative build context contents.
	printf 'shared-payload\n' >"${CTX}/oci/common/shared/.keep"
	printf 'brew "tmux"\n' >"${CTX}/custom/brew/default.Brewfile"
	printf 'brew "gcc"\n' >"${CTX}/custom/brew/development.Brewfile"
	printf 'custom-apps-marker:\n\techo apps\n' >"${CTX}/custom/ujust/custom-apps.just"
	printf 'custom-system-marker:\n\techo system\n' >"${CTX}/custom/ujust/custom-system.just"
	printf '# not a just file\n' >"${CTX}/custom/ujust/README.md"
	printf 'org.mozilla.firefox\n' >"${CTX}/custom/flatpaks/default.preinstall"

	sed \
		-e "s#/ctx/#${CTX}/#g" \
		-e "s#/usr/share/#${SANDBOX}/usr/share/#g" \
		-e "s#/etc/skel#${SANDBOX}/etc/skel#g" \
		-e "s#/etc/flatpak#${SANDBOX}/etc/flatpak#g" \
		"${OVERLAY_SRC}" >"${SCRIPT}"

	export PATH="${STUB_BIN}:${PATH}"
	export RSYNC_LOG SYSTEMCTL_LOG CURL_LOG

	for tool in rsync systemctl curl; do
		local log_var
		log_var="$(printf '%s' "${tool}" | tr '[:lower:]' '[:upper:]')_LOG"
		cat >"${STUB_BIN}/${tool}" <<EOF
#!/usr/bin/bash
printf '%s\n' "\$*" >> "\${${log_var}}"
exit 0
EOF
		chmod +x "${STUB_BIN}/${tool}"
	done
}

teardown() {
	rm -rf "${TEST_ROOT}"
}

@test "10-overlay: sandbox rewrite left no writes to the host filesystem" {
	# Guards the rewrite above: if the script's paths change, the sed no longer
	# matches and every other test in this file would silently touch the host.
	run grep -nE '(^|[^-[:alnum:]])/ctx/|[^-[:alnum:]]/usr/share/|[^-[:alnum:]]/etc/skel' "${SCRIPT}"
	[ "$status" -ne 0 ]
}

@test "10-overlay: completes successfully against a populated sandbox context" {
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Overlay phase complete!"* ]]
}

@test "10-overlay: emits GitHub Actions group markers" {
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"::group:: Overlay shared Common runtime files"* ]]
	[[ "$output" == *"::group:: Overlay Brew integration files"* ]]
	[[ "$output" == *"::group:: Copy template custom declarations"* ]]
	[[ "$output" == *"::group:: Add the Flathub remote descriptor"* ]]
	[[ "$output" == *"::group:: Enable runtime services"* ]]
	[[ "$output" == *"::endgroup::"* ]]
}

@test "10-overlay: overlays the inherited layers first, then the template seams" {
	mkdir -p "${CTX}/custom/config"
	printf '[settings]\n' >"${CTX}/custom/config/example.conf"

	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]

	mapfile -t calls <"${RSYNC_LOG}"
	# Order is the contract: every step writes over the one above it, so the
	# template's own seams deliberately win over the inherited payloads.
	[ "${calls[0]}" = "-rvK ${CTX}/oci/common/shared/ /" ]
	[ "${calls[1]}" = "-rvK ${CTX}/oci/brew/ /" ]
	[[ "${calls[2]}" == *"${CTX}/custom/files/ /"* ]]
	[[ "${calls[3]}" == *"${CTX}/custom/config/ ${SANDBOX}/etc/skel/.config/"* ]]

	# bluefin/ is product opinion and nvidia/ is a paired hardware feature, so
	# neither is ever overlaid.
	! grep -q 'common/bluefin' "${RSYNC_LOG}"
	! grep -q 'nvidia' "${RSYNC_LOG}"
}

@test "10-overlay: custom/files mirrors the image root and drops its own README" {
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]

	mapfile -t calls <"${RSYNC_LOG}"
	# The override seam copies to the image root, so a payload can replace
	# anything the inherited layers wrote. Its own README must not ship.
	[[ "${calls[2]}" == *"${CTX}/custom/files/ /"* ]]
	[[ "${calls[2]}" == *"--exclude=/README.md"* ]]
}

@test "10-overlay: copies every Brewfile into the ublue-os homebrew dir" {
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]

	[ -f "${HOMEBREW_DIR}/default.Brewfile" ]
	[ -f "${HOMEBREW_DIR}/development.Brewfile" ]
	grep -q 'brew "tmux"' "${HOMEBREW_DIR}/default.Brewfile"
}

@test "10-overlay: consolidates only .just files into 60-custom.just" {
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]

	[ -f "${JUST_DIR}/60-custom.just" ]
	grep -q 'custom-apps-marker:' "${JUST_DIR}/60-custom.just"
	grep -q 'custom-system-marker:' "${JUST_DIR}/60-custom.just"
	! grep -q 'not a just file' "${JUST_DIR}/60-custom.just"
}

@test "10-overlay: consolidates just recipes from subdirectories" {
	# A fork may group recipes by topic. The merge walks the tree, so a nested
	# recipe must not be dropped silently.
	mkdir -p "${CTX}/custom/ujust/nested"
	printf 'nested-marker:\n\techo nested\n' >"${CTX}/custom/ujust/nested/deep.just"

	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]

	grep -q 'nested-marker:' "${JUST_DIR}/60-custom.just"
}

@test "10-overlay: consolidates just recipes in sorted, deterministic order" {
	printf 'zzz-marker:\n\techo z\n' >"${CTX}/custom/ujust/zzz-last.just"
	printf 'aaa-marker:\n\techo a\n' >"${CTX}/custom/ujust/aaa-first.just"

	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]
	first_content="$(cat "${JUST_DIR}/60-custom.just")"

	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]
	[ "$(cat "${JUST_DIR}/60-custom.just")" = "${first_content}" ]

	# aaa-first.just sorts before zzz-last.just, so its marker must appear first.
	first_line="$(grep 'marker:' "${JUST_DIR}/60-custom.just" | head -n1)"
	[[ "${first_line}" == *"aaa-marker"* ]]
}

@test "10-overlay: repeated runs do not accumulate the consolidated just file" {
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]
	count_one="$(grep -c 'custom-apps-marker:' "${JUST_DIR}/60-custom.just")"
	[ "${count_one}" -eq 1 ]

	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]
	count_two="$(grep -c 'custom-apps-marker:' "${JUST_DIR}/60-custom.just")"
	[ "${count_two}" -eq 1 ]
}

@test "10-overlay: separates consolidated just recipes with a blank line" {
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]

	# Without the separator the last line of one file and the first recipe of
	# the next would merge into a single unparseable line.
	run grep -c '^$' "${JUST_DIR}/60-custom.just"
	[ "$status" -eq 0 ]
	[ "$output" -ge 2 ]
}

@test "10-overlay: copies flatpak preinstall files into preinstall.d" {
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]

	[ -f "${PREINSTALL_DIR}/default.preinstall" ]
	grep -q 'org.mozilla.firefox' "${PREINSTALL_DIR}/default.preinstall"
}

@test "10-overlay: seeds /etc/skel/.config from custom/config when present" {
	mkdir -p "${CTX}/custom/config"
	printf '[settings]\n' >"${CTX}/custom/config/example.conf"
	printf '# seam docs\n' >"${CTX}/custom/config/README.md"

	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]

	# rsync is stubbed, so the copy is asserted from the log. Per-user defaults
	# land under .config rather than directly in the home skeleton, and the
	# seam's own README documents the seam instead of shipping into every new
	# user's home.
	mapfile -t calls <"${RSYNC_LOG}"
	[[ "${calls[3]}" == *"${CTX}/custom/config/ ${SANDBOX}/etc/skel/.config/"* ]]
	[[ "${calls[3]}" == *"--exclude=/README.md"* ]]
}

@test "10-overlay: a missing custom/config directory is not an error" {
	[ ! -d "${CTX}/custom/config" ]

	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]
	[ ! -d "${SANDBOX}/etc/skel" ]
}

@test "10-overlay: enables exactly the brew, flatpak, setup and podman units" {
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]

	mapfile -t calls <"${SYSTEMCTL_LOG}"
	[ "${#calls[@]}" -eq 9 ]
	[ "${calls[0]}" = "enable brew-setup.service" ]
	[ "${calls[1]}" = "enable brew-update.timer" ]
	[ "${calls[2]}" = "enable brew-upgrade.timer" ]
	[ "${calls[3]}" = "--global enable brew-preinstall.service" ]
	[ "${calls[4]}" = "enable flatpak-preinstall.service" ]
	[ "${calls[5]}" = "enable flatpak-appstream-refresh.service" ]
	[ "${calls[6]}" = "enable ublue-system-setup.service" ]
	[ "${calls[7]}" = "--global enable ublue-user-setup.service" ]
	[ "${calls[8]}" = "enable podman.socket" ]
}

@test "10-overlay: ships the Flathub remote descriptor" {
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]

	# flatpak imports remotes from this directory the first time it is used, so
	# the descriptor replaces both a unit and a build-time remote-add. It is
	# fetched rather than committed so Flathub's signing key stays current.
	mapfile -t calls <"${CURL_LOG}"
	[ "${#calls[@]}" -eq 1 ]
	[[ "${calls[0]}" == *"--output ${SANDBOX}/etc/flatpak/remotes.d/flathub.flatpakrepo"* ]]
	[[ "${calls[0]}" == *"https://dl.flathub.org/repo/flathub.flatpakrepo"* ]]
}

@test "10-overlay: an empty brew dir fails the build despite nullglob (regression guard)" {
	# nullglob makes the glob expand to nothing, which leaves cp with a single
	# argument — cp then fails with 'missing destination file operand'. See
	# issue #287: nullglob does not make these copies optional.
	rm -f "${CTX}"/custom/brew/*.Brewfile
	run bash "${SCRIPT}"
	[ "$status" -ne 0 ]
}

@test "10-overlay: an empty flatpaks dir fails the build despite nullglob (regression guard)" {
	rm -f "${CTX}"/custom/flatpaks/*.preinstall
	run bash "${SCRIPT}"
	[ "$status" -ne 0 ]
}

@test "10-overlay: an empty ujust dir still produces a consolidated just file" {
	rm -f "${CTX}"/custom/ujust/*
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]
	[ -f "${JUST_DIR}/60-custom.just" ]
}

@test "10-overlay: restores default glob behaviour before finishing" {
	cat >>"${SCRIPT}" <<'EOF'
shopt -q nullglob || echo "NULLGLOB_OFF"
EOF
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"NULLGLOB_OFF"* ]]
}
