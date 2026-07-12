# patches/

## `actions-runner-musl-support.patch`

The official `actions/runner` release binaries are glibc/.NET builds and do
not run on musl (Alpine) — see the "Compatibility note" in the main
[README](../README.md). This patch adds `linux-musl-x64` /
`linux-musl-arm64` as buildable Runtime Identifiers to the `actions/runner`
*source*, so a self-contained runner binary can be compiled directly against
musl instead of relying on the prebuilt glibc release. `Dockerfile.alpine`
clones the pinned `actions/runner` tag, applies this patch, and builds the
layout with the .NET SDK's own `-alpine` image before packaging it into the
final Alpine runtime image.

What it changes, in the vendored `actions/runner` source tree:

- `src/Directory.Build.props` — adds `X64`/`ARM64` define constants for the
  `linux-musl-x64`/`linux-musl-arm64` package runtimes (mirrors the existing
  `linux-x64`/`linux-arm64` entries).
- `src/dev.sh` — allows `linux-musl-x64`/`linux-musl-arm64` as valid
  `RUNTIME_ID` values for the Linux build-platform check.
- `src/*.csproj` (Sdk, Runner.Common, Runner.Sdk, Runner.Listener,
  Runner.Worker, Runner.PluginHost, Runner.Plugins, Test) — adds
  `linux-musl-x64;linux-musl-arm64` to each project's `<RuntimeIdentifiers>`
  so `dotnet restore`/`publish` can resolve a musl target.
- `src/Misc/externals.sh` — for `linux-musl-x64`, downloads the
  Alpine-built Node tarballs (`actions/alpine_nodejs` releases — the same
  ones GitHub already ships for Alpine *job containers*) as the runner's own
  bundled `node20`/`node24`, since the runner host itself is musl here.
- `src/Misc/layoutroot/config.sh` — the stock dependency check shells out to
  `ldconfig -NXv | grep libicu` to verify ICU is installed. musl's
  `ldconfig` doesn't populate a cache the way glibc's does, so this check is
  always a false negative on Alpine even with `icu-libs` installed. The
  patch detects musl via `ldd --version` and instead confirms libicu is
  resolvable directly.

Known limitation: there is no official Alpine-built Node tarball for arm64,
so `linux-musl-arm64` currently has no bundled Node runtime for JS actions
— non-JS (composite/Docker/binary) actions and shell steps are unaffected.

Regenerate this patch after bumping `RUNNER_VERSION` by re-applying the same
changes against the new tag and re-diffing, since upstream file contents
(especially `config.sh`) may shift between releases.

## Further size trimming in `Dockerfile.alpine`

Beyond the source build itself, the final image drops two things that
turned out to be unnecessary weight (~918MB -> ~757MB):

- `gnupg` is not installed at all — it's only present in the Ubuntu image to
  import Docker's apt repo signing key; this image installs Docker via
  `apk`, so it has no purpose here.
- The bundled `node20` external (~100MB, a musl-static binary) is dropped by
  default via a builder-stage `RUN` step, controlled by the `INCLUDE_NODE20`
  build arg (default `false`). GitHub Actions already forces JS actions to
  run on Node 24 by default (confirmed via this image's own end-to-end
  test), and Node 20 is fully removed from Actions in September 2026. Build
  with `--build-arg INCLUDE_NODE20=true` if you need the legacy binary
  present for `ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION=true` during the
  transition window.
