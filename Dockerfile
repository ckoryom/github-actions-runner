# syntax=docker/dockerfile:1
# ---------------------------------------------------------------------------
# GitHub Actions ephemeral self-hosted runner
# Ubuntu 24.04 LTS base + Docker-in-Docker, multi-arch (linux/amd64, linux/arm64)
#
# NOTE: an Alpine-based variant was evaluated but is not viable today: the
# official actions/runner release binaries are glibc/.NET builds and fail at
# `./config.sh` on musl libc even with the gcompat shim installed
# ("Error relocating ./bin/libcoreclr.so: __isnan: symbol not found"). This is
# a known, unresolved upstream limitation (actions/runner#585). Ubuntu is the
# officially supported platform for the runner binary, so it is used here for
# correctness, security, and long-term maintainability.
# ---------------------------------------------------------------------------
ARG UBUNTU_VERSION=24.04
ARG RUNNER_VERSION=2.335.1

FROM ubuntu:${UBUNTU_VERSION}@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90

ARG RUNNER_VERSION
ARG TARGETARCH
ARG DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="github-actions-runner" \
      org.opencontainers.image.description="Ephemeral, GitHub App-authenticated self-hosted GitHub Actions runner with Docker-in-Docker, on Ubuntu 24.04 LTS (amd64/arm64)." \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/OWNER/github-actions-runner"

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8 \
    LC_ALL=C.UTF-8

# --- Base OS deps -------------------------------------------------------------
# NOTE: versions are pinned to the candidates available in the ubuntu:24.04
# image at the time of writing (see FROM digest above). If apt-get fails to
# find a pinned version after a base image bump, re-resolve versions with
# `apt-cache policy <pkg>` against the new digest and update the pins below.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash=5.2.21-2ubuntu4 \
        curl=8.5.0-2ubuntu10.11 \
        jq=1.7.1-3ubuntu0.24.04.2 \
        git=1:2.43.0-1ubuntu7.3 \
        openssh-client=1:9.6p1-3ubuntu13.16 \
        openssl=3.0.13-0ubuntu3.11 \
        ca-certificates=20260601~24.04.1 \
        tar=1.35+dfsg-3ubuntu0.2 \
        gzip=1.12-1ubuntu3.2 \
        sudo=1.9.15p5-3ubuntu5.24.04.2 \
        gnupg=2.4.4-2ubuntu17.4 \
        lsb-release=12.0-2 \
        libicu-dev=74.2-1ubuntu3.1 \
        libatomic1=14.2.0-4ubuntu2~24.04.1 \
        libstdc++6=14.2.0-4ubuntu2~24.04.1 \
        locales=2.39-0ubuntu8.7 \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# --- Docker Engine (for Docker-in-Docker) --------------------------------------
# Installs from Docker's official apt repo so amd64/arm64 are both resolved
# automatically by apt for the build platform.
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
        > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        docker-ce=5:29.6.1-1~ubuntu.24.04~noble \
        docker-ce-cli=5:29.6.1-1~ubuntu.24.04~noble \
        containerd.io=2.2.6-1~ubuntu.24.04~noble \
        docker-buildx-plugin=0.35.0-1~ubuntu.24.04~noble \
    && rm -rf /var/lib/apt/lists/*

# --- Non-root runner user ------------------------------------------------------
# actions/runner refuses to run config.sh/run.sh as root, so the registration
# and job-execution steps run as this user (entrypoint.sh switches to it via
# `runuser` after starting dockerd as root). Passwordless sudo is granted so
# workflow steps can install packages, matching common self-hosted runner
# conventions (e.g. GitHub-hosted runners also grant the runner passwordless
# sudo).
RUN groupadd docker 2>/dev/null || true \
    && useradd -m -d /home/runner -s /bin/bash runner \
    && usermod -aG docker runner \
    && echo "runner ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# --- Download the actions/runner release for the target architecture ---------
# TARGETARCH is provided automatically by `docker buildx build --platform ...`
# and maps 1:1 onto the runner's own arch naming (amd64 -> x64, arm64 -> arm64).
RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) RUNNER_ARCH="x64" ;; \
        arm64) RUNNER_ARCH="arm64" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    mkdir -p /home/runner/actions-runner; \
    curl -fsSL -o /tmp/runner.tar.gz \
        "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"; \
    tar xzf /tmp/runner.tar.gz -C /home/runner/actions-runner; \
    rm -f /tmp/runner.tar.gz; \
    /home/runner/actions-runner/bin/installdependencies.sh; \
    rm -rf /var/lib/apt/lists/*; \
    chown -R runner:runner /home/runner

WORKDIR /home/runner/actions-runner

COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=0755 scripts/generate-installation-token.sh /usr/local/bin/generate-installation-token.sh
COPY --chmod=0755 scripts/register-and-run.sh /usr/local/bin/register-and-run.sh

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD docker info >/dev/null 2>&1 && pgrep -f Runner.Listener >/dev/null 2>&1 || pgrep -f dockerd >/dev/null 2>&1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
