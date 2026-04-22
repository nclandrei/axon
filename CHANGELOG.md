# Changelog

All notable changes to axon are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-04-22

Initial public release.

### Added

- CLI commands for driving macOS apps over the Accessibility API:
  `list`, `launch`, `tree`, `click`, `double-click`, `right-click`, `hover`,
  `drag`, `type`, `set-value`, `key`, `scroll`, `screenshot`, `activate`,
  `close`, `move-resize`, `clipboard`, `menu`, `get-value`, `focused`,
  `window-info`.
- Wait primitives: `wait`, `wait-ready`, `wait-for-value`.
- Assertion primitives: `assert`, `exists`.
- Health check: `doctor`.
- Sheet/alert targeting sugar: `--sheet` and `--alert` flags accepted anywhere
  a target is accepted.
- VM lifecycle commands backed by Tart: `vm-acquire`, `vm-release`, `vm-list`,
  with a registry at `~/.axon/vms.json`.
- `Samples/AxonSample/` — a small SwiftUI notes app used as the canonical
  axon-testable reference app and driven by the E2E suite.
- Three-tier test suite: unit (`AxonUnitTests`), integration
  (`AxonIntegrationTests`), E2E (`AxonE2ETests`). `make verify` runs all three
  locally.
- Homebrew install path via `nclandrei/homebrew-tap`.
- Signed and notarized universal (arm64 + x86_64) binary distributed through
  GitHub Releases.

[0.1.0]: https://github.com/nclandrei/axon/releases/tag/v0.1.0
