#!/usr/bin/env bats
# Tests for the inactive build examples: build/*.sh.example.
#
# These four files are the only shell in the repository that nothing else
# checks. `just lint` and pr-validation.yml both resolve their scope from
# `git ls-files '*.sh'`, which does not match a `.sh.example` suffix, and the
# Containerfile never runs them. A contributor activates one by renaming it,
# so a syntax error or a broken instruction in one of them reaches a user's
# build unreviewed by any gate.
#
# The assertions here are the rules build/README.md states for a build script,
# plus the claims each example makes about itself and about 90-cleanup.sh.

BUILD_DIR="${BATS_TEST_DIRNAME}/../../build"
README="${BUILD_DIR}/README.md"
CLEANUP="${BUILD_DIR}/90-cleanup.sh"

_examples() {
    find "${BUILD_DIR}" -maxdepth 1 -type f -name '*.sh.example' | sort
}

setup() {
    mapfile -t EXAMPLES < <(_examples)
    # An empty subject list would pass every loop below silently.
    [ "${#EXAMPLES[@]}" -gt 0 ]
}

@test "every example is syntactically valid bash" {
    for example in "${EXAMPLES[@]}"; do
        run bash -n "${example}"
        [ "${status}" -eq 0 ] || {
            echo "${example}: ${output}" >&2
            return 1
        }
    done
}

@test "every example declares the bash shebang and strict mode" {
    for example in "${EXAMPLES[@]}"; do
        run head -n 1 "${example}"
        [ "${output}" = "#!/usr/bin/env bash" ] || {
            echo "${example}: first line is '${output}'" >&2
            return 1
        }
        grep -qx 'set -euo pipefail' "${example}" || {
            echo "${example}: no 'set -euo pipefail'" >&2
            return 1
        }
    done
}

@test "no example calls dnf or yum instead of dnf5" {
    # build/README.md: "Use dnf5, never dnf or yum".
    for example in "${EXAMPLES[@]}"; do
        run grep -nE '(^|[^[:alnum:]_/-])(dnf|yum)[[:space:]]' "${example}"
        [ "${status}" -ne 0 ] || {
            echo "${example}: ${output}" >&2
            return 1
        }
    done
}

@test "every dnf5 transaction is non-interactive" {
    # build/README.md: "always -y". A transaction without it hangs the build.
    for example in "${EXAMPLES[@]}"; do
        while IFS= read -r line; do
            [ -n "${line}" ] || continue
            case "${line}" in
                *" -y"*) ;;
                *)
                    echo "${example}: missing -y: ${line}" >&2
                    return 1
                    ;;
            esac
        done < <(grep -E '^[[:space:]]*dnf5[[:space:]]+(install|remove|upgrade|swap|group)' "${example}")
    done
}

@test "every example names the filename it is activated as" {
    # Each header tells the reader what to rename the file to. A file renamed
    # without its header updated sends the reader to a path that does not exist.
    for example in "${EXAMPLES[@]}"; do
        local activated
        activated="$(basename "${example}" .example)"
        grep -qF "${activated}" "${example}" || {
            echo "${example}: header never mentions '${activated}'" >&2
            return 1
        }
    done
}

@test "build/README.md lists exactly the examples that exist" {
    for example in "${EXAMPLES[@]}"; do
        local name
        name="$(basename "${example}")"
        grep -qF "\`${name}\`" "${README}" || {
            echo "build/README.md does not list ${name}" >&2
            return 1
        }
    done

    # And the reverse: README must not advertise an example that was deleted.
    while IFS= read -r name; do
        [ -f "${BUILD_DIR}/${name}" ] || {
            echo "build/README.md lists ${name}, which does not exist" >&2
            return 1
        }
    done < <(grep -oE '`[0-9]+-[a-z-]+\.sh\.example`' "${README}" | tr -d '`' | sort -u)
}

@test "every repository file an example drops into /etc/yum.repos.d is removed by it" {
    # A third-party repository is a build-time source only. Leaving the .repo
    # behind ships a live third-party source in the image.
    for example in "${EXAMPLES[@]}"; do
        while IFS= read -r repo_file; do
            grep -qE "rm[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*${repo_file}([[:space:]]|$)" "${example}" || {
                echo "${example}: ${repo_file} is written but never removed" >&2
                return 1
            }
        done < <(grep -ohE '/etc/yum\.repos\.d/[A-Za-z0-9_.-]+\.repo' "${example}" | sort -u)
    done
}

@test "90-cleanup.sh still disables tailscale.repo as the documented backstop" {
    # 30-tailscale.sh.example tells the reader that 90-cleanup.sh disables
    # tailscale.repo as a backstop. Dropping tailscale from that loop makes the
    # example's promise false without touching the example.
    grep -qF "90-cleanup.sh also disables tailscale.repo" \
        "${BUILD_DIR}/30-tailscale.sh.example"
    grep -qE '^for repo_name in .*[[:space:]]tailscale([[:space:]]|;)' "${CLEANUP}"
}

@test "shellcheck is clean on every example" {
    # `just lint` cannot reach these files: its scope is `git ls-files '*.sh'`.
    command -v shellcheck >/dev/null || skip "shellcheck is not installed"
    for example in "${EXAMPLES[@]}"; do
        run shellcheck --shell=bash "${example}"
        [ "${status}" -eq 0 ] || {
            echo "${example}: ${output}" >&2
            return 1
        }
    done
}
