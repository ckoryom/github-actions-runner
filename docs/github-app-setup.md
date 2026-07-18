# Setting up a GitHub App for this runner

This image supports two authentication modes: a simple **Personal Access
Token** (`GITHUB_PAT` — see the "Authentication options" section in the main
[README.md](../README.md) for a 2-step quick start), or the **GitHub App**
flow documented in detail here. The GitHub App is recommended whenever you
want a credential that isn't tied to a personal account and can be scoped
down to just runner management.

A GitHub App issues short-lived (1 hour) installation tokens on demand, which
the entrypoint exchanges for an even shorter-lived runner registration token
**every time the container starts (and again when it shuts down, to
deregister cleanly)**. You never generate or paste a runner token yourself,
and nothing ever goes stale.

## 1. Create the GitHub App

1. Go to **Settings → Developer settings → GitHub Apps → New GitHub App**
   (for an organization: **Org Settings → Developer settings → GitHub Apps**).
2. Fill in a name and homepage URL (any placeholder URL is fine — this App
   will not receive webhooks).
3. Under **Webhook**, uncheck "Active" (not needed).
4. Under **Permissions**, grant only what your chosen scope needs:

   | Runner scope | Required permission |
   |---|---|
   | Repository (`RUNNER_SCOPE=repo`) | Repository permissions → **Administration**: Read and write |
   | Organization (`RUNNER_SCOPE=org`) | Organization permissions → **Self-hosted runners**: Read and write |
   | Enterprise (`RUNNER_SCOPE=enterprise`) | Enterprise installations support the **Self-hosted runners** permission at the enterprise level (configure via the enterprise's own GitHub App settings) |

   Only grant the permission for the scope you actually intend to use — this
   keeps the App's blast radius minimal if the private key were ever leaked.

5. Choose **"Only on this account"** (unless you intend to distribute the App).
6. Click **Create GitHub App**.

## 2. Generate a private key

On the App's settings page, scroll to **Private keys** → **Generate a private
key**. This downloads a `.pem` file — treat it like a password. This is the
value for `GITHUB_APP_PRIVATE_KEY` (paste the full file contents, including
the `-----BEGIN/END-----` lines) or mount it as a file and set
`GITHUB_APP_PRIVATE_KEY_PATH`.

Note the **App ID** shown at the top of the same page — this is
`GITHUB_APP_ID`.

## 3. Install the App

Click **Install App** in the left sidebar and install it on:
- the specific **repository** you want runners for (repo scope), or
- your **organization**, granting access to all or selected repositories (org scope), or
- your **enterprise** (enterprise scope, via enterprise-level App management).

After installing, note the **Installation ID**: it's the numeric ID in the
URL of the installation's settings page
(`.../settings/installations/<INSTALLATION_ID>`), or you can leave
`GITHUB_APP_INSTALLATION_ID` unset if the App has exactly one installation —
the entrypoint will discover it automatically via the GitHub API.

## 4. Run the container

See the Quick Start in [README.md](../README.md) and
[docker-compose.example.yml](../docker-compose.example.yml) for the full set
of environment variables. At minimum you need:

```bash
podman run --rm --privileged \
  -e GITHUB_APP_ID=123456 \
  -e GITHUB_APP_PRIVATE_KEY="$(cat my-app.private-key.pem)" \
  -e RUNNER_SCOPE=repo \
  -e REPO_URL=https://github.com/OWNER/REPO \
  docker.io/ckoryom/podman-actions-runner:latest
```

## Why this avoids the "expiring token" problem

A manually-generated runner **registration token** expires after about one
hour. If you hardcode one into a container that restarts later (e.g., after a
host reboot, or when an orchestrator recreates it), the container will fail
to register and may sit there looking "offline" until someone notices and
regenerates the token by hand.

With App authentication, the entrypoint never uses a stored registration
token — it mints a fresh installation token from your App's private key
(which does not expire and is not a broad-scope credential), then immediately
exchanges that for a brand-new registration token, every single time the
container starts or stops. There is nothing for you to rotate or babysit.

## Handling the private key securely

- Never bake the private key into the image or commit it to source control.
- Prefer a secret manager / orchestrator secret (Docker secrets, Kubernetes
  Secret, CI/CD secret store) mounted as a file, and use
  `GITHUB_APP_PRIVATE_KEY_PATH`.
- If you must pass it as an env var, ensure your orchestrator does not log
  environment variables and that the host is otherwise trusted.
