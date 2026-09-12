#!/usr/bin/env bats
# Tests for .github/actions/check-token-health/check_token_health.sh.
#
# The script is the fail-fast gate every PAT-dependent workflow runs first, so
# the properties under test are the ones a workflow relies on: a non-200 status
# or a missing required scope must fail CLOSED (exit 1 with valid=false written
# to GITHUB_OUTPUT), and a healthy token must publish valid/rate_remaining/
# expires_at outputs.
#
# curl is stubbed on PATH — no network call is ever made and no real token is
# used. The stub honours curl's -D flag so header-parsing paths are exercised
# against fixture headers.
#
# Run with: bats tests/unit/check-token-health_test.bats

SCRIPT="${BATS_TEST_DIRNAME}/../../.github/actions/check-token-health/check_token_health.sh"

setup() {
    WORKDIR="$(mktemp -d)"
    mkdir -p "${WORKDIR}/bin" "${WORKDIR}/tmp"
    OUTPUT_FILE="${WORKDIR}/github_output"
    : >"${OUTPUT_FILE}"
    CURL_ARGS="${WORKDIR}/curl_args"

    cat >"${WORKDIR}/bin/curl" <<'MOCK'
#!/usr/bin/env bash
# Record the invocation, emit the fixture headers to curl's -D target, and
# print the stubbed HTTP status on stdout (the script uses -o /dev/null -w).
printf '%s\n' "$*" >>"${CURL_ARGS}"
headers_file=""
prev=""
for arg in "$@"; do
    [[ "${prev}" == "-D" ]] && headers_file="${arg}"
    prev="${arg}"
done
if [[ -n "${headers_file}" && -n "${STUB_HEADERS:-}" ]]; then
    printf '%s' "${STUB_HEADERS}" >"${headers_file}"
elif [[ -n "${headers_file}" ]]; then
    : >"${headers_file}"
fi
if [[ "${STUB_CURL_FAILS:-0}" == "1" ]]; then
    exit 7
fi
printf '%s' "${STUB_HTTP_CODE:-200}"
MOCK
    chmod +x "${WORKDIR}/bin/curl"

    export PATH="${WORKDIR}/bin:${PATH}"
    export CURL_ARGS
    export RUNNER_TEMP="${WORKDIR}/tmp"
    export GITHUB_OUTPUT="${OUTPUT_FILE}"
    export GH_TOKEN="stub-token-not-a-credential"
    export TOKEN_NAME="TEST_TOKEN"
    export REQUIRED_SCOPES=""
    export MIN_REMAINING="100"
    export STUB_HTTP_CODE="200"
    export STUB_HEADERS=""
    export STUB_CURL_FAILS="0"
}

teardown() {
    [[ -n "${WORKDIR:-}" ]] && rm -rf "${WORKDIR}"
}

# A classic PAT response: GitHub returns rate-limit AND x-oauth-scopes headers.
# Every header the script greps must be present, because `set -e` aborts the
# script on the first grep that finds nothing (see the two skipped tests below).
pat_headers() {
    printf 'HTTP/2 200\r\nx-ratelimit-limit: 5000\r\nx-ratelimit-remaining: 4999\r\nx-oauth-scopes: repo, workflow, read:org\r\n'
}

# --- required environment -------------------------------------------------

@test "fails when GH_TOKEN is unset" {
    unset GH_TOKEN
    run bash "${SCRIPT}"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"GH_TOKEN is required"* ]]
}

@test "fails when TOKEN_NAME is unset" {
    unset TOKEN_NAME
    run bash "${SCRIPT}"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"TOKEN_NAME is required"* ]]
}

@test "REQUIRED_SCOPES and MIN_REMAINING are optional" {
    unset REQUIRED_SCOPES MIN_REMAINING
    STUB_HEADERS="$(pat_headers)"
    run bash "${SCRIPT}"
    [ "${status}" -eq 0 ]
    grep -qx 'valid=true' "${OUTPUT_FILE}"
}

# --- HTTP status gate -----------------------------------------------------

@test "healthy token exits 0 and reports the status" {
    STUB_HEADERS="$(pat_headers)"
    run bash "${SCRIPT}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Validating TEST_TOKEN..."* ]]
    [[ "${output}" == *"Token is valid (HTTP 200)."* ]]
    [[ "${output}" == *"TEST_TOKEN health check passed."* ]]
}

@test "401 fails closed with an error annotation and valid=false" {
    STUB_HTTP_CODE="401"
    run bash "${SCRIPT}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"::error::TEST_TOKEN is invalid (HTTP 401)"* ]]
    grep -qx 'valid=false' "${OUTPUT_FILE}"
    ! grep -qx 'valid=true' "${OUTPUT_FILE}"
}

@test "403 fails closed" {
    STUB_HTTP_CODE="403"
    run bash "${SCRIPT}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"(HTTP 403)"* ]]
    grep -qx 'valid=false' "${OUTPUT_FILE}"
}

@test "a curl transport failure fails closed rather than passing" {
    STUB_CURL_FAILS="1"
    run bash "${SCRIPT}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"::error::TEST_TOKEN is invalid"* ]]
    grep -qx 'valid=false' "${OUTPUT_FILE}"
}

@test "the token is presented to the /user endpoint with the JSON accept header" {
    STUB_HEADERS="$(pat_headers)"
    run bash "${SCRIPT}"
    [ "${status}" -eq 0 ]
    grep -q 'https://api.github.com/user' "${CURL_ARGS}"
    grep -q 'Accept: application/vnd.github+json' "${CURL_ARGS}"
    # The value of GH_TOKEN must reach the request, otherwise the check would
    # validate an anonymous call and pass for a revoked token.
    grep -q "${GH_TOKEN}" "${CURL_ARGS}"
    # Nothing is written to stdout that could leak the credential into logs.
    [[ "${output}" != *"${GH_TOKEN}"* ]]
}

# --- rate limit parsing ---------------------------------------------------

@test "rate limit headers are parsed and reported" {
    STUB_HEADERS="$(pat_headers)"
    run bash "${SCRIPT}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Rate limit: 4999/5000"* ]]
    grep -qx 'rate_remaining=4999' "${OUTPUT_FILE}"
}

@test "header matching is case-insensitive" {
    STUB_HEADERS="$(printf 'HTTP/2 200\r\nX-RateLimit-Limit: 5000\r\nX-RateLimit-Remaining: 3000\r\nX-OAuth-Scopes: repo\r\n')"
    run bash "${SCRIPT}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Rate limit: 3000/5000"* ]]
}

@test "missing rate limit headers report unknown and still pass" {
    skip "known defect #339: RATE_REMAINING=\$(grep ...) aborts under set -e when the header is absent"
    STUB_HEADERS="$(printf 'HTTP/2 200\r\n')"
    run bash "${SCRIPT}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Rate limit: unknown/unknown"* ]]
    grep -qx 'rate_remaining=unknown' "${OUTPUT_FILE}"
}

@test "remaining below MIN_REMAINING warns but does not fail" {
    MIN_REMAINING="100"
    STUB_HEADERS="$(printf 'HTTP/2 200\r\nx-ratelimit-limit: 5000\r\nx-ratelimit-remaining: 42\r\nx-oauth-scopes: repo\r\n')"
    run bash "${SCRIPT}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"::warning::TEST_TOKEN has only 42 API requests remaining (minimum: 100)"* ]]
    grep -qx 'valid=true' "${OUTPUT_FILE}"
}

@test "remaining equal to MIN_REMAINING does not warn" {
    MIN_REMAINING="100"
    STUB_HEADERS="$(printf 'HTTP/2 200\r\nx-ratelimit-limit: 5000\r\nx-ratelimit-remaining: 100\r\nx-oauth-scopes: repo\r\n')"
    run bash "${SCRIPT}"
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"::warning::"* ]]
}

@test "MIN_REMAINING is honoured when overridden" {
    MIN_REMAINING="5000"
    STUB_HEADERS="$(pat_headers)"
    run bash "${SCRIPT}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"::warning::TEST_TOKEN has only 4999 API requests remaining (minimum: 5000)"* ]]
}

# --- scope enforcement ----------------------------------------------------

@test "required scopes present passes" {
    REQUIRED_SCOPES="repo,workflow"
    STUB_HEADERS="$(printf 'HTTP/2 200\r\nx-ratelimit-limit: 5000\r\nx-ratelimit-remaining: 4999\r\nx-oauth-scopes: repo, workflow, read:org\r\n')"
    run bash "${SCRIPT}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Scopes: repo, workflow, read:org"* ]]
    [[ "${output}" == *"All required scopes present."* ]]
    grep -qx 'valid=true' "${OUTPUT_FILE}"
}

@test "a missing required scope fails closed with valid=false" {
    REQUIRED_SCOPES="repo,workflow"
    STUB_HEADERS="$(printf 'HTTP/2 200\r\nx-ratelimit-limit: 5000\r\nx-ratelimit-remaining: 4999\r\nx-oauth-scopes: repo, read:org\r\n')"
    run bash "${SCRIPT}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"::error::TEST_TOKEN is missing required scope: workflow"* ]]
    grep -qx 'valid=false' "${OUTPUT_FILE}"
    ! grep -qx 'valid=true' "${OUTPUT_FILE}"
}

@test "whitespace around required scopes is trimmed" {
    REQUIRED_SCOPES="  repo ,  workflow  "
    STUB_HEADERS="$(printf 'HTTP/2 200\r\nx-ratelimit-limit: 5000\r\nx-ratelimit-remaining: 4999\r\nx-oauth-scopes: repo, workflow\r\n')"
    run bash "${SCRIPT}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"All required scopes present."* ]]
}

@test "empty REQUIRED_SCOPES accepts any valid token without scope checking" {
    REQUIRED_SCOPES=""
    STUB_HEADERS="$(printf 'HTTP/2 200\r\nx-ratelimit-limit: 5000\r\nx-ratelimit-remaining: 4999\r\nx-oauth-scopes: read:org\r\n')"
    run bash "${SCRIPT}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Scopes: read:org"* ]]
    [[ "${output}" != *"All required scopes present."* ]]
    grep -qx 'valid=true' "${OUTPUT_FILE}"
}

@test "fine-grained token without a scopes header skips the scope check" {
    skip "known defect #339: SCOPES=\$(grep ...) aborts under set -e, so the documented fine-grained/App-token branch is unreachable"
    REQUIRED_SCOPES="repo,workflow"
    STUB_HEADERS="$(printf 'HTTP/2 200\r\nx-ratelimit-limit: 5000\r\nx-ratelimit-remaining: 4999\r\n')"
    run bash "${SCRIPT}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"No OAuth scopes header"* ]]
    [[ "${output}" == *"skipping scope check"* ]]
    grep -qx 'valid=true' "${OUTPUT_FILE}"
}

# --- outputs and cleanup --------------------------------------------------

@test "all three outputs are written on success" {
    STUB_HEADERS="$(pat_headers)"
    run bash "${SCRIPT}"
    [ "${status}" -eq 0 ]
    grep -qx 'valid=true' "${OUTPUT_FILE}"
    grep -qx 'rate_remaining=4999' "${OUTPUT_FILE}"
    grep -qx 'expires_at=' "${OUTPUT_FILE}"
}

@test "outputs append rather than truncate GITHUB_OUTPUT" {
    echo 'preexisting=value' >"${OUTPUT_FILE}"
    STUB_HEADERS="$(pat_headers)"
    run bash "${SCRIPT}"
    [ "${status}" -eq 0 ]
    grep -qx 'preexisting=value' "${OUTPUT_FILE}"
    grep -qx 'valid=true' "${OUTPUT_FILE}"
}

@test "the headers file is written under RUNNER_TEMP and removed on success" {
    STUB_HEADERS="$(pat_headers)"
    run bash "${SCRIPT}"
    [ "${status}" -eq 0 ]
    grep -q -- "-D ${RUNNER_TEMP}/token-health-headers-" "${CURL_ARGS}"
    [ -z "$(find "${RUNNER_TEMP}" -name 'token-health-headers-*' -print -quit)" ]
}

@test "the headers file is removed on the failure path too" {
    STUB_HTTP_CODE="401"
    run bash "${SCRIPT}"
    [ "${status}" -eq 1 ]
    [ -z "$(find "${RUNNER_TEMP}" -name 'token-health-headers-*' -print -quit)" ]
}

@test "RUNNER_TEMP defaults to /tmp when unset" {
    unset RUNNER_TEMP
    STUB_HEADERS="$(pat_headers)"
    run bash "${SCRIPT}"
    [ "${status}" -eq 0 ]
    grep -q -- '-D /tmp/token-health-headers-' "${CURL_ARGS}"
}
