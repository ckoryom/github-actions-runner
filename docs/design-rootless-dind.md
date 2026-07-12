# Design note: Optional rootless Docker-in-Docker mode

## Problem

Running an isolated `dockerd` inside the runner container currently requires
`--privileged`, which grants near-root-equivalent access to the host kernel
(see the "Docker-in-Docker security note" in the README). This is the most
common security objection to this class of image, and it's the same
trade-off nearly every comparable self-hosted runner image makes today.

## Proposal

Add an opt-in rootless DinD mode, selected via a new environment variable
(e.g. `DOCKERD_ROOTLESS=true`), that runs the internal Docker daemon under
[rootless mode](https://docs.docker.com/engine/security/rootless/) instead
of requiring `--privileged`:

- Bundle `dockerd-rootless-setuptool.sh` / the `rootless-extras` package in
  the image.
- When `DOCKERD_ROOTLESS=true`, `entrypoint.sh` starts `dockerd-rootless.sh`
  as the runner user instead of the current privileged `dockerd` bootstrap.
- Document the trade-offs clearly: rootless mode has known limitations
  (no overlay2 on some kernels without `fuse-overlayfs`, some networking
  restrictions) — keep `--privileged` DinD as the default/documented path
  for maximum compatibility, and market rootless as the hardened opt-in for
  users who can accept its constraints.
- Requires validating `fuse-overlayfs` availability and possibly falling
  back to the existing `vfs` storage-driver workaround described in the
  README's "Docker-in-Docker storage driver note".

## Open questions

- Does rootless mode work reliably across the `linux/amd64` and
  `linux/arm64` targets we already publish?
- What's the performance delta vs. the current privileged + `vfs` setup?
- Should this be a separate image tag/variant, or a single image with a
  runtime switch (preferred, to avoid doubling the build/publish matrix)?

## Status

Not yet implemented — this is a design proposal for future work, scoped
separately from the README/tagging changes in this session.
