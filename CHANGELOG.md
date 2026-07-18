# Changelog

## [1.0.1](https://github.com/ckoryom/podman-actions-runner/compare/v1.0.0...v1.0.1) (2026-07-18)


### Bug Fixes

* checkout step failing with EACCES on /root/.gitconfig ([c601f75](https://github.com/ckoryom/podman-actions-runner/commit/c601f7513425a2d20bfce97de7fa5a218921b080))
* nested Docker-in-Docker fails to mount overlay for build/buildx containers ([c17e266](https://github.com/ckoryom/podman-actions-runner/commit/c17e266242f65851250fed219b98d2a1a5bbb025))
* pnpm/action-setup fails with missing libatomic.so.1 ([6074292](https://github.com/ckoryom/podman-actions-runner/commit/607429280736bde57ba18b682b7d76023ae7e3ec))
* runner refused to start because entrypoint ran config.sh/run.sh as root ([5ca0eaa](https://github.com/ckoryom/podman-actions-runner/commit/5ca0eaa62e034a30497c4d15df8e25b50dcbf625))

## Changelog

All notable changes to this project will be documented in this file.

This project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
