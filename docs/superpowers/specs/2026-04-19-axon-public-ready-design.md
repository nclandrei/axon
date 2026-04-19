# axon — Public-Ready Design

**Date:** 2026-04-19
**Status:** Approved (brainstorming). Ready for planning.

## Goal

Bring axon to the bar where it can be published as a public repo and marked "ready" with integrity. Two non-negotiable qualities:

1. **Usable first impression** — a stranger can install axon in one command, follow the README, and drive a real macOS app in under a minute.
2. **Production-trustworthy** — axon reliably drives an end-to-end macOS app verification flow, proven by an E2E test against a sample app bundled in the repo.

Target users: developers building their own new macOS apps who want AI agents (over SSH, in VMs, or locally) to verify their apps end-to-end.

## Non-goals

- Retrofitting accessibility onto closed-source third-party apps.
- Electron / Flutter / Qt support that depends on pixel/OCR fallbacks. Documented as a known limitation; no code for it at v1.
- System modal / TCC permission dialog dismissal — out of reach of AX API and brittle. Documented limitation.
- Hosted E2E in GitHub Actions. GHA hosted runners don't support nested virtualization and can't grant AX permissions cleanly. E2E is run locally by maintainers. The README does **not** mention this.
- GUI, menu bar app, auto-update (Sparkle). axon is a CLI; Homebrew handles upgrades.

## Delivery shape: three milestones

Each milestone is its own PR. Nothing is shipped publicly until M3.

### M1 — New commands

Pure library + CLI changes. Unit + integration tests per command. No repo layout changes. No user-visible surface other than new `--help` entries.

Commands added:

- **`axon doctor`** — health check.
  - Checks: `AXIsProcessTrusted()`; `CGPreflightScreenCaptureAccess()`; signature/notarization state of the running axon binary (`codesign -dv`, `spctl --assess`, informational only); Tart present (informational, for `vm-*`); Apple Silicon vs Intel (informational).
  - Output: `{ checks: [{ name, status: "ok"|"warn"|"fail", message, fix_hint }], ready: bool }`. `--format text` prints a human-readable checklist with copy-pasteable fix hints.
  - Exit 0 if every required check passes; exit 1 otherwise. Informational checks never drive the exit code.

- **`axon assert`** — explicit assertion primitive with clean non-zero exit codes. Targeting flags match `get-value` (`--identifier`, `--label`, `--path`), plus the `--sheet`/`--alert` resolver shortcuts (below). Assertion flags (any combination, AND-joined):
  - `--exists` / `--not-exists`
  - `--value <str>` (exact match on AXValue)
  - `--value-matches <regex>`
  - `--enabled` / `--disabled`
  - `--focused`
  - Exit codes: `0` pass; `1` assertion failed (structured JSON on stderr with expected vs. actual); `2` element lookup error (missing element, app not found).

- **`axon wait-ready --app <name>`** — polls until the app's AX tree has a window with at least one child and responds to `AXUIElementCopyAttributeValue` within 500 ms. Default `--timeout 10`. Replaces launch-then-sleep patterns.

- **`axon exists`** — thin lookup that always exits 0 on successful query. JSON stdout: `{ "exists": bool, "count": n }`. Takes the same targeting flags. Used by scripts that want to branch, not fail. `assert --exists` remains the version that fails hard.

- **Sheet/alert targeting sugar** — two resolver shortcuts accepted anywhere a target is accepted (click, type, assert, wait, get-value, screenshot, etc.):
  - `--sheet` targets the frontmost `AXSheet` attached to the active window.
  - `--alert` targets the frontmost `AXSheet` whose role description is "alert" or whose subrole is `AXSystemDialog`.
  - Combinable with `--label`, e.g. `axon click --app AxonSample --sheet --label "Don't Save"`.

Code organization:

- Diagnostics (`doctor`) lives in a new `Sources/AxonLib/Diagnostics.swift`.
- Assertions (`assert`, `exists`) live in a new `Sources/AxonLib/Assertions.swift`.
- `wait-ready` lives in `Actions.swift` next to the existing `wait` implementation.
- `--sheet`/`--alert` resolver logic lives in `AXHelpers.swift` alongside existing resolvers.

Testing per command:

- Unit tests in `AxonUnitTests/` covering argument parsing, JSON output shape, resolver logic, and failure modes (each new command gets a test file: `DoctorTests.swift`, `AssertionsTests.swift`, etc.).
- Integration tests in `CLIIntegrationTests.swift` covering argument validation, `--help` text, and exit codes via the built binary.

### M2 — Sample app + canonical E2E

Adds the demonstration artifact and proves the end-to-end loop.

**`Samples/AxonSample/`** — standalone SwiftUI "notes" app:

- A sidebar list of notes + an editor pane. Each note has a title and body.
- File menu: New (⌘N), Save (⌘S), Delete (⌘⌫).
- Unsaved-changes sheet on attempting to close a dirty note or quit: buttons "Save", "Don't Save", "Cancel".
- Standard command-key shortcuts: ⌘N, ⌘S, ⌘W, ⌘Q.
- Every interactive control has a stable `accessibilityIdentifier` (documented as the recommended pattern for axon-testable apps).
- Has its own `Samples/AxonSample/Package.swift`. Built to `.app` bundle via `Samples/AxonSample/Makefile` (`make build` produces `Samples/AxonSample/.build/AxonSample.app`).
- Is **not** a dependency of the `axon` executable target. The main `Package.swift` is unaffected.
- Target scope: ~200–300 lines of SwiftUI. Intended as living documentation, not a product.

**`Tests/AxonE2ETests/AxonSampleE2ETests.swift`** — the canonical E2E:

- Setup: ensure the sample app is built (`make -C Samples/AxonSample build`); launch it via `axon launch --path ...AxonSample.app`; wait-ready; confirm `axon doctor` returns `ready: true` (permissions OK).
- Scenario: create note → type title and body → verify via `axon assert --value-matches` → save via menu → create a second note → navigate sidebar → delete note → confirm deletion via unsaved-changes sheet interaction → quit with unsaved changes → dismiss sheet with "Don't Save".
- Exercises: `launch`, `wait-ready`, `tree`, `click`, `type`, `assert`, `menu`, `key` (shortcuts), `screenshot`, `--sheet` targeting, `close --quit`.
- Teardown: `axon close --quit`; `axon assert --not-exists` against the app.

**Additions to `E2ETests.swift`** — sheet/menu scenarios against TextEdit (not AxonSample):

- Trigger TextEdit's unsaved-changes sheet on close; target it with `--sheet`.
- Navigate `Format > Font > Show Fonts…` via `axon menu`; assert the font panel appears.
- Purpose: prove the sheet/menu support works on an app we don't control.

**Local-only test runner:** add `make verify` that builds release, builds the sample, runs unit + integration + E2E. Documented in `CONTRIBUTING.md`, **not** in `README.md`.

### M3 — Public surface

The ship-it milestone. After merge, the repo is ready to be made public.

**Repo files added/changed:**

- `LICENSE` — MIT. Copyright line matches the reaper pattern.
- `VERSION` — seeded `0.1.0`. Release workflow bumps patch automatically.
- `CHANGELOG.md` — seeded with `0.1.0` initial-release entry. Updated manually in each PR that lands a user-visible change (the release workflow only bumps `VERSION`; it does not touch the changelog).
- `CONTRIBUTING.md` — short: how to build, how to run `make verify`, how to add an identifier to a Mac app so axon can find it.
- `README.md` — rewritten with this structure:
  1. One-sentence positioning.
  2. **Install** — Homebrew (primary: `brew install nclandrei/tap/axon`) and direct tarball download from Releases. No "build from source" as a primary path; it remains in CONTRIBUTING.
  3. **60-second quickstart** — 5 lines that launch TextEdit, type, screenshot, quit.
  4. **Testing your own Mac app** — narrative walking through the `AxonSample` flow, linking to `Samples/AxonSample/` as the reference.
  5. Commands reference (current README section, trimmed where redundant with `--help`).
  6. Element targeting rules.
  7. Known limitations (Electron/Flutter AX emptiness; system modal / TCC dialogs out of reach).
  8. License.

**GitHub workflows:**

- `.github/workflows/ci.yml` — on PR and push to main: `macos-15` runner, `swift build`, `swift test --filter AxonUnitTests`, `swift test --filter AxonIntegrationTests`. No E2E. No CI badge in the README.

- `.github/workflows/release.yml` — on push to main (with `concurrency: release`, `cancel-in-progress: true`): modeled on `nclandrei/cicero`'s `release.yml`, adapted for a bare CLI binary.
  - Set version: bump patch in `VERSION` (matching `nclandrei/reaper` pattern — read current, increment patch, write back, commit at the end), produce timestamp tag.
  - Import Developer ID certificate from `APPLE_CERTIFICATE_P12` / `APPLE_CERTIFICATE_PASSWORD` secrets into a temp keychain.
  - `swift build -c release --arch arm64 --arch x86_64` (universal binary).
  - `codesign --force --sign "Developer ID Application: …" --options runtime --timestamp .build/release/axon`.
  - Package: `tar -czf axon-<version>-macos-universal.tar.gz -C .build/release axon`.
  - Notarize the tarball via `xcrun notarytool submit --wait` with `APPLE_ID` / `APPLE_ID_PASSWORD` / `APPLE_TEAM_ID` secrets. (CLIs inside a tar can be notarized; staple is skipped because you can't staple a bare Mach-O — notarization check happens online via Gatekeeper.)
  - Create GitHub Release with the tarball attached.
  - Clone `nclandrei/homebrew-tap` using `HOMEBREW_TAP_TOKEN`, write `Formula/axon.rb` pointing at the new release URL with SHA256, commit, push.
  - Cleanup keychain.
  - All secrets re-use the ones already configured for reaper/cicero.

**Homebrew formula** (`nclandrei/homebrew-tap/Formula/axon.rb`):

```ruby
class Axon < Formula
  desc "macOS Accessibility CLI for AI agent workflows"
  homepage "https://github.com/nclandrei/axon"
  url "https://github.com/nclandrei/axon/releases/download/vX.Y.Z/axon-X.Y.Z-macos-universal.tar.gz"
  sha256 "..."
  license "MIT"

  depends_on macos: ">= :sonoma"

  def install
    bin.install "axon"
  end

  test do
    assert_match "axon", shell_output("#{bin}/axon --version")
  end
end
```

Users install with `brew install nclandrei/tap/axon`. Users who prefer no Homebrew download the signed+notarized tarball from Releases and `chmod +x`; no Gatekeeper dance because notarization covers it.

## Architecture summary

No architectural shift. All M1 code fits the existing shape: library target `AxonLib` holds logic; `axon` target is a thin dispatch shim; unit/integration/E2E split stays as-is.

Two new source files (`Diagnostics.swift`, `Assertions.swift`) to avoid further bloating the 837-line `Actions.swift`.

`Samples/AxonSample/` is isolated by its own `Package.swift` — changes there cannot break the main build.

## Testing strategy

- **Unit (`AxonUnitTests`)** — every new command gets parsing, output-shape, and failure-mode coverage. Stays fast, no side effects, safe for background agents.
- **Integration (`AxonIntegrationTests`)** — runs the built binary against argument validation and `--help` surfaces. Safe for CI.
- **E2E (`AxonE2ETests`)** — drives real apps. Run locally only via `make verify`. Background agents must continue to use `--filter AxonUnitTests --filter AxonIntegrationTests`.

Success criterion: `make verify` is green on a fresh clone on a maintainer's Mac.

## Implementation discipline

All feature work in M1 and M2 must be implemented using red-green TDD:

1. Write a failing test that captures the desired behavior (red).
2. Write the minimum code needed to make it pass (green).
3. Refactor once green, keeping tests passing.

This applies to every new command (`doctor`, `assert`, `wait-ready`, `exists`, `--sheet`/`--alert` resolvers), every sample app behavior, and every E2E scenario. The implementation plan produced from this spec must structure each task as a red-green pair. M3 is mostly configuration (workflows, LICENSE, README) and is not subject to this discipline — but any Swift code added in M3 still is.

## Risks and mitigations

- **Notarization for a bare CLI binary.** `stapler staple` doesn't work on a bare Mach-O. Mitigation: notarize the tarball, rely on Gatekeeper's online check on first run. The signed binary plus notarization is sufficient; verified against the cicero pipeline pattern.
- **Universal binary build.** `swift build --arch arm64 --arch x86_64` may require adjustment depending on Xcode version on `macos-15` runners. Mitigation: fall back to `lipo`-combining two single-arch builds if needed.
- **`AXIsProcessTrusted()` on the CI runner.** GHA macOS runners will always return `false`. That's fine — `doctor` is tested by unit tests that mock the trust state. The command itself isn't exercised against a real trust check in CI.
- **Sample app build in E2E.** If `swift build` of the sample becomes slow or flaky, the E2E setup pays that cost every run. Mitigation: the sample app is tiny (~300 lines, no deps), build should stay sub-second. If not, cache the `.app` bundle across runs.

## Out of scope for this project

Call-outs so they don't creep in:

- No MCP server. The CLI is the interface.
- No shell completion scripts.
- No second sample app. The notes app is the only one.
- No vision/OCR integration.
- No hosted E2E in GHA.
- No renaming, repositioning, or logo work. `axon` stays `axon`.

## Terminal state

After M3 merges: tag `v0.1.0`; repo goes public; announce (channel TBD, out of scope for this spec).
