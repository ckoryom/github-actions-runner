<div align="center">

# 🐳 github-actions-runner

**An ephemeral, self-cleaning, Docker-in-Docker self-hosted GitHub Actions
runner — authenticated with a GitHub App, so no one ever babysits an
expiring token again.**

[![Build and Publish](https://github.com/OWNER/github-actions-runner/actions/workflows/build-and-publish.yml/badge.svg)](https://github.com/OWNER/github-actions-runner/actions/workflows/build-and-publish.yml)
[![CI](https://github.com/OWNER/github-actions-runner/actions/workflows/ci.yml/badge.svg)](https://github.com/OWNER/github-actions-runner/actions/workflows/ci.yml)
[![CodeQL](https://github.com/OWNER/github-actions-runner/actions/workflows/codeql.yml/badge.svg)](https://github.com/OWNER/github-actions-runner/actions/workflows/codeql.yml)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/OWNER/github-actions-runner/badge)](https://securityscorecards.dev/viewer/?uri=github.com/OWNER/github-actions-runner)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![GHCR](https://img.shields.io/badge/ghcr.io-OWNER%2Fgithub--actions--runner-blue?logo=docker)](https://github.com/OWNER/github-actions-runner/pkgs/container/github-actions-runner)
[![Platforms](https://img.shields.io/badge/platforms-linux%2Famd64%20%7C%20linux%2Farm64-informational)](#supported-architectures)
[![Base: Ubuntu 24.04 LTS](https://img.shields.io/badge/base-Ubuntu%2024.04%20LTS-E95420?logo=ubuntu&logoColor=white)](Dockerfile)
[![Docker-in-Docker](https://img.shields.io/badge/docker--in--docker-enabled-2496ED?logo=docker&logoColor=white)](docs/github-app-setup.md)
[![Ephemeral](https://img.shields.io/badge/lifecycle-ephemeral-success)](#how-registration--cleanup-works)
[![Auth: GitHub App](https://img.shields.io/badge/auth-GitHub%20App-181717?logo=github)](docs/github-app-setup.md)

</div>

---

A single Docker image that turns into a fully-configured, one-shot GitHub
Actions self-hosted runner the moment you `docker run` it — for a
**repository**, an **organization**, or an **enterprise** — and cleanly
removes itself from GitHub when the job finishes or the container stops.

## Why this exists

Manually-generated runner registration tokens expire in about an hour. Bake
one into a container and restart it later (host reboot, autoscaler,
Kubernetes rescheduling…) and it silently fails to register — or worse, you
end up with a stale "Offline" runner nobody notices until a workflow hangs.

This image sidesteps that entirely: it authenticates as a **GitHub App**,
mints a fresh installation token, exchanges it for a brand-new runner
registration token **on every start and every stop**, and never stores or
reuses a token across restarts. You configure the App once; the container
never asks you to touch a token again.

## Features

- 🔁 **Ephemeral by default** — runs exactly one job, then deregisters and
  exits. No "offline" zombie runners.
- 🔐 **GitHub App auth only** — no long-lived PAT ever stored in the
  container, image, or logs.
- 🏢 **Repo, org, and enterprise scopes** — one image, pick your scope via
  `RUNNER_SCOPE`.
- 🐋 **Docker-in-Docker built in** — jobs can `docker build`/`docker run`
  out of the box.
- 🏗️ **Multi-arch**: `linux/amd64` and `linux/arm64` published together.
- 🛡️ **Supply-chain hardened**: Trivy-scanned, cosign-signed, SBOM +
  provenance attested on every publish. See [SECURITY.md](SECURITY.md).

## Quick start

1. Create and install a GitHub App (one-time setup, ~5 minutes) — full
   walkthrough in [docs/github-app-setup.md](docs/github-app-setup.md).
2. Run the container:

```bash
docker run --rm --privileged \
  -e GITHUB_APP_ID=123456 \
  -e GITHUB_APP_PRIVATE_KEY="$(cat my-app.private-key.pem)" \
  -e RUNNER_SCOPE=repo \
  -e REPO_URL=https://github.com/OWNER/REPO \
  -e RUNNER_NAME=docker-runner-1 \
  ghcr.io/OWNER/github-actions-runner:latest
```

Or use [`docker-compose.example.yml`](docker-compose.example.yml) to run (and
scale) multiple ephemeral runners at once:

```bash
cp docker-compose.example.yml docker-compose.yml
# fill in your values, then:
docker compose up --scale runner=3
```

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `GITHUB_APP_ID` | ✅ | Your GitHub App's ID |
| `GITHUB_APP_PRIVATE_KEY` | ✅ (or the `_PATH` variant) | PEM contents of the App's private key |
| `GITHUB_APP_PRIVATE_KEY_PATH` | ✅ (or the above) | Path to a mounted PEM file, instead of passing raw contents |
| `GITHUB_APP_INSTALLATION_ID` | optional | Installation ID; auto-discovered if the App has exactly one installation |
| `RUNNER_SCOPE` | ✅ | `repo` \| `org` \| `enterprise` |
| `REPO_URL` | if `RUNNER_SCOPE=repo` | e.g. `https://github.com/OWNER/REPO` |
| `ORG_NAME` | if `RUNNER_SCOPE=org` | Organization login |
| `ENTERPRISE_NAME` | if `RUNNER_SCOPE=enterprise` | Enterprise slug |
| `RUNNER_NAME` | optional | Defaults to the container hostname |
| `RUNNER_LABELS` | optional | Comma-separated extra labels |
| `RUNNER_GROUP` | optional | Runner group name |
| `DISABLE_DIND` | optional | Set `true` to skip starting the internal Docker daemon (e.g., if you mount the host socket instead) |

## How registration & cleanup works

```
 container start
       │
       ▼
 sign a JWT with the App's private key
       │
       ▼
 exchange JWT → installation access token   (GitHub App API)
       │
       ▼
 exchange installation token → runner registration token
       │                        (repo / org / enterprise endpoint)
       ▼
 ./config.sh --ephemeral --token <reg-token>
       │
       ▼
 ./run.sh --once            ──► runs exactly one job
       │
       ▼  (also on SIGTERM/SIGINT/container stop)
 mint a fresh removal token → ./config.sh remove
       │
       ▼
 container exits — runner is gone from the GitHub UI
```

## Supported architectures

Published as a single multi-arch manifest — Docker automatically pulls the
right image for your host:

- `linux/amd64`
- `linux/arm64`

## Compatibility note

This image is built on **Ubuntu 24.04 LTS**, the officially supported
platform for the `actions/runner` binaries. An Alpine variant was evaluated
but is not currently viable: the official runner release is a glibc/.NET
build that fails at `./config.sh` on musl libc (`Error relocating
./bin/libcoreclr.so: __isnan: symbol not found`), even with the `gcompat`
shim installed — a known, unresolved upstream limitation
([actions/runner#585](https://github.com/actions/runner/issues/585)).

## Docker-in-Docker security note

Running an isolated Docker daemon inside the container requires
`--privileged`, which grants near-root-equivalent access to the host kernel.
Please read the [Security Policy](SECURITY.md) before deploying this to
untrusted workflows (e.g., public-repo fork PRs).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Issues and PRs welcome!

## License

[MIT](LICENSE)
