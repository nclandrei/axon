# Axon - macOS Accessibility CLI

## Build & Test

```bash
swift build -c release                    # Build release binary (needed before integration/E2E tests)
swift test                                # Run all tests
swift test --filter AxonUnitTests         # Unit tests only (fast, no side effects)
swift test --filter AxonIntegrationTests  # Integration tests (runs binary, no GUI interaction)
swift test --filter AxonE2ETests          # E2E tests (drives real apps, steals focus)
```

**Background agents must use `--filter AxonUnitTests --filter AxonIntegrationTests`** — E2E tests steal focus and show system dialogs.

## Architecture

- `Sources/AxonLib/` — Library: models, AX helpers, actions, screenshot, CLI parser, VM manager
- `Sources/axon/main.swift` — CLI entry point, help text, command dispatch
- `Tests/AxonUnitTests/` — Pure unit tests (models, parsing, key mappings)
- `Tests/AxonIntegrationTests/` — Runs the binary, tests arg validation and help text
- `Tests/AxonE2ETests/` — Drives real apps (Finder, TextEdit)

## Key Patterns

- All commands output JSON to stdout, errors to stderr
- Element targeting: `--identifier`, `--label`, `--path` (tree path)
- `resolveApp()` and `resolveElement()` handle lookup + error reporting
- No external dependencies — only Cocoa + CoreGraphics
