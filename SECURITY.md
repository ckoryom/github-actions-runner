# Security Policy

## Reporting a vulnerability

Please **do not** open a public issue for security vulnerabilities. Instead,
use GitHub's private reporting flow:

**Security → Advisories → [Report a vulnerability](../../security/advisories/new)**

We aim to acknowledge reports within 3 business days.

## Supported versions

Only the most recently published image tag (`latest` and the newest semver
tag) receives security fixes. Pin to a specific tag/digest in production and
upgrade regularly via the Dependabot PRs this repo generates.

## Design-level security notes (please read before deploying)

This project makes a few deliberate trade-offs. We'd rather be transparent
about them than pretend they don't exist:

### 1. `--privileged` is required for Docker-in-Docker

The default configuration runs an isolated Docker daemon *inside* the runner
container so workflow jobs can `docker build`/`docker run`. Docker's own
docs are blunt about this: `--privileged` grants the container
near-root-equivalent access to the host kernel. This is **not** a
sandboxed, defense-in-depth boundary — treat any workflow that can reach
this runner as having host-level access.

Mitigations / alternatives:
- Only point trusted repositories/workflows at this runner. Never use it as
  a runner for public-repo pull requests from forks.
- Set `DISABLE_DIND=true` and instead mount the host's Docker socket
  (`-v /var/run/docker.sock:/var/run/docker.sock`) if you already trust the
  host daemon equally — this avoids `--privileged` but shares the host's
  Docker daemon directly (also a strong trust boundary, just a different one).
- For stronger isolation, consider running this image inside a dedicated,
  disposable VM per job rather than on shared infrastructure.

### 2. Two supported auth methods — choose your trade-off

This image supports both a **Personal Access Token (PAT)** (`GITHUB_PAT`, the
simplest option) and a **GitHub App** (`GITHUB_APP_ID` + private key, the
more restrictive option). We recommend the GitHub App for anything beyond
personal/experimental use:

- A GitHub App's private key is scoped to exactly the permissions you grant
  it (e.g., only "Self-hosted runners" at the org level), is not tied to an
  individual human account, and can be rotated/revoked independently of any
  person's GitHub account. The entrypoint mints a brand-new installation
  token and registration token on every start and stop — nothing long-lived
  is ever cached inside the container or image.
- A PAT is a single credential that (for classic tokens) is often much
  broader than "manage runners," and is tied to whichever human account
  created it. If you use `GITHUB_PAT`, prefer a **fine-grained** token
  scoped only to the runner-management permission on the specific
  repo/org, and rotate it before its expiry.

Regardless of which you choose, never bake either credential into the image
or commit it to source control — pass it in at runtime via a secret store or
mounted file.

### 3. Ephemeral by design

Every runner takes exactly one job (`--ephemeral`, `run.sh --once`) and then
deregisters itself, including on `SIGTERM`/`SIGINT` (e.g., `docker stop`).
This limits the blast radius of a compromised job to a single execution and
ensures no zombie/offline runner entries accumulate in your GitHub UI.

### 4. Supply chain

Published images are:
- Built via GitHub-hosted runners directly from this repository's source
  (no third-party build infrastructure).
- Scanned with [Trivy](https://github.com/aquasecurity/trivy) for
  CRITICAL/HIGH CVEs before publishing (the publish job fails the build if
  any are found).
- Signed keylessly with [cosign](https://github.com/sigstore/cosign) via
  Sigstore/OIDC — verify with:
  ```bash
  cosign verify \
    --certificate-identity-regexp "https://github.com/OWNER/github-actions-runner/.*" \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com \
    ghcr.io/OWNER/github-actions-runner:latest
  ```
- Published with an SBOM and build provenance attestation
  ([SLSA](https://slsa.dev/)-style), viewable with
  `gh attestation verify oci://ghcr.io/OWNER/github-actions-runner:latest -o OWNER`.

## Reporting other concerns

For non-vulnerability security questions (hardening advice, threat model
discussion, etc.), feel free to open a regular GitHub issue or discussion.
