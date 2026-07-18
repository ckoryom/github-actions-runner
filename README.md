<div align="center">

# 🚀 podman-actions-runner

**A community-maintained, Alpine + Podman self-hosted GitHub Actions runner.**
**Small, ephemeral, GitHub App-friendly, and built for teams that want Podman instead of Docker-in-Docker.**

[![Build and Publish](https://github.com/ckoryom/podman-actions-runner/actions/workflows/build-and-publish.yml/badge.svg)](https://github.com/ckoryom/podman-actions-runner/actions/workflows/build-and-publish.yml)
[![CI](https://github.com/ckoryom/podman-actions-runner/actions/workflows/ci.yml/badge.svg)](https://github.com/ckoryom/podman-actions-runner/actions/workflows/ci.yml)
[![CodeQL](https://github.com/ckoryom/podman-actions-runner/actions/workflows/codeql.yml/badge.svg)](https://github.com/ckoryom/podman-actions-runner/actions/workflows/codeql.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Docker Hub](https://img.shields.io/badge/Docker%20Hub-ckoryom%2Fpodman--actions--runner-2496ED?logo=docker)](https://hub.docker.com/r/ckoryom/podman-actions-runner)
[![GHCR](https://img.shields.io/badge/GHCR-ghcr.io%2Fckoryom%2Fpodman--actions--runner-blue?logo=docker)](https://github.com/ckoryom/podman-actions-runner/pkgs/container/podman-actions-runner)
[![Alpine](https://img.shields.io/badge/Base-Alpine%203.23-0D597F?logo=alpinelinux)](https://alpinelinux.org/)
[![Podman](https://img.shields.io/badge/Engine-Podman-892CA0?logo=podman)](https://podman.io/)
[![Community](https://img.shields.io/badge/Contributions-Welcome-brightgreen)](CONTRIBUTING.md)

</div>

---

## ✨ What this project is

This repository ships one runner image to two registries:

- **`docker.io/ckoryom/podman-actions-runner`**
- **`ghcr.io/ckoryom/podman-actions-runner`**

It is:

- 🏔️ **Alpine-based**
- 🦭 **Podman-powered**
- 🔁 **ephemeral by default**
- 🔐 **GitHub App-ready**
- 📦 **published to Docker Hub + GHCR with semver tags**

The runner registers itself on startup, runs **exactly one job**, and removes itself when the job finishes or the container stops.

---

## 🥊 Why this is different from the competition

Most self-hosted runner images are built around **Ubuntu + Docker-in-Docker**. This one is intentionally different:

| Area | This project | Typical runner images |
| --- | --- | --- |
| Base image | **Alpine 3.23** | Usually Ubuntu/Debian |
| Container engine inside jobs | **Podman + Buildah** | Usually Docker Engine |
| Runtime model | **Daemonless engine** | Usually background `dockerd` |
| Runner lifecycle | **Ephemeral / one-job** | Often long-lived |
| Footprint | **~162 MiB local amd64 build** | Usually much heavier |
| Auth story | **Fresh tokens every start/stop** | Often PAT-only or manual token flows |

### ✅ Why Podman is a better fit here

- 🧠 **No long-lived inner Docker daemon** — Podman is daemonless, so there is less moving infrastructure inside the runner container.
- 📉 **Smaller dependency stack** — dropping the full Docker Engine stack saves a lot of weight.
- 🔒 **Cleaner security posture** — this image avoids mounting the host Docker socket and avoids a nested `dockerd` service. That does **not** make it a sandbox, but it is a simpler and smaller attack surface than classic Docker-in-Docker.
- 🧰 **Better alignment with modern Linux container tooling** — Podman + Buildah are a strong fit for Red Hat / Fedora / OpenShift-style workflows.

> **Important:** this runner still needs `--privileged` for nested container workloads. It is safer *than classic DinD in design*, but it is **not** a secure boundary for untrusted code. See [SECURITY.md](SECURITY.md).

---

## 📦 Published image and tags

The publish workflow pushes to:

```text
docker.io/ckoryom/podman-actions-runner
ghcr.io/ckoryom/podman-actions-runner
```

Recommended tags:

- `latest` — newest published release image
- `X.Y.Z` — exact release tag
- `X.Y` — rolling minor line

Examples:

```text
docker.io/ckoryom/podman-actions-runner:latest
docker.io/ckoryom/podman-actions-runner:1.4.0
docker.io/ckoryom/podman-actions-runner:1.4
ghcr.io/ckoryom/podman-actions-runner:latest
ghcr.io/ckoryom/podman-actions-runner:1.4.0
ghcr.io/ckoryom/podman-actions-runner:1.4
```

> Git release refs can still be `vX.Y.Z`; the published container tags are normalized to `X.Y.Z`.

The image is also published with OCI metadata so both registries show a clean package description, source link, and documentation link back to this repo.
The publish workflow also syncs this README to the Docker Hub repository description on each release tag publish.

### Automated releases + changelog

This repo uses `release-please` to keep `CHANGELOG.md` and version tags in sync.

- merges to `main` update/open a release PR
- merging that release PR updates `CHANGELOG.md`, creates a GitHub release, and creates a `vX.Y.Z` tag
- the tag triggers the publish workflow, which pushes `latest`, `X.Y.Z`, and `X.Y` image tags
- `release-please` uses `RELEASE_PLEASE_TOKEN` if set (recommended), otherwise `GITHUB_TOKEN`; if using `GITHUB_TOKEN`, enable **Actions > General > Workflow permissions > Allow GitHub Actions to create and approve pull requests**

The configured initial release version is `v1.0.0`.

---

## ⚡ Quick start

### 1. Create credentials

Use **one** of these:

- **GitHub App** — recommended
- **Personal Access Token** — simpler, but broader and less durable

For the GitHub App flow, see [docs/github-app-setup.md](docs/github-app-setup.md).

### 2. Run the runner

#### Recommended: GitHub App

```bash
podman run -d --privileged \
  --name gha-runner \
  --restart unless-stopped \
  -e GITHUB_APP_ID=123456 \
  -e GITHUB_APP_PRIVATE_KEY="$(cat my-app.private-key.pem)" \
  -e RUNNER_SCOPE=repo \
  -e REPO_URL=https://github.com/OWNER/REPO \
  -e RUNNER_NAME=gha-runner \
  docker.io/ckoryom/podman-actions-runner:latest
```

#### Simple: PAT

```bash
podman run -d --privileged \
  --name gha-runner \
  --restart unless-stopped \
  -e GITHUB_PAT=ghp_xxxxxxxxxxxxxxxxxxxx \
  -e RUNNER_SCOPE=repo \
  -e REPO_URL=https://github.com/OWNER/REPO \
  -e RUNNER_NAME=gha-runner \
  docker.io/ckoryom/podman-actions-runner:latest
```

### 3. Useful commands

```bash
podman logs -f gha-runner
podman ps --filter name=gha-runner
podman stop gha-runner
```

---

## 🧾 Supported environment variables

| Variable | Required | Description |
| --- | --- | --- |
| `GITHUB_PAT` | ✅ for PAT auth | Personal access token |
| `GITHUB_APP_ID` | ✅ for App auth | GitHub App ID |
| `GITHUB_APP_PRIVATE_KEY` | ✅ for App auth | PEM contents of the App private key |
| `GITHUB_APP_PRIVATE_KEY_PATH` | optional | Mounted PEM file path instead of inline contents |
| `GITHUB_APP_INSTALLATION_ID` | optional | Installation ID, auto-discovered if only one installation exists |
| `RUNNER_SCOPE` | ✅ | `repo`, `org`, or `enterprise` |
| `REPO_URL` | repo scope | `https://github.com/OWNER/REPO` |
| `ORG_NAME` | org scope | GitHub org login |
| `ENTERPRISE_NAME` | enterprise scope | GitHub enterprise slug |
| `RUNNER_NAME` | optional | Defaults to container hostname |
| `RUNNER_LABELS` | optional | Comma-separated extra labels |
| `RUNNER_GROUP` | optional | Runner group name |
| `DISABLE_PODMAN` | optional | Skip the startup Podman priming step |

---

## 🛠️ How to use this runner in workflows

This runner is best for:

- ✅ `podman build`
- ✅ `podman run`
- ✅ `buildah bud`
- ✅ `redhat-actions/buildah-build`
- ✅ `redhat-actions/push-to-registry`
- ✅ general Linux build/test/release jobs

### Recommended container build workflow

If you want to build and push container images **on this runner**, prefer the Red Hat actions:

```yaml
name: Build image with Podman toolchain

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: self-hosted

    steps:
      - uses: actions/checkout@v4

      - name: Build image
        id: build-image
        uses: redhat-actions/buildah-build@v2
        with:
          image: my-app
          tags: latest ${{ github.sha }}
          containerfiles: |
            ./Dockerfile

      - name: Push image
        uses: redhat-actions/push-to-registry@v2
        with:
          image: ${{ steps.build-image.outputs.image }}
          tags: ${{ steps.build-image.outputs.tags }}
          registry: ghcr.io/${{ github.repository_owner }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
```

`buildah` is installed in the runner image itself, so `redhat-actions/buildah-build` works without extra bootstrapping.

---

## 🚫 What will **not** work the same as Docker runners

This runner is **not** a good fit for workflows that assume a full Docker Buildx environment.

### Expect problems with:

- `docker/setup-buildx-action`
- `docker/build-push-action`
- workflows that require Docker BuildKit/buildx plugin behavior
- workflows that assume Docker daemon APIs rather than Podman/Buildah tooling

### Why

This image intentionally uses **Podman + the `podman-docker` shim**, not Docker Engine + Buildx. The `docker` CLI compatibility layer is good for many common commands, but it is **not** a drop-in replacement for advanced Docker Buildx pipelines.

### What to do instead

- Use **`redhat-actions/buildah-build`**
- Use **`redhat-actions/push-to-registry`**
- Or write direct `podman build` / `podman push` / `buildah bud` steps

If your workflow absolutely depends on Docker Buildx, this project is probably the wrong runner image for that job.

---

## 🔐 Authentication model

This image supports:

1. **GitHub App** — recommended for teams and production
2. **PAT** — simple for experiments and smaller setups

Why GitHub App is great here:

- the credential is not tied to one human
- permissions can be scoped tightly
- the runner mints a **fresh registration token every start and stop**
- no static runner registration token is ever baked into the image

See [docs/github-app-setup.md](docs/github-app-setup.md).

---

## 🧪 How the runner behaves

```text
container starts
  -> mints fresh auth token
  -> mints fresh runner registration token
  -> registers as ephemeral runner
  -> runs one job
  -> deregisters on exit
  -> container stops
```

That means:

- no stale “offline” runners piling up
- no manually managed registration tokens
- one-job blast radius

---

## 🏗️ Architectures

Published as:

- `linux/amd64`
- `linux/arm64`

For `linux/arm64` on Alpine/musl, the runner bundles `externals/node20` and
`externals/node24` from Node's unofficial musl arm64 builds so JavaScript-based
actions (for example `actions/checkout`) can start correctly.
CI smoke tests validate both `linux/amd64` and `linux/arm64` builds and verify
the runner's embedded Node runtime is executable on each.

---

## 🤝 Community project

This is a **community project**, not a huge platform team product. If this runner helps you:

- ⭐ star the repo
- 🐛 open issues when you find bugs
- 💡 suggest improvements
- 🔧 send PRs

Contributors are very welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

---

## 🛡️ Security and supply chain

Published images are:

- scanned with **Trivy**
- signed with **cosign**
- published with **SBOM + provenance**

More detail: [SECURITY.md](SECURITY.md)

---

## 📚 Repo docs

- [Changelog](CHANGELOG.md)
- [GitHub App setup guide](docs/github-app-setup.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)

---

## ❤️ Final note

If you want a **smaller**, **Podman-first**, **ephemeral**, **community-friendly** GitHub Actions runner, this repo is for you.
