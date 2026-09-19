#!/usr/bin/env bash
# Token Health Check — validates a GitHub token against the API.
# Called by the composite action; env vars are set in action.yml.
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${TOKEN_NAME:?TOKEN_NAME is required}"
: "${REQUIRED_SCOPES:=}"
: "${MIN_REMAINING:=100}"

GITHUB_API="https://api.github.com"
TMPDIR="${RUNNER_TEMP:-/tmp}"
HEADERS_FILE="${TMPDIR}/token-health-headers-$$.txt"

cleanup() { rm -f "${HEADERS_FILE}"; }
trap cleanup EXIT

echo "Validating ${TOKEN_NAME}..."

# Hit the user endpoint — works for both PATs and fine-grained tokens
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
	-H "Authorization: Bearer ${GH_TOKEN}" \
	-H "Accept: application/vnd.github+json" \
	-D "${HEADERS_FILE}" \
	"${GITHUB_API}/user" 2>/dev/null) || true

# Check HTTP status
if [[ "${HTTP_CODE}" != "200" ]]; then
	echo "::error::${TOKEN_NAME} is invalid (HTTP ${HTTP_CODE}). Token may be expired, revoked, or malformed."
	echo "valid=false" >>"${GITHUB_OUTPUT}"
	exit 1
fi

echo "Token is valid (HTTP ${HTTP_CODE})."

# Read one response header, treating its absence as "not present" rather than
# as an error. Under `set -euo pipefail` a bare VAR=$(grep ...) takes the exit
# status of the substitution, so a response that omits the header would abort
# the whole check -- which is what GitHub returns for fine-grained PATs and App
# installation tokens (issue #339).
header_value() {
	grep -i "^$1:" "${HEADERS_FILE}" \
		| tail -n 1 \
		| sed "s/^[^:]*:[[:space:]]*//" \
		| tr -d '\r' || true
}

# Parse rate-limit info
RATE_REMAINING=$(header_value "x-ratelimit-remaining")
RATE_LIMIT=$(header_value "x-ratelimit-limit")
echo "Rate limit: ${RATE_REMAINING:-unknown}/${RATE_LIMIT:-unknown}"

# A non-numeric or absent value is not a threshold breach: `-lt` on one would
# itself fail the step.
if [[ "${RATE_REMAINING}" =~ ^[0-9]+$ && "${RATE_REMAINING}" -lt "${MIN_REMAINING}" ]]; then
	echo "::warning::${TOKEN_NAME} has only ${RATE_REMAINING} API requests remaining (minimum: ${MIN_REMAINING})"
fi

# Check scopes (PATs only — fine-grained tokens don't expose scopes this way)
SCOPES=$(header_value "x-oauth-scopes")
EXPIRES_AT=""

if [[ -n "${SCOPES}" ]]; then
	echo "Scopes: ${SCOPES}"

	if [[ -n "${REQUIRED_SCOPES}" ]]; then
		IFS=',' read -ra REQUIRED_ARRAY <<<"${REQUIRED_SCOPES}"
		for scope in "${REQUIRED_ARRAY[@]}"; do
			scope=$(echo "${scope}" | xargs) # trim whitespace
			if ! echo "${SCOPES}" | grep -qw "${scope}"; then
				echo "::error::${TOKEN_NAME} is missing required scope: ${scope}"
				echo "valid=false" >>"${GITHUB_OUTPUT}"
				exit 1
			fi
		done
		echo "All required scopes present."
	fi
else
	echo "No OAuth scopes header (likely a fine-grained token — skipping scope check)."
fi

# Write outputs
{
	echo "valid=true"
	echo "rate_remaining=${RATE_REMAINING:-unknown}"
	echo "expires_at=${EXPIRES_AT}"
} >>"${GITHUB_OUTPUT}"

echo "${TOKEN_NAME} health check passed."
