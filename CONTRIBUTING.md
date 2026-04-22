# Contributing to axon

Thanks for your interest. axon is a small, focused CLI — the contribution bar
is that changes keep it that way.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15 or later (for the bundled Swift toolchain)
- For VM commands: [Tart](https://github.com/cirruslabs/tart) on Apple Silicon
- For E2E tests: Accessibility and Screen Recording permissions granted to
  your terminal app (see [Permissions](#permissions) below)

## Build

```bash
swift build -c release
```

The binary lands at `.build/release/axon`. `make install` copies it to
`/usr/local/bin/axon`.

## Test tiers

Three suites with different blast radii:

```bash
swift test --filter AxonUnitTests         # fast, no side effects, safe anywhere
swift test --filter AxonIntegrationTests  # runs the binary, validates args + help
swift test --filter AxonE2ETests          # drives real apps, STEALS FOCUS
```

E2E tests launch TextEdit and the `AxonSample` app, click around, and close
them. Don't run them in the background — they'll fight you for the keyboard.
Background agents and CI must stick to unit + integration.

## `make verify`

The full local check:

```bash
make verify
```

This builds release, builds the sample app, and runs all three tiers in
order. Use it before opening a PR. It only runs locally — GitHub Actions runs
unit + integration only.

## Making your own app axon-testable

If you're adding axon support to a macOS app you own, the single most
important thing is: **give every interactive control a stable
`accessibilityIdentifier`**.

In SwiftUI:

```swift
Button("Save") { save() }
    .accessibilityIdentifier("saveButton")
```

In AppKit:

```swift
saveButton.setAccessibilityIdentifier("saveButton")
```

Identifiers are the first thing axon tries when resolving a target. They're
stable across localisation, theme changes, and layout tweaks — unlike labels
or tree paths. `Samples/AxonSample/` is the reference implementation.

## Permissions

axon drives apps through the macOS Accessibility API, which requires explicit
user consent:

- **Accessibility** — System Settings → Privacy & Security → Accessibility,
  add your terminal (Terminal.app, iTerm, Ghostty, etc.)
- **Screen Recording** — System Settings → Privacy & Security → Screen
  Recording, add your terminal. Required for `screenshot`.

Run `axon doctor` to verify. It prints a checklist with copy-pasteable fix
hints.

For VMs, grant these to the SSH server process (`sshd`) in the guest.

## Code organization

```
Sources/
├── axon/main.swift          CLI entry, comprehensive --help, command dispatch
└── AxonLib/
    ├── Models.swift         AXNode and Codable JSON output types
    ├── AXHelpers.swift      AXUIElement wrappers, tree walking, element finding
    ├── AppDiscovery.swift   Find running apps by name or bundle ID
    ├── Actions.swift        launch, click, type, scroll, activate, close, wait
    ├── Assertions.swift     assert and exists
    ├── Diagnostics.swift    doctor
    ├── Screenshot.swift     CGWindowListCreateImage capture
    ├── VMManager.swift      Tart VM lifecycle + ~/.axon/vms.json registry
    └── CLI.swift            Argument parser

Tests/
├── AxonUnitTests/          Pure unit tests
├── AxonIntegrationTests/   Runs the built binary, arg/help validation
└── AxonE2ETests/           Drives real apps (TextEdit + AxonSample)

Samples/
└── AxonSample/             Standalone SwiftUI notes app (its own Package.swift)
```

All logic lives in `AxonLib`. The `axon` executable target is a thin dispatch
shim — new commands should add a case to `main.swift` and put the real work in
`AxonLib`.

## Workflow

1. Open an issue first for anything larger than a small fix. axon is
   deliberately narrow; drive-by features are likely to be closed.
2. Develop with red-green TDD: write the failing test first, then the minimum
   code to pass, then refactor.
3. Every new command gets at least a unit test (arg parsing + output shape),
   an integration test (exit codes + help text), and — when it drives UI — an
   E2E scenario.
4. `make verify` green before you push.
5. Keep changes to `CHANGELOG.md` in the same PR as the user-visible change.
   The release workflow bumps `VERSION` automatically; don't touch it by
   hand.

## License

By contributing, you agree that your contributions will be licensed under the
MIT License (see [LICENSE](./LICENSE)).
