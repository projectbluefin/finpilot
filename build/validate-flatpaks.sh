#!/usr/bin/env bash
# Validate flatpak preinstall files under custom/flatpaks/ without mutating
# the host beyond (re)installing the flathub remote (--user, --force).
#
# Contract enforced per app:
#   - every line must be a blank line, a '#' comment, a [Flatpak Preinstall
#     <app-id>] header, or a key=value pair, which is the shape GKeyFile
#     accepts; flatpak logs anything else at g_info level and then discards the
#     whole file, so malformed syntax looks identical to an empty list
#   - every [Flatpak Preinstall <app-id>] section must declare a non-empty
#     Branch= key (an empty one fails closed, never resolves on the remote)
#   - every declared app-id must resolve on the flathub remote at its declared
#     branch (queried as <app-id>//<branch>, so a malformed or unpublished
#     branch fails instead of passing on the app-id alone)
#
# Single implementation of the flatpak validation contract; the CI workflow
# (.github/workflows/validate-flatpaks.yml) and `just validate-flatpaks` are
# thin callers. Mirrors the Brewfile contract in build/validate-brewfiles.sh.
#
# --force (not --if-not-exists): on a dev host a flathub remote may already
# exist, and --if-not-exists would leave it untouched, so validation runs
# against a stale or misconfigured remote instead of the pinned descriptor.
# --force re-adds the pinned descriptor every run so the check always resolves
# against the intended flathub. See projectbluefin/finpilot#523.

main() (
    set -euo pipefail
    if [[ $# -gt 1 ]]; then
        echo "Usage: $0 [flatpak-directory]" >&2
        exit 2
    fi
    root="${1:-custom/flatpaks}"
    if [[ ! -d "${root}" ]]; then
        printf 'Flatpak directory does not exist: %s\n' "${root}" >&2
        exit 2
    fi
    if ! command -v flatpak >/dev/null; then
        echo "flatpak is required to validate preinstall files." >&2
        exit 2
    fi

    flatpak remote-add --user --force flathub https://dl.flathub.org/repo/flathub.flatpakrepo

    workdir=$(mktemp -d)
    trap 'rm -rf -- "${workdir}"' EXIT
    # Materialize discovery so find/sort failures cannot become an empty success.
    find "${root}" -type f -iname '*.preinstall' -print0 | sort -z > "${workdir}/files"
    mapfile -d '' -t preinstalls < "${workdir}/files"
    if [[ ${#preinstalls[@]} -eq 0 ]]; then
        printf 'No .preinstall files found in %s\n' "${root}" >&2
        exit 2
    fi

    failed=0
    checked=0
    for preinstall in "${preinstalls[@]}"; do
        printf '\nPreinstall: %s\n' "${preinstall}"

        # Syntax pass. flatpak parses these files with GKeyFile and, on a
        # malformed line, logs the error at g_info level and carries on with an
        # empty keyfile (common/flatpak-dir.c), so one stray line silently
        # reduces the whole list to a no-op. Groups are matched by prefix and
        # any other name is skipped at the same level, so a header that is not
        # exactly [Flatpak Preinstall <app-id>] drops that app just as quietly.
        line_number=0
        in_group=0
        while IFS= read -r line || [[ -n "${line}" ]]; do
            line_number=$((line_number + 1))
            if [[ -z "${line}" || "${line}" == "#"* ]]; then
                continue
            elif [[ "${line}" =~ ^\[Flatpak\ Preinstall\ [A-Za-z0-9._-]+\]$ ]]; then
                in_group=1
                continue
            elif [[ "${in_group}" -eq 1 && "${line}" != "["* && "${line}" == *"="* ]]; then
                continue
            fi
            failed=$((failed + 1))
            printf 'FAIL: %s:%s: not a # comment, a [Flatpak Preinstall <app-id>] header, or a key=value pair: %s\n' \
                "${preinstall}" "${line_number}" "${line}" >&2
        done < "${preinstall}"

        while IFS= read -r app_id; do
            branch=$(awk -v app="${app_id}" '
                $0 == "[Flatpak Preinstall " app "]" {found=1; next}
                # GKeyFile strips the whitespace around the key and the "="
                # before comparing, so `Branch = stable` is the key Branch,
                # and for a duplicate key the LAST value wins (g_hash_table_replace
                # in glib/gkeyfile.c). Strip only leading whitespace from the
                # value: GKeyFile preserves trailing whitespace (g_strndup to
                # end of line), so `Branch=stable ` names branch "stable "
                # and the remote check must catch that. Fail closed when the
                # last value is empty. See projectbluefin/finpilot#509 #513.
                found && /^[[:space:]]*Branch[[:space:]]*=/ {
                    val = $0
                    sub(/^[^=]*=/, "", val)
                    sub(/^[[:space:]]+/, "", val)
                    branch = val
                    valid = 1
                }
                found && /^\[/ {exit}
                END {if (!valid || branch == "") print "MISSING"; else print branch}
            ' "${preinstall}")
            if [[ "${branch}" == "MISSING" ]]; then
                failed=$((failed + 1))
                printf 'FAIL: %s: %s: missing Branch= key\n' "${preinstall}" "${app_id}" >&2
                continue
            fi
            checked=$((checked + 1))
            # Pass the Branch= value in the app ref (APP//BRANCH) so a
            # non-empty but nonexistent or malformed branch (e.g. Branch=nope,
            # Branch=stable with trailing space) fails here instead of
            # resolving against the remote's default branch and passing.
            ref="${app_id}//${branch}"
            if flatpak remote-info --user flathub "${ref}" > "${workdir}/output" 2>&1; then
                printf 'PASS: %s: %s (%s)\n' "${preinstall}" "${app_id}" "${branch}"
            else
                rc=$?
                failed=$((failed + 1))
                printf 'FAIL: %s: %s: not on flathub at branch %q (exit %s)\n' "${preinstall}" "${app_id}" "${branch}" "${rc}" >&2
                printf 'Command: flatpak remote-info --user flathub %q\n' "${ref}" >&2
                sed 's/^/  /' "${workdir}/output" >&2
            fi
        done < <(sed -n 's/^\[Flatpak Preinstall \(.*\)\]$/\1/p' "${preinstall}")
    done
    printf '\nValidation complete: %s preinstall files, %s app checks, %s failures.\n' "${#preinstalls[@]}" "${checked}" "${failed}"
    [[ "${failed}" -eq 0 ]]
)

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
