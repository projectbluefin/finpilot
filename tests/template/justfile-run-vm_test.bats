#!/usr/bin/env bats
#
# Execution tests for the root Justfile's VM launchers: `_run-vm` (reached
# through `run-vm-qcow2`, `run-vm-raw` and `run-vm-iso`), its containerised
# fallback `_run-vm-container`, and `spawn-vm`.
#
# justfile-vm-artifact_test.bats only reads these recipes as text. Nothing ran
# them, so the decisions they make before a VM boots went unchecked: building a
# missing artifact with the caller's image and tag, falling back to the qemus
# container when the host has no QEMU, giving the ISO a scratch install target
# while disk images boot in place, never letting the container write to a built
# disk (-snapshot), stepping past a taken ssh or console port, and refusing what
# systemd-vmspawn cannot boot.
#
# Every external command is a stub on a PATH that holds nothing else, so the
# tests control whether QEMU exists and assert on the argument vectors podman,
# qemu-system-x86_64, qemu-img and systemd-vmspawn would have received. Nested
# `just build-<type>` calls are intercepted and stand in for a Bootc Image
# Builder run by creating the artifact.
#
# Two inputs are absolute paths the recipes hardcode: the OVMF firmware under
# /usr/share and /dev/kvm. Cases that need them present run `just` inside an
# `unshare -rm` user and mount namespace with a tmpfs over those paths; hosts
# without unprivileged user namespaces (GitHub's ubuntu-latest among them) skip
# those cases. Cases that need them absent skip on a host that has them.

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	REAL_JUST="$(command -v just)" || skip "just is not installed"
	REAL_SLEEP="$(command -v sleep)"
	HOST_PATH="${PATH}"
	NS_UNSHARE="$(PATH="${PATH}:/usr/sbin:/sbin" command -v unshare || true)"
	NS_MOUNT="$(PATH="${PATH}:/usr/sbin:/sbin" command -v mount || true)"

	TEST_ROOT="$(mktemp -d)"
	TEST_ROOT="$(realpath "${TEST_ROOT}")"
	SANDBOX="${TEST_ROOT}/repo"
	STUB_BIN="${TEST_ROOT}/stub-bin"
	TOOLS="${TEST_ROOT}/tools"
	LOGS="${TEST_ROOT}/logs"
	mkdir -p "${SANDBOX}" "${STUB_BIN}" "${TOOLS}" "${LOGS}"
	cp "${REPO_ROOT}/Justfile" "${SANDBOX}/Justfile"

	# Only the tools the recipes need, so a QEMU or vmspawn on the host cannot
	# leak into a case that expects it to be missing.
	local tool path
	for tool in bash sh env grep sed head tail wc mkdir cp rm chmod mktemp realpath cat dirname touch; do
		path="$(command -v "${tool}")" || skip "${tool} is not installed"
		ln -s "${path}" "${TOOLS}/${tool}"
	done

	export REAL_JUST LOGS
	export VM_RAM=4096 VM_CPUS=3
	export SS_BUSY_PORTS="" STUB_PODMAN_STATUS=0
	unset DISPLAY WAYLAND_DISPLAY QEMU_IMAGE

	stub just <<'EOF'
#!/usr/bin/env bash
# A nested build stands in for Bootc Image Builder: record it and create the
# artifact where vm-artifact says the recipe will look.
if [[ "$1" == build-* ]]; then
	printf '%s\n' "$*" >>"${LOGS}/build.log"
	artifact="$("${REAL_JUST}" vm-artifact "${1#build-}")"
	mkdir -p "$(dirname "${artifact}")"
	: >"${artifact}"
	exit 0
fi
exec "${REAL_JUST}" "$@"
EOF
	stub ss <<'EOF'
#!/usr/bin/env bash
for port in ${SS_BUSY_PORTS}; do
	printf 'tcp LISTEN 0 4096 127.0.0.1:%s 0.0.0.0:* users:(("stub",pid=1,fd=3))\n' "${port}"
done
EOF
	stub podman <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"${LOGS}/podman.args"
exit "${STUB_PODMAN_STATUS}"
EOF
	stub sleep <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
	stub xdg-open <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${LOGS}/xdg-open.log"
EOF
	stub qemu-img <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${LOGS}/qemu-img.log"
[[ "$1" == create ]] && : >"${@: -2:1}"
exit 0
EOF
	stub qemu-system-x86_64 <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"${LOGS}/qemu.args"
# Record the UEFI vars file as QEMU would see it: it must exist, be writable
# and hold the firmware's template.
for arg in "$@"; do
	if [[ "${arg}" == if=pflash,format=raw,file=* ]]; then
		vars="${arg#*file=}"
		printf '%s\n' "${vars}" >"${LOGS}/vars.path"
		[[ -w "${vars}" ]] && cat "${vars}" >"${LOGS}/vars.content"
	fi
done
exit 0
EOF
	stub systemd-vmspawn <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"${LOGS}/vmspawn.args"
EOF

	export PATH="${STUB_BIN}:${TOOLS}"
}

teardown() {
	export PATH="${HOST_PATH}"
	rm -rf "${TEST_ROOT}"
}

# Write a stub executable from stdin.
stub() {
	cat >"${STUB_BIN}/$1"
	chmod +x "${STUB_BIN}/$1"
}

# Remove a stub so the command is missing from PATH entirely.
unstub() {
	rm -f "${STUB_BIN}/$1"
}

run_recipe() {
	run just --justfile "${SANDBOX}/Justfile" --working-directory "${SANDBOX}" "$@"
}

make_artifact() {
	mkdir -p "${SANDBOX}/$(dirname "$1")"
	: >"${SANDBOX}/$1"
}

# The line after `$2` in an argument log: the value of a flag.
arg_after() {
	grep -A1 -Fx -- "$2" "$1" | tail -n1
}

ns_or_skip() {
	[[ -n "${NS_UNSHARE}" ]] || skip "unshare is not installed"
	[[ -n "${NS_MOUNT}" ]] || skip "mount is not installed"
	"${NS_UNSHARE}" -rm "${BASH}" -c : 2>/dev/null || skip "unprivileged user namespaces are unavailable"
}

# Run a recipe in a user and mount namespace after the shell snippet $NS_PREP
# has rearranged the hardcoded paths.
run_recipe_ns() {
	run "${NS_UNSHARE}" -rm "${BASH}" -c '
		set -e
		eval "${NS_PREP}"
		exec just --justfile "$0" --working-directory "${0%/Justfile}" "$@"
	' "${SANDBOX}/Justfile" "$@"
}

# Replace /usr/share with a tmpfs holding only the given OVMF files, each
# containing its own name.
with_ovmf() {
	ns_or_skip
	local prep="'${NS_MOUNT}' -t tmpfs tmpfs /usr/share;"
	local f
	for f in "$@"; do
		prep+=" mkdir -p '$(dirname "${f}")'; printf '%s' '${f}' >'${f}';"
	done
	export NS_PREP="${prep}" NS_MOUNT
}

# Replace /dev with a tmpfs holding /dev/null and a writable /dev/kvm.
with_writable_kvm() {
	ns_or_skip
	mkdir -p "${TEST_ROOT}/dev"
	: >"${TEST_ROOT}/dev/null"
	: >"${TEST_ROOT}/dev/kvm"
	export NS_PREP="'${NS_MOUNT}' --bind /dev/null '${TEST_ROOT}/dev/null'; '${NS_MOUNT}' --rbind '${TEST_ROOT}/dev' /dev;" NS_MOUNT
}

host_has_ovmf() {
	local f
	for f in /usr/share/edk2/ovmf/OVMF_CODE.fd /usr/share/OVMF/OVMF_CODE.fd \
		/usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/edk2/x64/OVMF_CODE.4m.fd \
		/usr/share/qemu/OVMF_CODE.fd; do
		[[ -f "${f}" ]] && return 0
	done
	return 1
}

# --- _run-vm-container --------------------------------------------------------

@test "_run-vm-container: a missing artifact fails before podman runs" {
	run_recipe _run-vm-container qcow2 output/qcow2/disk.qcow2
	[ "$status" -eq 1 ]
	[[ "$output" == *"ERROR: output/qcow2/disk.qcow2 not found — run: just build-qcow2"* ]]
	[ ! -e "${LOGS}/podman.args" ]
}

@test "_run-vm-container: qcow2 mounts at /boot.qcow2 and boots with -snapshot" {
	make_artifact output/qcow2/disk.qcow2
	run_recipe _run-vm-container qcow2 output/qcow2/disk.qcow2
	[ "$status" -eq 0 ]
	args="${LOGS}/podman.args"
	[ "$(head -n1 "${args}")" = "run" ]
	grep -Fxq -- "--rm" "${args}"
	grep -Fxq -- "--privileged" "${args}"
	[ "$(arg_after "${args}" --device=/dev/kvm)" = "--publish" ]
	grep -Fxq "ARGUMENTS=-snapshot" "${args}"
	grep -Fxq "${SANDBOX}/output/qcow2/disk.qcow2:/boot.qcow2" "${args}"
	grep -Fxq "BOOT_MODE=uefi" "${args}"
}

@test "_run-vm-container: raw mounts at /boot.img and boots with -snapshot" {
	make_artifact output/image/disk.raw
	run_recipe _run-vm-container raw output/image/disk.raw
	[ "$status" -eq 0 ]
	grep -Fxq "${SANDBOX}/output/image/disk.raw:/boot.img" "${LOGS}/podman.args"
	grep -Fxq "ARGUMENTS=-snapshot" "${LOGS}/podman.args"
}

@test "_run-vm-container: the ISO mounts at /boot.iso without -snapshot, so the install persists" {
	make_artifact output/bootiso/install.iso
	run_recipe _run-vm-container iso output/bootiso/install.iso
	[ "$status" -eq 0 ]
	grep -Fxq "${SANDBOX}/output/bootiso/install.iso:/boot.iso" "${LOGS}/podman.args"
	! grep -q "^ARGUMENTS=" "${LOGS}/podman.args"
}

@test "_run-vm-container: VM_CPUS and VM_RAM size the guest, and the qemus image is the last argument" {
	make_artifact output/qcow2/disk.qcow2
	run_recipe _run-vm-container qcow2 output/qcow2/disk.qcow2
	[ "$status" -eq 0 ]
	grep -Fxq "CPU_CORES=3" "${LOGS}/podman.args"
	grep -Fxq "RAM_SIZE=4096M" "${LOGS}/podman.args"
	pinned="$(sed -nE 's/^export qemu_image := env\("QEMU_IMAGE", "([^"]+)"\)$/\1/p' "${SANDBOX}/Justfile")"
	[ -n "${pinned}" ]
	[ "$(tail -n1 "${LOGS}/podman.args")" = "${pinned}" ]
}

@test "_run-vm-container: QEMU_IMAGE overrides the pinned qemus image" {
	make_artifact output/qcow2/disk.qcow2
	QEMU_IMAGE=registry.example/qemu:test run_recipe _run-vm-container qcow2 output/qcow2/disk.qcow2
	[ "$status" -eq 0 ]
	[ "$(tail -n1 "${LOGS}/podman.args")" = "registry.example/qemu:test" ]
}

@test "_run-vm-container: the web console binds loopback on 8006 and opens it" {
	make_artifact output/qcow2/disk.qcow2
	run_recipe _run-vm-container qcow2 output/qcow2/disk.qcow2
	[ "$status" -eq 0 ]
	[[ "$output" == *"Web console: http://localhost:8006"* ]]
	[ "$(arg_after "${LOGS}/podman.args" --publish)" = "127.0.0.1:8006:8006" ]
	# The opener runs in the background; give it a moment to log.
	for _ in 1 2 3 4 5 6 7 8 9 10; do
		[ -s "${LOGS}/xdg-open.log" ] && break
		"${REAL_SLEEP}" 0.1
	done
	[ "$(cat "${LOGS}/xdg-open.log")" = "http://localhost:8006" ]
}

@test "_run-vm-container: a taken console port moves to the next free one" {
	make_artifact output/qcow2/disk.qcow2
	SS_BUSY_PORTS="8006 8007" run_recipe _run-vm-container qcow2 output/qcow2/disk.qcow2
	[ "$status" -eq 0 ]
	[[ "$output" == *"Web console: http://localhost:8008"* ]]
	[ "$(arg_after "${LOGS}/podman.args" --publish)" = "127.0.0.1:8008:8006" ]
}

@test "_run-vm-container: a podman failure is the recipe's failure" {
	make_artifact output/qcow2/disk.qcow2
	STUB_PODMAN_STATUS=125 run_recipe _run-vm-container qcow2 output/qcow2/disk.qcow2
	[ "$status" -ne 0 ]
}

# --- _run-vm dispatch ---------------------------------------------------------

@test "run-vm-raw: without qemu-system-x86_64 the VM boots in the qemus container" {
	unstub qemu-system-x86_64
	make_artifact output/image/disk.raw
	run_recipe run-vm-raw
	[ "$status" -eq 0 ]
	grep -Fxq "${SANDBOX}/output/image/disk.raw:/boot.img" "${LOGS}/podman.args"
	[ ! -e "${LOGS}/build.log" ]
}

@test "run-vm-qcow2: a missing artifact is built first with the default image and tag" {
	unstub qemu-system-x86_64
	run_recipe run-vm-qcow2
	[ "$status" -eq 0 ]
	[ "$(cat "${LOGS}/build.log")" = "build-qcow2 localhost/finpilot stable" ]
	grep -Fxq "${SANDBOX}/output/qcow2/disk.qcow2:/boot.qcow2" "${LOGS}/podman.args"
}

@test "run-vm-iso: a missing artifact is built with the image and tag the caller named" {
	unstub qemu-system-x86_64
	run_recipe run-vm-iso ghcr.io/example/finpilot stable-testing
	[ "$status" -eq 0 ]
	[ "$(cat "${LOGS}/build.log")" = "build-iso ghcr.io/example/finpilot stable-testing" ]
	grep -Fxq "${SANDBOX}/output/bootiso/install.iso:/boot.iso" "${LOGS}/podman.args"
}

@test "run-vm-qcow2: without OVMF firmware QEMU is never started" {
	host_has_ovmf && skip "this host has OVMF firmware installed"
	make_artifact output/qcow2/disk.qcow2
	run_recipe run-vm-qcow2
	[ "$status" -eq 1 ]
	[[ "$output" == *"ERROR: OVMF firmware not found"* ]]
	[ ! -e "${LOGS}/qemu.args" ]
	[ ! -e "${LOGS}/podman.args" ]
}

# --- _run-vm native QEMU ------------------------------------------------------

@test "run-vm-qcow2: boots the built disk in place with UEFI, KVM and ssh on 2222" {
	with_ovmf /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_VARS_4M.fd
	make_artifact output/qcow2/disk.qcow2
	run_recipe_ns run-vm-qcow2
	[ "$status" -eq 0 ]
	args="${LOGS}/qemu.args"
	[ "$(arg_after "${args}" -accel)" = "kvm" ]
	[ "$(arg_after "${args}" -smp)" = "3" ]
	[ "$(arg_after "${args}" -m)" = "4096" ]
	grep -Fxq "user,id=net0,hostfwd=tcp:127.0.0.1:2222-:22" "${args}"
	grep -Fxq "if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd" "${args}"
	grep -Fxq "file=output/qcow2/disk.qcow2,if=virtio,format=qcow2" "${args}"
	[ "$(arg_after "${args}" -boot)" = "order=c" ]
	[ ! -e "${LOGS}/podman.args" ]
}

@test "run-vm-qcow2: QEMU gets a writable copy of the UEFI vars, removed afterwards" {
	with_ovmf /usr/share/edk2/ovmf/OVMF_CODE.fd /usr/share/edk2/ovmf/OVMF_VARS.fd
	make_artifact output/qcow2/disk.qcow2
	run_recipe_ns run-vm-qcow2
	[ "$status" -eq 0 ]
	vars="$(cat "${LOGS}/vars.path")"
	[ "${vars}" != "/usr/share/edk2/ovmf/OVMF_VARS.fd" ]
	[ "$(cat "${LOGS}/vars.content")" = "/usr/share/edk2/ovmf/OVMF_VARS.fd" ]
	[ ! -e "${vars}" ]
}

@test "run-vm-raw: the raw disk is attached with format=raw" {
	with_ovmf /usr/share/qemu/OVMF_CODE.fd /usr/share/qemu/OVMF_VARS.fd
	make_artifact output/image/disk.raw
	run_recipe_ns run-vm-raw
	[ "$status" -eq 0 ]
	grep -Fxq "file=output/image/disk.raw,if=virtio,format=raw" "${LOGS}/qemu.args"
	[ "$(arg_after "${LOGS}/qemu.args" -boot)" = "order=c" ]
}

@test "run-vm-iso: the ISO boots read-only as a CD onto a 64G scratch target, created once" {
	with_ovmf /usr/share/OVMF/OVMF_CODE.fd /usr/share/OVMF/OVMF_VARS.fd
	make_artifact output/bootiso/install.iso
	run_recipe_ns run-vm-iso
	[ "$status" -eq 0 ]
	args="${LOGS}/qemu.args"
	grep -Fxq "file=output/bootiso/install.iso,media=cdrom,readonly=on,format=raw" "${args}"
	grep -Fxq "file=${SANDBOX}/output/iso/target.qcow2,if=virtio,format=qcow2" "${args}"
	[ "$(arg_after "${args}" -boot)" = "order=d" ]
	[ "$(cat "${LOGS}/qemu-img.log")" = "create -f qcow2 output/iso/target.qcow2 64G" ]

	run_recipe_ns run-vm-iso
	[ "$status" -eq 0 ]
	[ "$(wc -l <"${LOGS}/qemu-img.log")" -eq 1 ]
}

@test "run-vm-qcow2: a taken ssh port moves the forward to the next free one" {
	with_ovmf /usr/share/OVMF/OVMF_CODE.fd /usr/share/OVMF/OVMF_VARS.fd
	make_artifact output/qcow2/disk.qcow2
	SS_BUSY_PORTS="2222" run_recipe_ns run-vm-qcow2
	[ "$status" -eq 0 ]
	grep -Fxq "user,id=net0,hostfwd=tcp:127.0.0.1:2223-:22" "${LOGS}/qemu.args"
	[[ "$output" == *"ssh -p 2223"* ]]
}

@test "run-vm-qcow2: with no display the guest console goes to serial on stdio" {
	with_ovmf /usr/share/OVMF/OVMF_CODE.fd /usr/share/OVMF/OVMF_VARS.fd
	make_artifact output/qcow2/disk.qcow2
	run_recipe_ns run-vm-qcow2
	[ "$status" -eq 0 ]
	[ "$(arg_after "${LOGS}/qemu.args" -display)" = "none" ]
	[ "$(arg_after "${LOGS}/qemu.args" -serial)" = "mon:stdio" ]
}

@test "run-vm-qcow2: a Wayland or X display gets a GTK window" {
	with_ovmf /usr/share/OVMF/OVMF_CODE.fd /usr/share/OVMF/OVMF_VARS.fd
	make_artifact output/qcow2/disk.qcow2
	WAYLAND_DISPLAY=wayland-0 run_recipe_ns run-vm-qcow2
	[ "$status" -eq 0 ]
	[ "$(arg_after "${LOGS}/qemu.args" -display)" = "gtk" ]
	! grep -Fxq -- "-serial" "${LOGS}/qemu.args"
}

# --- spawn-vm -----------------------------------------------------------------

@test "spawn-vm: a missing systemd-vmspawn is named, with run-vm as the way out" {
	unstub systemd-vmspawn
	run_recipe spawn-vm
	[ "$status" -eq 1 ]
	[[ "$output" == *"ERROR: systemd-vmspawn not found — use 'just run-vm-qcow2' instead"* ]]
}

@test "spawn-vm: a missing qemu-system-x86_64 is named before anything runs" {
	unstub qemu-system-x86_64
	run_recipe spawn-vm 0 raw
	[ "$status" -eq 1 ]
	[[ "$output" == *"ERROR: qemu-system-x86_64 not found — use 'just run-vm-raw' instead"* ]]
	[ ! -e "${LOGS}/vmspawn.args" ]
}

@test "spawn-vm: an unwritable /dev/kvm is refused" {
	[[ -w /dev/kvm ]] && skip "/dev/kvm is writable on this host"
	run_recipe spawn-vm
	[ "$status" -eq 1 ]
	[[ "$output" == *"ERROR: /dev/kvm is missing or not writable"* ]]
	[ ! -e "${LOGS}/vmspawn.args" ]
}

@test "spawn-vm: an ISO is refused, since vmspawn boots disk images only" {
	with_writable_kvm
	make_artifact output/bootiso/install.iso
	run_recipe_ns spawn-vm 0 iso
	[ "$status" -eq 1 ]
	[[ "$output" == *"use 'just run-vm-iso' for an ISO"* ]]
	[ ! -e "${LOGS}/vmspawn.args" ]
}

@test "spawn-vm: a missing artifact is refused unless a rebuild was asked for" {
	with_writable_kvm
	run_recipe_ns spawn-vm
	[ "$status" -eq 1 ]
	[[ "$output" == *"ERROR: output/qcow2/disk.qcow2 not found — run: just build-qcow2"* ]]
	[ ! -e "${LOGS}/build.log" ]
	[ ! -e "${LOGS}/vmspawn.args" ]
}

@test "spawn-vm: boots the resolved disk with the requested RAM in bytes" {
	numfmt_bin=/usr/bin/numfmt
	[[ -x "${numfmt_bin}" ]] || skip "spawn-vm hardcodes /usr/bin/numfmt"
	with_writable_kvm
	make_artifact output/image/disk.raw
	run_recipe_ns spawn-vm 0 raw 2G
	[ "$status" -eq 0 ]
	args="${LOGS}/vmspawn.args"
	grep -Fxq -- "--ram=2147483648" "${args}"
	[ "$(arg_after "${args}" -i)" = "${SANDBOX}/output/image/disk.raw" ]
	grep -Fxq -- "--network-user-mode" "${args}"
	[ ! -e "${LOGS}/build.log" ]
}

@test "spawn-vm: rebuild=1 builds the type first, then boots it" {
	[[ -x /usr/bin/numfmt ]] || skip "spawn-vm hardcodes /usr/bin/numfmt"
	with_writable_kvm
	run_recipe_ns spawn-vm 1 qcow2
	[ "$status" -eq 0 ]
	[ "$(cat "${LOGS}/build.log")" = "build-qcow2" ]
	[ "$(arg_after "${LOGS}/vmspawn.args" -i)" = "${SANDBOX}/output/qcow2/disk.qcow2" ]
	grep -Fxq -- "--ram=6442450944" "${LOGS}/vmspawn.args"
}
