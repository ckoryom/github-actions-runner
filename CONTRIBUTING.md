# Contributing

Thanks for considering a contribution! This is a small, focused project —
here's how to get productive quickly.

## Development workflow

1. Fork and clone the repo.
2. Make your changes.
3. Validate locally before opening a PR:
   ```bash
   # Lint the Dockerfile
   docker run --rm -i hadolint/hadolint < Dockerfile

   # Lint the shell scripts
   docker run --rm -v "$PWD:/mnt" koalaman/shellcheck:stable entrypoint.sh scripts/*.sh

   # Build for your local architecture
   docker build -t github-actions-runner:dev .

   # Sanity-check the runner binary actually starts on this base image
   docker run --rm --user runner --entrypoint bash github-actions-runner:dev \
     -c "cd /home/runner/actions-runner && ./config.sh --help && ./run.sh --version"
   ```
4. Open a pull request against `main`. CI (`.github/workflows/ci.yml`) runs
   hadolint, ShellCheck, and a single-arch build/smoke-test automatically.

## Bumping the bundled `actions/runner` version

The runner version is pinned via the `RUNNER_VERSION` build arg at the top of
the `Dockerfile`. Dependabot tracks the base image and our own GitHub Actions
automatically, but it does **not** track this custom build-arg pin — please
bump it manually in a PR when a new
[actions/runner release](https://github.com/actions/runner/releases) ships,
and mention the release notes in your PR description.

## Reporting bugs / requesting features

Please open a GitHub issue with:
- The image tag/digest you're using.
- `RUNNER_SCOPE` and (redacted) environment variables in use.
- Full container logs (`docker logs <container>`), with any tokens/keys
  redacted.

## Security issues

Do not open a public issue for security vulnerabilities — see
[SECURITY.md](SECURITY.md) for the private reporting process.

## Code style

- Shell scripts: `bash`, `set -euo pipefail`, pass ShellCheck with no errors.
- Dockerfile: pass hadolint with no errors; keep layers minimal and pin
  versions via build args rather than hardcoding them inline.
