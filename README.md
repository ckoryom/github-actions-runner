<div align="center">

# 🐳 github-actions-runner

**An ephemeral, self-cleaning, Docker-in-Docker self-hosted GitHub Actions
runner. Authenticate the simple way with a PAT, or the more secure way with
a GitHub App — either way, no one ever babysits an expiring token again.**

[![Build and Publish](https://github.com/ckoryom/github-actions-runner/actions/workflows/build-and-publish.yml/badge.svg)](https://github.com/ckoryom/github-actions-runner/actions/workflows/build-and-publish.yml)
[![CI](https://github.com/ckoryom/github-actions-runner/actions/workflows/ci.yml/badge.svg)](https://github.com/ckoryom/github-actions-runner/actions/workflows/ci.yml)
[![CodeQL](https://github.com/ckoryom/github-actions-runner/actions/workflows/codeql.yml/badge.svg)](https://github.com/ckoryom/github-actions-runner/actions/workflows/codeql.yml)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/ckoryom/github-actions-runner/badge)](https://securityscorecards.dev/viewer/?uri=github.com/ckoryom/github-actions-runner)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![GHCR](https://img.shields.io/badge/ghcr.io-ckoryom%2Fgithub--actions--runner-blue?logo=docker)](https://github.com/ckoryom/github-actions-runner/pkgs/container/github-actions-runner)

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

This image sidesteps that entirely: it mints a brand-new runner registration
token **on every start and every stop**, and never stores or reuses one
across restarts. You authenticate once (either a PAT or a GitHub App); the
container never asks you to touch a runner token yourself.

## Features

- 🔁 **Ephemeral by default** — runs exactly one job, then deregisters and
  exits. No "offline" zombie runners.
- 🔐 **Two auth options** — a simple Personal Access Token, or a scoped
  GitHub App for tighter security. See [Authentication options](#authentication-options).
- 🏢 **Repo, org, and enterprise scopes** — one image, pick your scope via
  `RUNNER_SCOPE`.
- 🐋 **Docker-in-Docker built in** — jobs can `docker build`/`docker run`
  out of the box.
- 🏗️ **Multi-arch**: `linux/amd64` and `linux/arm64` published together.
- 🛡️ **Supply-chain hardened**: Trivy-scanned, cosign-signed, SBOM +
  provenance attested on every publish. See [SECURITY.md](SECURITY.md).

## What sets this apart

Plenty of self-hosted runner images exist. A few things this one does
differently, all out of the box, with no extra setup:

- **Zero standing runner tokens.** Registration tokens are minted fresh on
  every start *and* every stop, then discarded — never baked into the image,
  never reused across restarts, and never left for you to manage by hand.
- **GitHub App auth as a first-class citizen**, not an afterthought bolted
  onto a PAT-only design — scoped, key-rotatable, and documented end-to-end
  in [docs/github-app-setup.md](docs/github-app-setup.md).
- **Supply-chain verification baked into the release pipeline**: every image
  is Trivy-scanned, cosign-signed, and shipped with an SBOM and build
  provenance attestation — not an optional add-on you have to wire up
  yourself.
- **One image, three scopes.** Repository, organization, and enterprise
  registration are all supported from the same image via `RUNNER_SCOPE`,
  with no separate builds to maintain.

## Quick start

Pick **one** of the two authentication options below, then run the container.

### Option A — Personal Access Token (simplest)

1. Create a token: **Settings → Developer settings → Personal access tokens**.
   - Fine-grained token: grant **Administration: Read and write** on the
     target repository (or the equivalent organization "Self-hosted runners"
     permission for org/enterprise scope).
   - Classic token: the `repo` scope (or `admin:org` for org/enterprise scope).
2. Run it:

```bash
docker run -d --privileged \
  --name docker-runner-1 \
  --restart unless-stopped \
  -e GITHUB_PAT=ghp_xxxxxxxxxxxxxxxxxxxx \
  -e RUNNER_SCOPE=repo \
  -e REPO_URL=https://github.com/OWNER/REPO \
  -e RUNNER_NAME=docker-runner-1 \
  ghcr.io/OWNER/github-actions-runner:latest
```

### Option B — GitHub App (recommended for production)

More setup, but scoped, key-rotatable, and not tied to a personal account —
see [Authentication options](#authentication-options) below for the full
step-by-step, or the deep dive in [docs/github-app-setup.md](docs/github-app-setup.md).

```bash
docker run -d --privileged \
  --name docker-runner-1 \
  --restart unless-stopped \
  -e GITHUB_APP_ID=123456 \
  -e GITHUB_APP_PRIVATE_KEY="$(cat my-app.private-key.pem)" \
  -e RUNNER_SCOPE=repo \
  -e REPO_URL=https://github.com/OWNER/REPO \
  -e RUNNER_NAME=docker-runner-1 \
  ghcr.io/OWNER/github-actions-runner:latest
```

> **Detached mode:** `-d` runs the container in the background and returns
> your terminal immediately; `--restart unless-stopped` re-launches it (and
> re-registers, since it's ephemeral) automatically after a host reboot or
> crash. Since it's `--ephemeral`, the container exits on its own after each
> job — use an orchestrator (`docker compose`, a systemd unit, or a
> supervisor) if you want it to keep re-spawning for the next job; see
> `docker-compose.example.yml` below for a ready-made way to do that.
>
> Useful follow-up commands:
> ```bash
> docker logs -f docker-runner-1   # tail runner output
> docker ps --filter name=docker-runner-1   # check it's running
> docker stop docker-runner-1      # graceful shutdown (deregisters itself)
> ```

Or use [`docker-compose.example.yml`](docker-compose.example.yml) to run (and
scale) multiple ephemeral runners at once:

```bash
cp docker-compose.example.yml docker-compose.yml
# fill in your values, then:
docker compose up --scale runner=3
```

## Authentication options

This image supports **exactly one** of the two auth modes below per
container. If both are set, `GITHUB_PAT` wins.

### Personal Access Token (PAT) — simplest

Just generate a token and pass it in as `GITHUB_PAT`. No extra setup, no App
to create. Trade-offs to be aware of:

- **Fine-grained tokens** expire after at most 1 year — you'll need to
  rotate and update your deployment before then.
- **Classic tokens** with `repo`/`admin:org` scope can do a lot more than
  just manage runners (e.g., read/write code, admin the org) — a leak is
  more damaging than a leaked GitHub App key scoped to just runner management.
- The token is tied to **your personal GitHub account** — if you leave the
  org or lose access, runners using your PAT stop working.

This is a great option for personal projects, quick experiments, or trusted
internal environments where the simplicity is worth the trade-off.

Required env vars: `GITHUB_PAT`, `RUNNER_SCOPE`, and the matching
`REPO_URL` / `ORG_NAME` / `ENTERPRISE_NAME`.

### GitHub App — recommended for production / public use

A GitHub App's private key can be scoped to *just* "Self-hosted runners"
permissions, isn't tied to a human account, and can be rotated or revoked
independently. The entrypoint mints a fresh installation token *and* a fresh
runner registration token from it on every start and stop — nothing is ever
cached or reused.

**Step-by-step: creating the GitHub App**

1. Go to **Settings → Developer settings → GitHub Apps → New GitHub App**
   (for an org: **Org Settings → Developer settings → GitHub Apps**).
2. Give it any name and a placeholder homepage URL.
3. Under **Webhook**, uncheck "Active" — this App doesn't need webhooks.
4. Under **Permissions**, grant only what your scope needs:

   | `RUNNER_SCOPE` | Permission to grant |
   |---|---|
   | `repo` | Repository permissions → **Administration**: Read and write |
   | `org` | Organization permissions → **Self-hosted runners**: Read and write |
   | `enterprise` | **Self-hosted runners** permission via the enterprise's own App settings |

5. Choose **"Only on this account"**, then click **Create GitHub App**.
6. On the App's page, scroll to **Private keys** → **Generate a private
   key** — this downloads a `.pem` file. Note the **App ID** at the top of
   the same page.
7. Click **Install App** (left sidebar) and install it on the
   repo/org/enterprise you want runners for. Note the **Installation ID**
   from the URL (`.../installations/<ID>`) — or leave it unset if the App
   has only one installation; it's auto-discovered.
8. Run the container with `GITHUB_APP_ID`, `GITHUB_APP_PRIVATE_KEY` (or
   `GITHUB_APP_PRIVATE_KEY_PATH` for a mounted file), and optionally
   `GITHUB_APP_INSTALLATION_ID`.

For more detail (screenshots-friendly walkthrough, key-handling advice), see
[docs/github-app-setup.md](docs/github-app-setup.md).

**Why this avoids the "expiring token" problem**: a manually-generated
runner registration token expires in ~1 hour — hardcode one and restart the
container later and it silently fails. With a GitHub App, the entrypoint
never stores a registration token; it re-mints one from your (non-expiring)
private key every single time the container starts or stops.

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `GITHUB_PAT` | ✅ (Option A) — mutually exclusive with the App vars below | Personal access token used directly to request runner registration tokens |
| `GITHUB_APP_ID` | ✅ (Option B) | Your GitHub App's ID |
| `GITHUB_APP_PRIVATE_KEY` | ✅ (Option B, or the `_PATH` variant) | PEM contents of the App's private key |
| `GITHUB_APP_PRIVATE_KEY_PATH` | ✅ (Option B, or the above) | Path to a mounted PEM file, instead of passing raw contents |
| `GITHUB_APP_INSTALLATION_ID` | optional | Installation ID; auto-discovered if the App has exactly one installation |
| `RUNNER_SCOPE` | ✅ | `repo` \| `org` \| `enterprise` |
| `REPO_URL` | if `RUNNER_SCOPE=repo` | e.g. `https://github.com/OWNER/REPO` |
| `ORG_NAME` | if `RUNNER_SCOPE=org` | Organization login |
| `ENTERPRISE_NAME` | if `RUNNER_SCOPE=enterprise` | Enterprise slug |
| `RUNNER_NAME` | optional | Defaults to the container hostname |
| `RUNNER_LABELS` | optional | Comma-separated extra labels |
| `RUNNER_GROUP` | optional | Runner group name |
| `DISABLE_DIND` | optional | Set `true` to skip starting the internal Docker daemon (e.g., if you mount the host socket instead) |
| `DOCKERD_STORAGE_DRIVER` | optional | Storage driver for the internal `dockerd`. Defaults to `vfs` (see note below); override if your host is verified to support nested `overlay2` |

## How registration & cleanup works

```
 container start
       │
       ▼
 GITHUB_PAT set? ──yes──► use it directly as the bearer token
       │no
       ▼
 sign a JWT with the App's private key
       │
       ▼
 exchange JWT → installation access token   (GitHub App API)
       │
       ▼
 exchange bearer token → runner registration token
       │                  (repo / org / enterprise endpoint)
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

## Image tags

Every publish to `ghcr.io/ckoryom/github-actions-runner` produces several tags
at once, so you can pin to whatever level of stability you need:

| Tag | Example | Meaning |
| --- | --- | --- |
| `latest` | `latest` | Most recent build from the default branch. |
| `{{version}}` | `1.4.0` | Full semantic version, from a `vX.Y.Z` git tag. |
| `{{major}}.{{minor}}` | `1.4` | Rolling minor version — updates with patch releases. |
| `runner-<version>` | `runner-2.335.1` | The exact baked-in `actions/runner` version, independent of this image's own release cadence — use this if you need to pin to a specific runner build regardless of image version. |
| short SHA | `sha-abc1234` | The exact commit the image was built from. |

Use semver tags for general use, `runner-<version>` when you need a specific
`actions/runner` release, and the short SHA for fully reproducible pins.

## Compatibility note

This image is built on **Ubuntu 24.04 LTS**. The official `actions/runner`
*release* binary is a glibc/.NET build and fails at `./config.sh` on musl
libc (`Error relocating ./bin/libcoreclr.so: __isnan: symbol not found`),
even with the `gcompat` shim installed — a known, unresolved upstream
limitation ([actions/runner#585](https://github.com/actions/runner/issues/585)).

An experimental **Alpine variant** (`Dockerfile.alpine`) is now available
that works around this by compiling `actions/runner` from source targeting
the `linux-musl-x64`/`linux-musl-arm64` .NET Runtime Identifiers instead of
using the prebuilt glibc release — `.NET` officially supports musl
self-contained builds (see Microsoft's own `dotnet/runtime:*-alpine`
images), the stock `actions/runner` build scripts just don't expose that RID
by default. See `patches/README.md` for exactly what's patched. This has
been verified end-to-end: registering as an ephemeral runner, running
`actions/checkout@v4` (a JS action, via the bundled Alpine Node build), a
shell step, and a nested `docker build` all succeed on Alpine with no
glibc/gcompat shim required.

### Image size comparison

| Image | Base | Size | Notes |
| --- | --- | --- | --- |
| `Dockerfile` | Ubuntu 24.04 | ~1.81 GB | Official, fully supported `actions/runner` release binary. |
| `Dockerfile.alpine` | Alpine 3.20 | ~918 MB (**~49% smaller**) | Source-built musl runner (this repo's patch); experimental. |
| *(bonus, not shipped)* | Chainguard Wolfi | ~1.12 GB | glibc-based, stock official release binary, no patching needed — a smaller-than-Ubuntu fallback if the Alpine/musl approach is ever reverted. |

Trade-off: the Alpine image requires building `actions/runner` from source
against a project-maintained patch, which is a new build/maintenance burden
(the patch must be re-verified on every `RUNNER_VERSION` bump). Ubuntu
remains the default/primary image for correctness and long-term
maintainability; Alpine is offered as a smaller, opt-in alternative.

## Docker-in-Docker security note

Running an isolated Docker daemon inside the container requires
`--privileged`, which grants near-root-equivalent access to the host kernel.
Please read the [Security Policy](SECURITY.md) before deploying this to
untrusted workflows (e.g., public-repo fork PRs).

## Docker-in-Docker storage driver note

The internal `dockerd` defaults to the `vfs` storage driver instead of
`overlay2`. Nested Docker-in-Docker almost always runs on top of a host
filesystem that is itself `overlay2` (containerd's default snapshotter), and
stacking `overlay2` on `overlay2` frequently fails at runtime — e.g. build
steps using `docker/setup-buildx-action` or plain `docker build` can fail
with errors like `failed to mount ...: fstype: overlay ... invalid
argument`. `vfs` avoids this entirely and is the standard, widely-documented
workaround for nested DinD, at the cost of slower, non-copy-on-write layer
storage. If you've verified your specific host/kernel supports nested
`overlay2`, you can opt back in with `-e DOCKERD_STORAGE_DRIVER=overlay2`
for faster builds.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Issues and PRs welcome!

## License

[MIT](LICENSE)
