#!/usr/bin/env bash
# Container entrypoint for the Podman-based Alpine variant
# (Dockerfile.alpine-podman): validates configuration, primes Podman's
# nested-container cgroup setup, then hands off to register-and-run.sh.
#
# There is no background daemon to start or wait on: Podman is daemonless, so
# `docker`/`podman` commands run and exit as regular child processes of
# whatever invokes them (a workflow step, or register-and-run.sh itself).
set -euo pipefail

log() { echo "[entrypoint] $*"; }

fail() {
    echo "[entrypoint] ERROR: $*" >&2
    exit 1
}

# --- Basic env validation ----------------------------------------------------
# Two mutually exclusive auth modes are supported:
#   1. GitHub App (recommended): GITHUB_APP_ID + GITHUB_APP_PRIVATE_KEY[_PATH]
#   2. Personal Access Token (simpler, less isolated): GITHUB_PAT
if [[ -n "${GITHUB_PAT:-}" ]]; then
    log "GITHUB_PAT provided; using Personal Access Token authentication."
    if [[ -n "${GITHUB_APP_ID:-}" ]]; then
        log "WARNING: both GITHUB_PAT and GITHUB_APP_ID are set; GITHUB_PAT takes precedence."
    fi
elif [[ -n "${GITHUB_APP_ID:-}" ]]; then
    if [[ -z "${GITHUB_APP_PRIVATE_KEY:-}" && -z "${GITHUB_APP_PRIVATE_KEY_PATH:-}" ]]; then
        fail "Set GITHUB_APP_PRIVATE_KEY (PEM contents) or GITHUB_APP_PRIVATE_KEY_PATH (mounted file)."
    fi
else
    fail "Set either GITHUB_PAT (simple) or GITHUB_APP_ID + GITHUB_APP_PRIVATE_KEY[_PATH] (recommended) for authentication."
fi

case "${RUNNER_SCOPE:-}" in
    repo)       [[ -n "${REPO_URL:-}" ]]        || fail "REPO_URL is required when RUNNER_SCOPE=repo." ;;
    org)        [[ -n "${ORG_NAME:-}" ]]        || fail "ORG_NAME is required when RUNNER_SCOPE=org." ;;
    enterprise) [[ -n "${ENTERPRISE_NAME:-}" ]] || fail "ENTERPRISE_NAME is required when RUNNER_SCOPE=enterprise." ;;
    "")         fail "RUNNER_SCOPE is required: repo, org, or enterprise." ;;
    *)          fail "RUNNER_SCOPE must be one of: repo, org, enterprise (got '${RUNNER_SCOPE}')." ;;
esac

# --- Podman-in-Docker priming --------------------------------------------------
# Podman lazily creates its `/libpod_parent` cgroup the first time any
# container is started in a fresh mount/cgroup namespace (as is the case
# here, one per runner container instance). That very first attempt reliably
# emits a cgroupfs race warning and, on some kernels, a hard failure
# ("crun: the requested cgroup controller `pids` is not available"); every
# subsequent invocation succeeds. Running one throwaway container here means
# real workflow steps never hit this — it's fully absorbed at startup, before
# the runner starts listening for jobs.
#
# Workflow steps (and register-and-run.sh) always run as the non-root
# `runner` user, which makes Podman use its rootless code path (separate
# user namespace/cgroup delegation from root's). So prime as `runner`, not
# root, to actually absorb the warning where it would otherwise occur.
if [[ "${DISABLE_PODMAN:-false}" != "true" ]]; then
    log "Priming Podman cgroup setup (one-time, absorbs a harmless first-run warning)..."
    runuser -u runner -- podman run --rm alpine:3.23 true >/var/log/podman-prime.log 2>&1 || true
else
    log "DISABLE_PODMAN=true; skipping Podman priming step."
fi

# --- Hand off to the registration/run script -----------------------------------
# The actions/runner binaries (config.sh/run.sh) refuse to run as root, so we
# drop privileges to the non-root `runner` user for this step. No EXIT
# trap/cleanup is needed here (no background daemon to stop), so we can `exec`
# straight into register-and-run.sh via runuser.
export HOME=/home/runner
export USER=runner
export LOGNAME=runner

exec runuser -u runner --preserve-environment -- /usr/local/bin/register-and-run.sh
