#!/usr/bin/env bats
#
# Unit tests for the root Justfile's `vm-artifact` recipe and the artifact-path
# contract every VM recipe depends on.
#
# `vm-artifact` is the single definition of where Bootc Image Builder leaves the
# file for a given --type, and the mapping is not the identity: raw exports as
# "image" while qcow2 exports as "qcow2" and an ISO exports as "bootiso". Six
# build/rebuild recipes, three run-vm recipes, `spawn-vm` and `_run-vm-container`
# all resolve their input through it, and nothing executed it. A wrong arm, or a
# type added to a caller without an arm here, surfaces only as a VM boot that
# fails after a full image build.
#
# The recipe is pure -- it echoes a path and touches nothing -- so the mapping
# cases run the real `just` binary directly. The drift cases read the Justfile
# text, because the callers they check cannot be executed without podman, KVM
# and a built image.

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	SANDBOX="$(mktemp -d)"
	cp "${REPO_ROOT}/Justfile" "${SANDBOX}/Justfile"
}

teardown() {
	rm -rf "${SANDBOX}"
}

run_recipe() {
	run just --justfile "${SANDBOX}/Justfile" --working-directory "${SANDBOX}" "$@"
}

# The body of a Justfile recipe, from its signature line up to the next
# top-level construct.
recipe_body() {
	awk -v name="$1" '
		$0 ~ "^" name "([ :])" { inside = 1; print; next }
		inside && /^[^[:space:]#]/ { inside = 0 }
		inside { print }
	' "${REPO_ROOT}/Justfile"
}

@test "vm-artifact: qcow2 resolves to osbuild's qcow2 export" {
	run_recipe vm-artifact qcow2
	[ "$status" -eq 0 ]
	[ "$output" = "output/qcow2/disk.qcow2" ]
}

@test "vm-artifact: raw resolves to the 'image' export, not 'raw'" {
	run_recipe vm-artifact raw
	[ "$status" -eq 0 ]
	[ "$output" = "output/image/disk.raw" ]
}

@test "vm-artifact: iso resolves to the 'bootiso' export, not 'iso'" {
	run_recipe vm-artifact iso
	[ "$status" -eq 0 ]
	[ "$output" = "output/bootiso/install.iso" ]
}

@test "vm-artifact: an unknown type fails and names the type it was given" {
	run_recipe vm-artifact vhdx
	[ "$status" -ne 0 ]
	[[ "$output" == *"vhdx"* ]]
	[[ "$output" == *"qcow2"* ]]

	# A caller does `artifact=$(just vm-artifact "${type}")`, so an error that
	# reaches stdout becomes a path and the caller builds on it. Captured
	# outside `run`, which merges stderr into stdout.
	local on_stdout
	on_stdout="$(just --justfile "${SANDBOX}/Justfile" --working-directory "${SANDBOX}" \
		vm-artifact vhdx 2>/dev/null || true)"
	[ -z "${on_stdout}" ]
}

@test "vm-artifact: an empty type is rejected rather than resolved" {
	run_recipe vm-artifact ""
	[ "$status" -ne 0 ]
}

@test "vm-artifact: every resolved artifact lives under output/, which just clean removes" {
	local type
	for type in qcow2 raw iso; do
		run_recipe vm-artifact "${type}"
		[ "$status" -eq 0 ]
		[[ "$output" == output/* ]]
	done
}

@test "vm-artifact: resolves every type the build and rebuild recipes pass to the bib recipes" {
	local types
	types="$(grep -Eo '_(re)?build-bib target_image tag "[a-z0-9]+"' "${REPO_ROOT}/Justfile" |
		sed -E 's/.*"([a-z0-9]+)"/\1/' | sort -u)"
	[ -n "${types}" ]

	local type
	while read -r type; do
		run_recipe vm-artifact "${type}"
		[ "$status" -eq 0 ] || {
			echo "no vm-artifact arm for build type '${type}'"
			return 1
		}
	done <<<"${types}"
}

@test "vm-artifact: resolves every type the run-vm recipes pass to _run-vm" {
	local types
	types="$(grep -Eo '\(_run-vm target_image tag "[a-z0-9]+"\)' "${REPO_ROOT}/Justfile" |
		sed -E 's/.*"([a-z0-9]+)".*/\1/' | sort -u)"
	[ -n "${types}" ]

	local type
	while read -r type; do
		run_recipe vm-artifact "${type}"
		[ "$status" -eq 0 ] || {
			echo "no vm-artifact arm for run-vm type '${type}'"
			return 1
		}
	done <<<"${types}"
}

@test "bib callers pair the ISO type with iso/iso.toml and disk types with iso/disk.toml" {
	local line type config seen=0
	while read -r line; do
		type="$(sed -E 's/.*_(re)?build-bib target_image tag "([a-z0-9]+)".*/\2/' <<<"${line}")"
		config="$(sed -E 's/.*_(re)?build-bib target_image tag "[a-z0-9]+" "([^"]+)".*/\2/' <<<"${line}")"
		seen=$((seen + 1))

		if [[ "${type}" == "iso" ]]; then
			[ "${config}" = "iso/iso.toml" ]
		else
			[ "${config}" = "iso/disk.toml" ]
		fi
		[ -f "${REPO_ROOT}/${config}" ]
	done < <(grep -E '_(re)?build-bib target_image tag "[a-z0-9]+" "[^"]+"' "${REPO_ROOT}/Justfile")

	# qcow2, raw and iso, for both build-* and rebuild-*.
	[ "${seen}" -ge 6 ]
}

@test "_run-vm-container handles exactly the types vm-artifact resolves" {
	local arms
	arms="$(recipe_body _run-vm-container | grep -Eo '^[[:space:]]+[a-z0-9|]+\)' |
		tr -d ' )' | tr '|' '\n' | sort -u)"
	[ -n "${arms}" ]

	# Its case has no default arm: an unhandled type leaves boot_mount unset
	# and `set -u` kills the run after the image was already built.
	[ "$(tr '\n' ' ' <<<"${arms}")" = "iso qcow2 raw " ]

	local arm
	while read -r arm; do
		run_recipe vm-artifact "${arm}"
		[ "$status" -eq 0 ]
	done <<<"${arms}"
}

@test "_run-vm and spawn-vm resolve the artifact through vm-artifact, never a literal path" {
	local recipe body
	for recipe in _run-vm spawn-vm; do
		body="$(recipe_body "${recipe}")"
		[ -n "${body}" ]
		[[ "${body}" == *"just vm-artifact"* ]]

		# A second copy of the mapping is the drift this recipe exists to stop.
		run grep -Eq 'output/(qcow2/disk\.qcow2|image/disk\.raw|bootiso/install\.iso)' <<<"${body}"
		[ "$status" -ne 0 ]
	done
}
