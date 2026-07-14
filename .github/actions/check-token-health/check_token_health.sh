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

# Parse rate-limit info
RATE_REMAINING=$(grep -i "^x-ratelimit-remaining:" "${HEADERS_FILE}" | awk '{print $2}' | tr -d '\r')
RATE_LIMIT=$(grep -i "^x-ratelimit-limit:" "${HEADERS_FILE}" | awk '{print $2}' | tr -d '\r')
echo "Rate limit: ${RATE_REMAINING:-unknown}/${RATE_LIMIT:-unknown}"

if [[ -n "${RATE_REMAINING}" && "${RATE_REMAINING}" -lt "${MIN_REMAINING}" ]]; then
	echo "::warning::${TOKEN_NAME} has only ${RATE_REMAINING} API requests remaining (minimum: ${MIN_REMAINING})"
fi

# Check scopes (PATs only — fine-grained tokens don't expose scopes this way)
SCOPES=$(grep -i "^x-oauth-scopes:" "${HEADERS_FILE}" | sed 's/^x-oauth-scopes:\s*//i' | tr -d '\r')
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
