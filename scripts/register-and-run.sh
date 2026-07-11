#!/usr/bin/env bash
# Registers this container as an ephemeral GitHub Actions self-hosted runner
# (repo, org, or enterprise scope), runs exactly one job, then deregisters.
#
# See README.md for the full list of supported environment variables.
set -euo pipefail

GITHUB_API_URL="${GITHUB_API_URL:-https://api.github.com}"
RUNNER_HOME="/home/runner/actions-runner"
RUNNER_NAME="${RUNNER_NAME:-$(hostname)}"
RUNNER_LABELS="${RUNNER_LABELS:-}"
RUNNER_GROUP="${RUNNER_GROUP:-}"
RUNNER_SCOPE="${RUNNER_SCOPE:-}"

require_env() {
    local name="$1"
    if [[ -z "${!name:-}" ]]; then
        echo "ERROR: required environment variable '${name}' is not set." >&2
        exit 1
    fi
}

if [[ -z "${RUNNER_SCOPE}" ]]; then
    echo "ERROR: RUNNER_SCOPE must be one of: repo, org, enterprise." >&2
    exit 1
fi

case "${RUNNER_SCOPE}" in
    repo)
        require_env "REPO_URL"
        # REPO_URL like https://github.com/owner/repo
        owner_repo="${REPO_URL#https://github.com/}"
        owner_repo="${owner_repo%/}"
        registration_endpoint="${GITHUB_API_URL}/repos/${owner_repo}/actions/runners/registration-token"
        runner_url="${REPO_URL}"
        ;;
    org)
        require_env "ORG_NAME"
        registration_endpoint="${GITHUB_API_URL}/orgs/${ORG_NAME}/actions/runners/registration-token"
        runner_url="https://github.com/${ORG_NAME}"
        ;;
    enterprise)
        require_env "ENTERPRISE_NAME"
        registration_endpoint="${GITHUB_API_URL}/enterprises/${ENTERPRISE_NAME}/actions/runners/registration-token"
        runner_url="https://github.com/enterprises/${ENTERPRISE_NAME}"
        ;;
    *)
        echo "ERROR: RUNNER_SCOPE must be one of: repo, org, enterprise (got '${RUNNER_SCOPE}')." >&2
        exit 1
        ;;
esac

fetch_registration_token() {
    local installation_token
    installation_token=$(/usr/local/bin/generate-installation-token.sh)

    local response
    response=$(curl -fsSL -X POST \
        -H "Authorization: Bearer ${installation_token}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${registration_endpoint}")

    local token
    token=$(echo "${response}" | jq -r '.token // empty')
    if [[ -z "${token}" ]]; then
        echo "ERROR: failed to obtain a runner registration token:" >&2
        echo "${response}" >&2
        exit 1
    fi
    printf '%s' "${token}"
}

cd "${RUNNER_HOME}"

REG_TOKEN=$(fetch_registration_token)

config_args=(
    --url "${runner_url}"
    --token "${REG_TOKEN}"
    --name "${RUNNER_NAME}"
    --ephemeral
    --unattended
    --replace
)
[[ -n "${RUNNER_LABELS}" ]] && config_args+=(--labels "${RUNNER_LABELS}")
[[ -n "${RUNNER_GROUP}" ]] && config_args+=(--runnergroup "${RUNNER_GROUP}")

./config.sh "${config_args[@]}"

cleanup() {
    echo "Deregistering runner '${RUNNER_NAME}'..."
    local removal_token
    removal_token=$(fetch_registration_token) || {
        echo "WARNING: could not obtain a removal token; runner may show as offline until GitHub prunes it." >&2
        return 0
    }
    ./config.sh remove --token "${removal_token}" || true
}
trap cleanup EXIT INT TERM

./run.sh --once
