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

# --- Docker-in-Docker ---------------------------------------------------------
DIND_PID=""
if [[ "${DISABLE_DIND:-false}" != "true" ]]; then
    # Default to the `vfs` storage driver for the *inner* dockerd. The outer
    # host/container filesystem is almost always already overlay2 (containerd's
    # default snapshotter), and stacking overlayfs-on-overlayfs for nested
    # Docker-in-Docker frequently fails at runtime with errors like:
    #   "failed to mount ...: fstype: overlay ... invalid argument"
    # when the inner daemon tries to prepare a container/buildkit rootfs. `vfs`
    # has no such restriction (at the cost of slower, non-CoW layer storage) and
    # is the standard, widely-documented workaround for nested DinD. Override
    # via DOCKERD_STORAGE_DRIVER if your host is verified to support nested
    # overlay2 (e.g. some modern kernels do) and you want faster builds.
    DOCKERD_STORAGE_DRIVER="${DOCKERD_STORAGE_DRIVER:-vfs}"
    log "Starting internal Docker daemon (DinD, storage-driver=${DOCKERD_STORAGE_DRIVER})..."
    dockerd --storage-driver="${DOCKERD_STORAGE_DRIVER}" >/var/log/dockerd.log 2>&1 &
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
        kill "${DIND_PID}" 2>/dev/null || true
        wait "${DIND_PID}" 2>/dev/null || true
    fi
}
trap cleanup_dind EXIT

# --- Hand off to the registration/run script -----------------------------------
# The actions/runner binaries (config.sh/run.sh) refuse to run as root, so we
# drop privileges to the non-root `runner` user for this step. `runuser` lets
# root switch users without a password prompt while preserving the environment
# (needed for GITHUB_PAT / GITHUB_APP_* / RUNNER_* / REPO_URL etc.). However,
# --preserve-environment also keeps HOME/USER/LOGNAME pointed at root's values,
# which breaks tools like git that read $HOME/.gitconfig (EACCES, since
# `runner` can't read /root). Override them to the runner user's own home
# before the handoff so everything downstream (git, npm, etc.) behaves as if
# `runner` had logged in normally. dockerd itself keeps running as root in the
# background, started above.
#
# Not using `exec` here (even though it's the entrypoint's last step) because we
# still need the EXIT trap above to stop the internal dockerd afterwards.
export HOME=/home/runner
export USER=runner
export LOGNAME=runner

set +e
runuser -u runner --preserve-environment -- /usr/local/bin/register-and-run.sh
runner_exit_code=$?
set -e
exit "${runner_exit_code}"
