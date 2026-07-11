#!/usr/bin/env bash
# Generates a short-lived GitHub App installation access token.
#
# Required environment variables:
#   GITHUB_APP_ID                - GitHub App ID (numeric)
#   GITHUB_APP_PRIVATE_KEY       - PEM-encoded App private key (contents), OR
#   GITHUB_APP_PRIVATE_KEY_PATH  - path to a mounted PEM file
#
# Optional:
#   GITHUB_APP_INSTALLATION_ID   - installation ID; auto-discovered if omitted
#                                  and the App has exactly one installation.
#   GITHUB_API_URL               - defaults to https://api.github.com
#
# Prints the installation access token to stdout on success.
set -euo pipefail

GITHUB_API_URL="${GITHUB_API_URL:-https://api.github.com}"

base64url() {
    openssl base64 -A | tr '+/' '-_' | tr -d '='
}

require_env() {
    local name="$1"
    if [[ -z "${!name:-}" ]]; then
        echo "ERROR: required environment variable '${name}' is not set." >&2
        exit 1
    fi
}

require_env "GITHUB_APP_ID"

if [[ -n "${GITHUB_APP_PRIVATE_KEY_PATH:-}" ]]; then
    PRIVATE_KEY_FILE="${GITHUB_APP_PRIVATE_KEY_PATH}"
    if [[ ! -f "${PRIVATE_KEY_FILE}" ]]; then
        echo "ERROR: GITHUB_APP_PRIVATE_KEY_PATH (${PRIVATE_KEY_FILE}) does not exist." >&2
        exit 1
    fi
elif [[ -n "${GITHUB_APP_PRIVATE_KEY:-}" ]]; then
    PRIVATE_KEY_FILE="$(mktemp)"
    trap 'rm -f "${PRIVATE_KEY_FILE}"' EXIT
    printf '%s\n' "${GITHUB_APP_PRIVATE_KEY}" > "${PRIVATE_KEY_FILE}"
else
    echo "ERROR: set either GITHUB_APP_PRIVATE_KEY or GITHUB_APP_PRIVATE_KEY_PATH." >&2
    exit 1
fi

now=$(date +%s)
iat=$((now - 60))          # allow for clock drift
exp=$((now + 540))         # max allowed is 10 minutes; use 9 to be safe

header='{"alg":"RS256","typ":"JWT"}'
payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "${iat}" "${exp}" "${GITHUB_APP_ID}")

header_b64=$(printf '%s' "${header}" | base64url)
payload_b64=$(printf '%s' "${payload}" | base64url)
signing_input="${header_b64}.${payload_b64}"

signature=$(printf '%s' "${signing_input}" | openssl dgst -sha256 -sign "${PRIVATE_KEY_FILE}" | base64url)

jwt="${signing_input}.${signature}"

installation_id="${GITHUB_APP_INSTALLATION_ID:-}"
if [[ -z "${installation_id}" ]]; then
    installations=$(curl -fsSL \
        -H "Authorization: Bearer ${jwt}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${GITHUB_API_URL}/app/installations")

    count=$(echo "${installations}" | jq 'length')
    if [[ "${count}" -eq 0 ]]; then
        echo "ERROR: this GitHub App has no installations. Install it on your repo/org/enterprise first." >&2
        exit 1
    elif [[ "${count}" -gt 1 ]]; then
        echo "ERROR: multiple installations found for this App; set GITHUB_APP_INSTALLATION_ID explicitly." >&2
        echo "${installations}" | jq -r '.[] | "  id=\(.id) account=\(.account.login)"' >&2
        exit 1
    fi
    installation_id=$(echo "${installations}" | jq -r '.[0].id')
fi

response=$(curl -fsSL -X POST \
    -H "Authorization: Bearer ${jwt}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${GITHUB_API_URL}/app/installations/${installation_id}/access_tokens")

token=$(echo "${response}" | jq -r '.token // empty')
if [[ -z "${token}" ]]; then
    echo "ERROR: failed to obtain installation access token:" >&2
    echo "${response}" >&2
    exit 1
fi

printf '%s' "${token}"
