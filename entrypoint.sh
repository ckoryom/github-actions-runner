#!/usr/bin/env bash
# Container entrypoint: starts the internal Docker daemon (unless disabled),
# validates configuration, then hands off to register-and-run.sh.
set -euo pipefail

log() { echo "[entrypoint] $*"; }

fail() {
    echo "[entrypoint] ERROR: $*" >&2
    exit 1
}

# --- Basic env validation ----------------------------------------------------
[[ -n "${GITHUB_APP_ID:-}" ]] || fail "GITHUB_APP_ID is required."
if [[ -z "${GITHUB_APP_PRIVATE_KEY:-}" && -z "${GITHUB_APP_PRIVATE_KEY_PATH:-}" ]]; then
    fail "Set GITHUB_APP_PRIVATE_KEY (PEM contents) or GITHUB_APP_PRIVATE_KEY_PATH (mounted file)."
fi

case "${RUNNER_SCOPE:-}" in
    repo)       [[ -n "${REPO_URL:-}" ]]        || fail "REPO_URL is required when RUNNER_SCOPE=repo." ;;
    org)        [[ -n "${ORG_NAME:-}" ]]        || fail "ORG_NAME is required when RUNNER_SCOPE=org." ;;
    enterprise) [[ -n "${ENTERPRISE_NAME:-}" ]] || fail "ENTERPRISE_NAME is required when RUNNER_SCOPE=enterprise." ;;
    "")         fail "RUNNER_SCOPE is required: repo, org, or enterprise." ;;
    *)          fail "RUNNER_SCOPE must be one of: repo, org, enterprise (got '${RUNNER_SCOPE}')." ;;
esac

# --- Docker-in-Docker ---------------------------------------------------------
DIND_PID=""
if [[ "${DISABLE_DIND:-false}" != "true" ]]; then
    log "Starting internal Docker daemon (DinD)..."
    sudo dockerd >/var/log/dockerd.log 2>&1 &
    DIND_PID=$!

    log "Waiting for the Docker daemon to become ready..."
    for _ in $(seq 1 30); do
        if docker info >/dev/null 2>&1; then
            log "Docker daemon is ready."
            break
        fi
        sleep 1
    done

    if ! docker info >/dev/null 2>&1; then
        echo "---- dockerd log ----" >&2
        cat /var/log/dockerd.log >&2 || true
        fail "Docker daemon did not become ready in time. Ensure the container runs with --privileged (or an equivalent rootless DinD setup)."
    fi
else
    log "DISABLE_DIND=true; skipping internal Docker daemon startup (assuming a mounted host socket or none needed)."
fi

cleanup_dind() {
    if [[ -n "${DIND_PID}" ]] && kill -0 "${DIND_PID}" 2>/dev/null; then
        log "Stopping internal Docker daemon..."
        sudo kill "${DIND_PID}" 2>/dev/null || true
        wait "${DIND_PID}" 2>/dev/null || true
    fi
}
trap cleanup_dind EXIT

# --- Hand off to the registration/run script -----------------------------------
# Not using `exec` here (even though it's the entrypoint's last step) because we
# still need the EXIT trap above to stop the internal dockerd afterwards.
set +e
/usr/local/bin/register-and-run.sh
runner_exit_code=$?
set -e
exit "${runner_exit_code}"
