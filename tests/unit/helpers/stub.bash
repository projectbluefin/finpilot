#!/usr/bin/bash
# Shared BATS helpers for finpilot unit tests.
#
# These helpers create a sandbox directory per test and let a test place fake
# executables ("stubs") ahead of the real ones on PATH, so build scripts that
# call dnf5/systemctl/mountpoint can run outside a container.

# Absolute path to the repository root, derived from this file's location.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export REPO_ROOT

# Creates BATS_TEST_TMPDIR-scoped sandbox state:
#   SANDBOX  - empty directory a test may use as a fake filesystem root
#   STUB_BIN - directory prepended to PATH for stub executables
#   STUB_LOG - file each stub appends its invocation to
setup_sandbox() {
	SANDBOX="${BATS_TEST_TMPDIR}/sandbox"
	STUB_BIN="${BATS_TEST_TMPDIR}/bin"
	STUB_LOG="${BATS_TEST_TMPDIR}/stub.log"
	mkdir -p "${SANDBOX}" "${STUB_BIN}"
	: >"${STUB_LOG}"
	PATH="${STUB_BIN}:${PATH}"
	export SANDBOX STUB_BIN STUB_LOG PATH
}

# stub_command <name> [exit_code]
#
# Creates an executable named <name> in STUB_BIN that logs "<name> <args...>"
# to STUB_LOG and exits with [exit_code] (default 0).
stub_command() {
	local name="$1"
	local exit_code="${2:-0}"
	cat >"${STUB_BIN}/${name}" <<EOF
#!/usr/bin/bash
printf '%s\n' "${name} \$*" >>"${STUB_LOG}"
exit ${exit_code}
EOF
	chmod +x "${STUB_BIN}/${name}"
}

# stub_log_contains <substring>
#
# Succeeds when some recorded stub invocation contains <substring>.
stub_log_contains() {
	grep -qF -- "$1" "${STUB_LOG}"
}
