#!/usr/bin/env bash
# Validate flatpak preinstall files under custom/flatpaks/ without mutating
# the host beyond adding the flathub remote (--user, --if-not-exists).
#
# Contract enforced per app:
#   - every [Flatpak Preinstall <app-id>] section must declare a Branch= key
#   - every declared app-id must resolve on the flathub remote
#
# Single implementation of the flatpak validation contract; the CI workflow
# (.github/workflows/validate-flatpaks.yml) and `just validate-flatpaks` are
# thin callers. Mirrors the Brewfile contract in build/validate-brewfiles.sh.

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

    flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

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
        while IFS= read -r app_id; do
            branch=$(awk -v app="${app_id}" '
                $0 == "[Flatpak Preinstall " app "]" {found=1; next}
                found && /^Branch=/ {print; valid=1; exit}
                found && /^\[/ {exit}
                END {if (!valid) print "MISSING"}
            ' "${preinstall}")
            if [[ "${branch}" == "MISSING" ]]; then
                failed=$((failed + 1))
                printf 'FAIL: %s: %s: missing Branch= key\n' "${preinstall}" "${app_id}" >&2
                continue
            fi
            checked=$((checked + 1))
            if flatpak remote-info --user flathub "${app_id}" > "${workdir}/output" 2>&1; then
                printf 'PASS: %s: %s (%s)\n' "${preinstall}" "${app_id}" "${branch#Branch=}"
            else
                rc=$?
                failed=$((failed + 1))
                printf 'FAIL: %s: %s: not on flathub (exit %s)\n' "${preinstall}" "${app_id}" "${rc}" >&2
                printf 'Command: flatpak remote-info --user flathub %q\n' "${app_id}" >&2
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
