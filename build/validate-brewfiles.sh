#!/usr/bin/env bash
# Check every Brewfile against real Homebrew metadata without evaluating the
# Brewfiles as Ruby. Brewfiles are a Ruby DSL: `brew bundle check` loads them
# through Homebrew's evaluator, so a PR-controlled Brewfile gets code execution
# in CI. This script only ever greps the files — entries are passed to
# `brew info` as data — and rejects anything that is not a quoted literal.
#
# Ported from projectbluefin/common scripts/validate-brewfiles.sh with one
# hardening on top: tap declarations are validated as literals too, because
# the taps-only file below IS fed back to `brew bundle` (and therefore
# evaluated). A computed tap line fails closed here instead.
#
# This syncs declared taps but never installs formulae/casks.

main() (
    set -euo pipefail
    if [[ $# -gt 1 ]]; then
        echo "Usage: $0 [brewfile-directory]" >&2
        exit 2
    fi
    root="${1:-custom/brew}"
    if [[ ! -d "${root}" ]]; then
        printf 'Brewfile directory does not exist: %s\n' "${root}" >&2
        exit 2
    fi
    if ! command -v brew >/dev/null; then
        echo "Homebrew is required to validate Brewfiles." >&2
        exit 2
    fi

    workdir=$(mktemp -d)
    trap 'rm -rf -- "${workdir}"' EXIT
    # Materialize discovery so find/sort failures cannot become an empty success.
    find "${root}" -type f -iname '*.Brewfile' -print0 | sort -z > "${workdir}/files"
    mapfile -d '' -t brewfiles < "${workdir}/files"
    if [[ ${#brewfiles[@]} -eq 0 ]]; then
        printf 'No Brewfiles found in %s\n' "${root}" >&2
        exit 2
    fi

    # Sync the complete tap set first: otherwise bare-name ambiguity depends on
    # which Brewfile find happens to visit first. Only literal tap declarations
    # are collected — the taps file is evaluated as Ruby by `brew bundle`, so
    # trailing code or string interpolation (#{...}) fails closed here.
    # The only accepted option is the documented trust flag.
    tap_entry='^[[:space:]]*tap[[:space:]]+"[^{}"]+"([[:space:]]*,[[:space:]]*trusted:[[:space:]]*(true|false))?[[:space:]]*(#.*)?$'
    tap_single="^[[:space:]]*tap[[:space:]]+'[^']+'([[:space:]]*,[[:space:]]*trusted:[[:space:]]*(true|false))?[[:space:]]*(#.*)?$"
    tap_declaration='^[[:space:]]*tap([^[:alnum:]_]|$)'
    : > "${workdir}/taps.Brewfile"
    for brewfile in "${brewfiles[@]}"; do
        line_number=0
        while IFS= read -r line || [[ -n "${line}" ]]; do
            line_number=$((line_number + 1))
            if [[ "${line}" =~ ${tap_declaration} ]]; then
                if [[ "${line}" =~ ${tap_entry} || "${line}" =~ ${tap_single} ]]; then
                    printf '%s\n' "${line}" >> "${workdir}/taps.Brewfile"
                else
                    printf 'FAIL: %s:%s: expected a quoted literal tap declaration: %s\n' "${brewfile}" "${line_number}" "${line}" >&2
                    printf 'Validation complete: refusing to evaluate non-literal tap lines.\n' >&2
                    exit 1
                fi
            fi
        done < "${brewfile}"
    done
    sort -u "${workdir}/taps.Brewfile" -o "${workdir}/taps.Brewfile"
    if [[ -s "${workdir}/taps.Brewfile" ]]; then
        echo "Syncing declared taps from:"
        printf '  %s\n' "${brewfiles[@]}"
        sed 's/^/  /' "${workdir}/taps.Brewfile"
        if brew bundle --file="${workdir}/taps.Brewfile" > "${workdir}/output" 2>&1; then
            echo "Tap setup passed."
        else
            rc=$?
            printf 'FAIL: tap setup (exit %s). Package checks were not run.\n' "${rc}" >&2
            printf 'Command: brew bundle --file=%q\n' "${workdir}/taps.Brewfile" >&2
            sed 's/^/  /' "${workdir}/output" >&2
            exit 1
        fi
    fi

    # The repository uses literal brew/cask declarations, not computed Ruby.
    # Reject malformed declarations rather than silently skipping them.
    double_entry='^[[:space:]]*(brew|cask)[[:space:]]+"([^"]+)"([[:space:]]*,.*|[[:space:]]*(#.*)?)$'
    single_entry="^[[:space:]]*(brew|cask)[[:space:]]+'([^']+)'([[:space:]]*,.*|[[:space:]]*(#.*)?)$"
    declaration='^[[:space:]]*(brew|cask)([^[:alnum:]_]|$)'
    checked=0
    failed=0
    for brewfile in "${brewfiles[@]}"; do
        printf '\nBrewfile: %s\n' "${brewfile}"
        line_number=0
        while IFS= read -r line || [[ -n "${line}" ]]; do
            line_number=$((line_number + 1))
            if [[ "${line}" =~ ${double_entry} || "${line}" =~ ${single_entry} ]]; then
                type="${BASH_REMATCH[1]}"
                name="${BASH_REMATCH[2]}"
                [[ "${type}" != brew ]] || type=formula
                checked=$((checked + 1))
                # Pass names as data, never interpolate them into bash -c.
                # Serial checks keep each error adjacent to its source location.
                if brew info "--${type}" -- "${name}" > "${workdir}/output" 2>&1; then
                    printf 'PASS: %s:%s: %s %s\n' "${brewfile}" "${line_number}" "${type}" "${name}"
                else
                    rc=$?
                    failed=$((failed + 1))
                    printf 'FAIL: %s:%s: %s %s (exit %s)\n' "${brewfile}" "${line_number}" "${type}" "${name}" "${rc}" >&2
                    printf 'Command: brew info --%s -- %q\n' "${type}" "${name}" >&2
                    sed 's/^/  /' "${workdir}/output" >&2
                fi
            elif [[ "${line}" =~ ${declaration} ]]; then
                failed=$((failed + 1))
                printf 'FAIL: %s:%s: expected a quoted literal brew/cask name: %s\n' "${brewfile}" "${line_number}" "${line}" >&2
            fi
        done < "${brewfile}"
    done
    printf '\nValidation complete: %s Brewfiles, %s package checks, %s failures.\n' "${#brewfiles[@]}" "${checked}" "${failed}"
    [[ "${failed}" -eq 0 ]]
)

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
