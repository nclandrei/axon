# M1 — New Commands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add five new CLI capabilities to axon — `doctor`, `assert`, `exists`, `wait-ready`, and `--sheet`/`--alert` resolver shortcuts — each implemented via strict red-green TDD.

**Architecture:** Two new Swift files in `Sources/AxonLib/` (`Diagnostics.swift`, `Assertions.swift`). One new function in `Actions.swift` (`performWaitReady`). Extension of `ElementSelector` in `AXHelpers.swift` with `.sheet` and `.alert` cases. New output models in `Models.swift`. CLI wiring + help text in `Sources/axon/main.swift`. Unit tests in `Tests/AxonUnitTests/`, integration tests appended to `Tests/AxonIntegrationTests/CLIIntegrationTests.swift`.

**Tech Stack:** Swift 5.9, XCTest, AXUIElement / ApplicationServices, CoreGraphics. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-04-19-axon-public-ready-design.md` (M1 section).

**TDD discipline:** Every task is a red-green-refactor cycle. Never write production code without a failing test. Each task ends with a commit. If a test cannot be written (e.g. it requires a real UI), write a test that exercises the pure part of the logic and note the gap explicitly in the commit message.

---

## File Structure

**New files created in this plan:**

- `Sources/AxonLib/Diagnostics.swift` — `runDoctor()` plus the per-check helpers. One responsibility: diagnose local machine state.
- `Sources/AxonLib/Assertions.swift` — `performAssert()` and `performExists()`. One responsibility: evaluate assertions against AXUIElements.
- `Tests/AxonUnitTests/DiagnosticsTests.swift` — unit tests for `Diagnostics.swift`.
- `Tests/AxonUnitTests/AssertionsTests.swift` — unit tests for `Assertions.swift`.
- `Tests/AxonUnitTests/SheetResolverTests.swift` — unit tests for the `.sheet`/`.alert` selector cases.

**Modified files:**

- `Sources/AxonLib/Models.swift` — add `DoctorOutput`, `DoctorCheck`, `DoctorStatus`, `AssertOutput`, `AssertFailure`, `ExistsOutput`, `WaitReadyOutput` at the bottom of the Command Output Models section.
- `Sources/AxonLib/AXHelpers.swift` — extend `ElementSelector` with `.sheet` and `.alert` cases; extend `findElement` with dispatch for the new cases; add private `findFrontmostSheet` / `findFrontmostAlert` helpers.
- `Sources/AxonLib/AppDiscovery.swift` — `resolveElement` signature accepts new `sheet: Bool`, `alert: Bool`, optional `labelForSheet: String?` parameters to compose sheet/alert + label.
- `Sources/AxonLib/Actions.swift` — append `performWaitReady(appElement:timeout:) -> Int?` at the bottom of the file.
- `Sources/axon/main.swift` — add help text blocks `helpDoctor`, `helpAssert`, `helpExists`, `helpWaitReady`; wire them into `showHelp`; add `case "doctor"`, `case "assert"`, `case "exists"`, `case "wait-ready"` in the dispatch switch; update `helpMain` to list the new commands and the `--sheet`/`--alert` flags.
- `Tests/AxonUnitTests/ActionsTests.swift` — append wait-ready unit tests.
- `Tests/AxonIntegrationTests/CLIIntegrationTests.swift` — append integration tests for the new commands and new help-text entries.

**Invariant:** No existing tests should break. Run `swift test --filter AxonUnitTests --filter AxonIntegrationTests` at the end of every task and expect all-green (including pre-existing tests).

**Build discipline:** Integration tests require a fresh release build. Always run `swift build -c release` before `swift test --filter AxonIntegrationTests`.

---

## Task 1: Add output models for `doctor`

**Files:**
- Modify: `Sources/AxonLib/Models.swift` (append new types near the other Command Output Models, before the "Error Output" section around line 595)
- Test: `Tests/AxonUnitTests/ModelsTests.swift` (append)

- [ ] **Step 1: Write the failing test**

Append to `Tests/AxonUnitTests/ModelsTests.swift`:

```swift
// MARK: - DoctorOutput tests

func testDoctorCheckEncoding() throws {
    let check = DoctorCheck(
        name: "accessibility",
        status: .ok,
        message: "AX trust granted",
        fix_hint: nil
    )
    let data = try jsonEncoder.encode(check)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["name"] as? String, "accessibility")
    XCTAssertEqual(json["status"] as? String, "ok")
    XCTAssertEqual(json["message"] as? String, "AX trust granted")
    XCTAssertNil(json["fix_hint"])
}

func testDoctorCheckEncodingWithFixHint() throws {
    let check = DoctorCheck(
        name: "accessibility",
        status: .fail,
        message: "Not granted",
        fix_hint: "Enable in System Settings"
    )
    let data = try jsonEncoder.encode(check)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["status"] as? String, "fail")
    XCTAssertEqual(json["fix_hint"] as? String, "Enable in System Settings")
}

func testDoctorOutputEncoding() throws {
    let output = DoctorOutput(
        ready: false,
        checks: [
            DoctorCheck(name: "a", status: .ok, message: "ok", fix_hint: nil),
            DoctorCheck(name: "b", status: .fail, message: "no", fix_hint: "fix it"),
        ]
    )
    let data = try jsonEncoder.encode(output)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["ready"] as? Bool, false)
    let checks = json["checks"] as! [[String: Any]]
    XCTAssertEqual(checks.count, 2)
}

func testDoctorStatusRawValues() {
    XCTAssertEqual(DoctorStatus.ok.rawValue, "ok")
    XCTAssertEqual(DoctorStatus.warn.rawValue, "warn")
    XCTAssertEqual(DoctorStatus.fail.rawValue, "fail")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AxonUnitTests/ModelsTests/testDoctorCheckEncoding`
Expected: FAIL with "Cannot find 'DoctorCheck' in scope" (compile error).

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/AxonLib/Models.swift` just before the `// MARK: - Error Output` section:

```swift
// MARK: - Doctor Output

public enum DoctorStatus: String, Codable {
    case ok
    case warn
    case fail
}

public struct DoctorCheck: Codable {
    public let name: String
    public let status: DoctorStatus
    public let message: String
    public let fix_hint: String?

    public init(name: String, status: DoctorStatus, message: String, fix_hint: String?) {
        self.name = name
        self.status = status
        self.message = message
        self.fix_hint = fix_hint
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(status, forKey: .status)
        try c.encode(message, forKey: .message)
        if let fix_hint = fix_hint { try c.encode(fix_hint, forKey: .fix_hint) }
    }

    enum CodingKeys: String, CodingKey {
        case name, status, message, fix_hint
    }
}

public struct DoctorOutput: Codable {
    public let ready: Bool
    public let checks: [DoctorCheck]

    public init(ready: Bool, checks: [DoctorCheck]) {
        self.ready = ready
        self.checks = checks
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter AxonUnitTests/ModelsTests`
Expected: PASS (including the 4 new tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AxonLib/Models.swift Tests/AxonUnitTests/ModelsTests.swift
git commit -m "Add DoctorOutput/DoctorCheck/DoctorStatus models"
```

---

## Task 2: Doctor — AX trust check (core logic)

**Files:**
- Create: `Sources/AxonLib/Diagnostics.swift`
- Create: `Tests/AxonUnitTests/DiagnosticsTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/AxonUnitTests/DiagnosticsTests.swift`:

```swift
import XCTest
@testable import AxonLib

final class DiagnosticsTests: XCTestCase {

    // MARK: - AX trust check

    func testRunDoctorIncludesAccessibilityCheck() {
        let output = runDoctor(axTrusted: false, screenCaptureGranted: false, isAppleSilicon: true, tartInstalled: false, binarySignatureInfo: nil)
        XCTAssertTrue(output.checks.contains { $0.name == "accessibility" })
    }

    func testAccessibilityCheckFailsWhenUntrusted() {
        let output = runDoctor(axTrusted: false, screenCaptureGranted: true, isAppleSilicon: true, tartInstalled: true, binarySignatureInfo: nil)
        let ax = output.checks.first(where: { $0.name == "accessibility" })
        XCTAssertEqual(ax?.status, .fail)
        XCTAssertNotNil(ax?.fix_hint)
        XCTAssertTrue(ax?.fix_hint?.contains("Privacy & Security") ?? false)
    }

    func testAccessibilityCheckPassesWhenTrusted() {
        let output = runDoctor(axTrusted: true, screenCaptureGranted: true, isAppleSilicon: true, tartInstalled: true, binarySignatureInfo: nil)
        let ax = output.checks.first(where: { $0.name == "accessibility" })
        XCTAssertEqual(ax?.status, .ok)
        XCTAssertNil(ax?.fix_hint)
    }

    func testReadyIsFalseWhenAnyRequiredCheckFails() {
        let output = runDoctor(axTrusted: false, screenCaptureGranted: true, isAppleSilicon: true, tartInstalled: true, binarySignatureInfo: nil)
        XCTAssertFalse(output.ready)
    }

    func testReadyIsTrueWhenAllRequiredPass() {
        let output = runDoctor(axTrusted: true, screenCaptureGranted: true, isAppleSilicon: true, tartInstalled: true, binarySignatureInfo: nil)
        XCTAssertTrue(output.ready)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AxonUnitTests/DiagnosticsTests`
Expected: FAIL — "Cannot find 'runDoctor' in scope".

- [ ] **Step 3: Write minimal implementation**

Create `Sources/AxonLib/Diagnostics.swift`:

```swift
import Foundation
import ApplicationServices
import CoreGraphics

/// Pure, dependency-injected doctor runner. The real entrypoint
/// (`runDoctorLive()`) gathers machine state and calls this.
///
/// `axTrusted`, `screenCaptureGranted`, `isAppleSilicon`, `tartInstalled` are
/// the raw facts we observe. `binarySignatureInfo` is the one-line output of
/// `codesign -dv` or nil if unavailable — informational.
public func runDoctor(
    axTrusted: Bool,
    screenCaptureGranted: Bool,
    isAppleSilicon: Bool,
    tartInstalled: Bool,
    binarySignatureInfo: String?
) -> DoctorOutput {
    var checks: [DoctorCheck] = []

    // Required: AX trust
    if axTrusted {
        checks.append(DoctorCheck(
            name: "accessibility",
            status: .ok,
            message: "axon is trusted for accessibility",
            fix_hint: nil
        ))
    } else {
        checks.append(DoctorCheck(
            name: "accessibility",
            status: .fail,
            message: "axon is not trusted for accessibility",
            fix_hint: "Open System Settings > Privacy & Security > Accessibility and enable your terminal (or axon)."
        ))
    }

    let ready = checks.allSatisfy { $0.status != .fail }
    return DoctorOutput(ready: ready, checks: checks)
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter AxonUnitTests/DiagnosticsTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AxonLib/Diagnostics.swift Tests/AxonUnitTests/DiagnosticsTests.swift
git commit -m "Add runDoctor with AX trust check"
```

---

## Task 3: Doctor — screen recording check

**Files:**
- Modify: `Sources/AxonLib/Diagnostics.swift`
- Modify: `Tests/AxonUnitTests/DiagnosticsTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `DiagnosticsTests.swift`, inside the class:

```swift
// MARK: - Screen recording check

func testScreenRecordingCheckIncluded() {
    let output = runDoctor(axTrusted: true, screenCaptureGranted: true, isAppleSilicon: true, tartInstalled: true, binarySignatureInfo: nil)
    XCTAssertTrue(output.checks.contains { $0.name == "screen_recording" })
}

func testScreenRecordingCheckFailsWhenNotGranted() {
    let output = runDoctor(axTrusted: true, screenCaptureGranted: false, isAppleSilicon: true, tartInstalled: true, binarySignatureInfo: nil)
    let sr = output.checks.first(where: { $0.name == "screen_recording" })
    XCTAssertEqual(sr?.status, .fail)
    XCTAssertTrue(sr?.fix_hint?.contains("Screen") ?? false)
}

func testScreenRecordingCheckPassesWhenGranted() {
    let output = runDoctor(axTrusted: true, screenCaptureGranted: true, isAppleSilicon: true, tartInstalled: true, binarySignatureInfo: nil)
    let sr = output.checks.first(where: { $0.name == "screen_recording" })
    XCTAssertEqual(sr?.status, .ok)
}

func testReadyFalseWhenScreenRecordingMissing() {
    let output = runDoctor(axTrusted: true, screenCaptureGranted: false, isAppleSilicon: true, tartInstalled: true, binarySignatureInfo: nil)
    XCTAssertFalse(output.ready)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AxonUnitTests/DiagnosticsTests`
Expected: 4 failures — the new tests fail because no `screen_recording` check exists.

- [ ] **Step 3: Write minimal implementation**

Edit `Diagnostics.swift` — add the screen recording check after the AX trust check, before the `ready` calculation:

```swift
    // Required: screen recording (needed for `axon screenshot`)
    if screenCaptureGranted {
        checks.append(DoctorCheck(
            name: "screen_recording",
            status: .ok,
            message: "Screen recording permission granted",
            fix_hint: nil
        ))
    } else {
        checks.append(DoctorCheck(
            name: "screen_recording",
            status: .fail,
            message: "Screen recording permission not granted",
            fix_hint: "Open System Settings > Privacy & Security > Screen Recording and enable your terminal (or axon)."
        ))
    }
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter AxonUnitTests/DiagnosticsTests`
Expected: PASS (all 9 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AxonLib/Diagnostics.swift Tests/AxonUnitTests/DiagnosticsTests.swift
git commit -m "Add screen recording check to doctor"
```

---

## Task 4: Doctor — informational checks (architecture, Tart, signature)

**Files:**
- Modify: `Sources/AxonLib/Diagnostics.swift`
- Modify: `Tests/AxonUnitTests/DiagnosticsTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `DiagnosticsTests.swift`:

```swift
// MARK: - Informational checks

func testArchitectureCheckIncluded() {
    let output = runDoctor(axTrusted: true, screenCaptureGranted: true, isAppleSilicon: true, tartInstalled: true, binarySignatureInfo: nil)
    let arch = output.checks.first(where: { $0.name == "architecture" })
    XCTAssertNotNil(arch)
    XCTAssertEqual(arch?.status, .ok)
    XCTAssertTrue(arch?.message.contains("Apple Silicon") ?? false)
}

func testArchitectureCheckOnIntel() {
    let output = runDoctor(axTrusted: true, screenCaptureGranted: true, isAppleSilicon: false, tartInstalled: true, binarySignatureInfo: nil)
    let arch = output.checks.first(where: { $0.name == "architecture" })
    XCTAssertEqual(arch?.status, .warn)
    XCTAssertTrue(arch?.message.contains("Intel") ?? false)
}

func testTartCheckWhenPresent() {
    let output = runDoctor(axTrusted: true, screenCaptureGranted: true, isAppleSilicon: true, tartInstalled: true, binarySignatureInfo: nil)
    let tart = output.checks.first(where: { $0.name == "tart" })
    XCTAssertEqual(tart?.status, .ok)
}

func testTartCheckWhenAbsent() {
    let output = runDoctor(axTrusted: true, screenCaptureGranted: true, isAppleSilicon: true, tartInstalled: false, binarySignatureInfo: nil)
    let tart = output.checks.first(where: { $0.name == "tart" })
    XCTAssertEqual(tart?.status, .warn)
    XCTAssertTrue(tart?.fix_hint?.contains("tart") ?? false)
}

func testBinarySignatureCheckWhenPresent() {
    let output = runDoctor(axTrusted: true, screenCaptureGranted: true, isAppleSilicon: true, tartInstalled: true, binarySignatureInfo: "Authority=Developer ID Application: X")
    let sig = output.checks.first(where: { $0.name == "binary_signature" })
    XCTAssertEqual(sig?.status, .ok)
    XCTAssertTrue(sig?.message.contains("Developer ID") ?? false)
}

func testBinarySignatureCheckWhenAbsent() {
    let output = runDoctor(axTrusted: true, screenCaptureGranted: true, isAppleSilicon: true, tartInstalled: true, binarySignatureInfo: nil)
    let sig = output.checks.first(where: { $0.name == "binary_signature" })
    XCTAssertEqual(sig?.status, .warn)
}

func testInformationalWarnDoesNotAffectReady() {
    let output = runDoctor(axTrusted: true, screenCaptureGranted: true, isAppleSilicon: false, tartInstalled: false, binarySignatureInfo: nil)
    XCTAssertTrue(output.ready, "ready should be true when only informational checks warn")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AxonUnitTests/DiagnosticsTests`
Expected: 7 failures for missing architecture/tart/binary_signature checks.

- [ ] **Step 3: Write minimal implementation**

Edit `Diagnostics.swift` — add between the screen recording block and the `ready` calculation:

```swift
    // Informational: architecture
    if isAppleSilicon {
        checks.append(DoctorCheck(
            name: "architecture",
            status: .ok,
            message: "Apple Silicon (arm64)",
            fix_hint: nil
        ))
    } else {
        checks.append(DoctorCheck(
            name: "architecture",
            status: .warn,
            message: "Intel (x86_64). Tart VMs require Apple Silicon.",
            fix_hint: nil
        ))
    }

    // Informational: Tart presence (required only for vm-* commands)
    if tartInstalled {
        checks.append(DoctorCheck(
            name: "tart",
            status: .ok,
            message: "Tart CLI found",
            fix_hint: nil
        ))
    } else {
        checks.append(DoctorCheck(
            name: "tart",
            status: .warn,
            message: "Tart not installed (only needed for vm-* commands)",
            fix_hint: "brew install cirruslabs/cli/tart"
        ))
    }

    // Informational: binary signature
    if let info = binarySignatureInfo, info.contains("Developer ID") {
        checks.append(DoctorCheck(
            name: "binary_signature",
            status: .ok,
            message: "axon binary signed with Developer ID (\(info))",
            fix_hint: nil
        ))
    } else {
        checks.append(DoctorCheck(
            name: "binary_signature",
            status: .warn,
            message: "axon binary is unsigned or signature unreadable",
            fix_hint: nil
        ))
    }
```

Then replace the existing `ready` calculation at the bottom with:

```swift
    // Ready = no required checks failed. "warn" is informational and never affects ready.
    let ready = !checks.contains(where: { $0.status == .fail })
    return DoctorOutput(ready: ready, checks: checks)
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter AxonUnitTests/DiagnosticsTests`
Expected: PASS (16 tests total).

- [ ] **Step 5: Commit**

```bash
git add Sources/AxonLib/Diagnostics.swift Tests/AxonUnitTests/DiagnosticsTests.swift
git commit -m "Add informational checks (arch, tart, binary signature) to doctor"
```

---

## Task 5: Doctor — live probe wrapper

**Files:**
- Modify: `Sources/AxonLib/Diagnostics.swift`

- [ ] **Step 1: Write the failing test**

Append to `DiagnosticsTests.swift`:

```swift
// MARK: - Live probe

func testRunDoctorLiveReturnsWellFormedOutput() {
    let output = runDoctorLive()
    XCTAssertFalse(output.checks.isEmpty)
    let names = Set(output.checks.map(\.name))
    XCTAssertTrue(names.contains("accessibility"))
    XCTAssertTrue(names.contains("screen_recording"))
    XCTAssertTrue(names.contains("architecture"))
    XCTAssertTrue(names.contains("tart"))
    XCTAssertTrue(names.contains("binary_signature"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AxonUnitTests/DiagnosticsTests/testRunDoctorLiveReturnsWellFormedOutput`
Expected: FAIL — "Cannot find 'runDoctorLive' in scope".

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/AxonLib/Diagnostics.swift`:

```swift
/// Live entrypoint used by `axon doctor`. Probes actual system state and delegates to `runDoctor`.
public func runDoctorLive() -> DoctorOutput {
    return runDoctor(
        axTrusted: AXIsProcessTrusted(),
        screenCaptureGranted: CGPreflightScreenCaptureAccess(),
        isAppleSilicon: isAppleSiliconArchitecture(),
        tartInstalled: isTartOnPath(),
        binarySignatureInfo: binarySignatureOfRunningProcess()
    )
}

private func isAppleSiliconArchitecture() -> Bool {
    #if arch(arm64)
    return true
    #else
    return false
    #endif
}

private func isTartOnPath() -> Bool {
    let task = Process()
    task.launchPath = "/usr/bin/env"
    task.arguments = ["which", "tart"]
    task.standardOutput = Pipe()
    task.standardError = Pipe()
    do {
        try task.run()
    } catch {
        return false
    }
    task.waitUntilExit()
    return task.terminationStatus == 0
}

private func binarySignatureOfRunningProcess() -> String? {
    guard let path = Bundle.main.executablePath ?? CommandLine.arguments.first else { return nil }
    let task = Process()
    task.launchPath = "/usr/bin/codesign"
    task.arguments = ["-dvv", path]
    let err = Pipe()
    task.standardError = err
    task.standardOutput = Pipe()
    do {
        try task.run()
    } catch {
        return nil
    }
    task.waitUntilExit()
    guard task.terminationStatus == 0 else { return nil }
    let data = err.fileHandleForReading.readDataToEndOfFile()
    guard let text = String(data: data, encoding: .utf8) else { return nil }
    // Return the first "Authority=" line if present.
    return text
        .split(separator: "\n")
        .first(where: { $0.hasPrefix("Authority=") })
        .map(String.init)
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter AxonUnitTests/DiagnosticsTests`
Expected: PASS (17 tests). Note: `runDoctorLive` exercises real system calls; the test only asserts shape, not values, so it will pass whether or not AX is granted on the test runner.

- [ ] **Step 5: Commit**

```bash
git add Sources/AxonLib/Diagnostics.swift Tests/AxonUnitTests/DiagnosticsTests.swift
git commit -m "Add runDoctorLive probe wrapping runDoctor"
```

---

## Task 6: Doctor — CLI wiring and integration

**Files:**
- Modify: `Sources/axon/main.swift`
- Modify: `Tests/AxonIntegrationTests/CLIIntegrationTests.swift`

- [ ] **Step 1: Write the failing integration test**

Append to `CLIIntegrationTests.swift` inside the class:

```swift
// MARK: - doctor

func testDoctorEmitsJSONWithChecks() {
    let result = runAxon(["doctor"])
    // Exit code depends on runtime AX state; accept 0 or 1
    XCTAssertTrue(result.exitCode == 0 || result.exitCode == 1, "doctor should exit 0 or 1, got \(result.exitCode)")
    let json = parseJSON(result.stdout)
    XCTAssertNotNil(json, "doctor stdout should be valid JSON")
    XCTAssertNotNil(json?["checks"])
    XCTAssertNotNil(json?["ready"])
}

func testDoctorHelp() {
    let result = runAxon(["doctor", "--help"])
    XCTAssertEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("axon doctor"))
}

func testMainHelpListsDoctor() {
    let result = runAxon(["--help"])
    XCTAssertEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("doctor"), "main --help should list doctor")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift build -c release && swift test --filter AxonIntegrationTests/CLIIntegrationTests/testDoctorEmitsJSONWithChecks`
Expected: FAIL — "Unknown command 'doctor'".

- [ ] **Step 3: Write minimal implementation**

Edit `Sources/axon/main.swift`:

3a. Add a `helpDoctor` constant near the other help constants (search for `let helpGetValue =` and add after the block it's in):

```swift
let helpDoctor = """
axon doctor - diagnose axon's environment

  axon doctor                  Run all checks, emit JSON
  axon doctor --format text    Human-readable checklist

Checks performed:
  accessibility     — AXIsProcessTrusted (required)
  screen_recording  — CGPreflightScreenCaptureAccess (required)
  architecture      — Apple Silicon vs Intel (informational)
  tart              — Tart CLI on PATH (informational, for vm-*)
  binary_signature  — Developer ID signature on the running binary (informational)

Exit codes:
  0  all required checks pass
  1  at least one required check failed

Output:
  {
    "ready": true,
    "checks": [
      {"name": "accessibility", "status": "ok", "message": "…"},
      …
    ]
  }
"""
```

3b. Add to `showHelp(for:)` switch (around line 689):

```swift
    case "doctor":      text = helpDoctor
```

3c. Add to main dispatch switch (just before `default:` at line 1466):

```swift
case "doctor":
    let output = runDoctorLive()
    if format == .text {
        for check in output.checks {
            let marker: String
            switch check.status {
            case .ok: marker = "[ok]"
            case .warn: marker = "[warn]"
            case .fail: marker = "[fail]"
            }
            print("\(marker) \(check.name): \(check.message)")
            if let hint = check.fix_hint {
                print("       → \(hint)")
            }
        }
        print(output.ready ? "ready: true" : "ready: false")
    } else {
        printJSON(output)
    }
    if !output.ready { exit(1) }
```

3d. Update `helpMain` to list `doctor`. Find the line `App discovery:` block and either insert a new section at the top or below it. Add near the top of the help body, after "All commands output JSON to stdout…":

```
Diagnostics:
  axon doctor                                        Check AX + screen recording permissions, etc.
```

Concretely: open `Sources/axon/main.swift`, find the `App discovery:` block in `helpMain`, and insert the `Diagnostics:` block just above it.

- [ ] **Step 4: Rebuild and run tests**

Run: `swift build -c release && swift test --filter AxonIntegrationTests`
Expected: PASS (all existing + 3 new).

Also run: `swift test --filter AxonUnitTests`
Expected: PASS (no regressions).

- [ ] **Step 5: Commit**

```bash
git add Sources/axon/main.swift Tests/AxonIntegrationTests/CLIIntegrationTests.swift
git commit -m "Wire axon doctor command"
```

---

## Task 7: Extend ElementSelector with `.sheet` and `.alert` cases

**Files:**
- Modify: `Sources/AxonLib/AXHelpers.swift`
- Create: `Tests/AxonUnitTests/SheetResolverTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/AxonUnitTests/SheetResolverTests.swift`:

```swift
import XCTest
@testable import AxonLib

final class SheetResolverTests: XCTestCase {

    func testElementSelectorHasSheetCase() {
        let selector: ElementSelector = .sheet(labelFilter: nil)
        switch selector {
        case .sheet: break
        default: XCTFail("Expected .sheet case")
        }
    }

    func testElementSelectorHasAlertCase() {
        let selector: ElementSelector = .alert(labelFilter: nil)
        switch selector {
        case .alert: break
        default: XCTFail("Expected .alert case")
        }
    }

    func testFindElementSheetOnSelfAppReturnsNil() {
        // Self app has no sheet attached. Should resolve to nil (not crash).
        let selfApp = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let found = findElement(root: selfApp, selector: .sheet(labelFilter: nil))
        XCTAssertNil(found)
    }

    func testFindElementAlertOnSelfAppReturnsNil() {
        let selfApp = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let found = findElement(root: selfApp, selector: .alert(labelFilter: nil))
        XCTAssertNil(found)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AxonUnitTests/SheetResolverTests`
Expected: FAIL — compile error, `.sheet` and `.alert` cases don't exist on `ElementSelector`.

- [ ] **Step 3: Write minimal implementation**

Edit `Sources/AxonLib/AXHelpers.swift`:

3a. Extend the `ElementSelector` enum (around line 155):

```swift
public enum ElementSelector {
    case identifier(String)
    case label(String)
    case path(String)
    /// Frontmost AXSheet attached to the app's active window. Optional label filter picks a descendant by title/description.
    case sheet(labelFilter: String?)
    /// Frontmost AXSheet whose role description is "alert" or subrole is AXSystemDialog. Optional label filter as above.
    case alert(labelFilter: String?)
}
```

3b. Extend `findElement` to dispatch the new cases. Replace the existing switch statement inside `findElement` with:

```swift
public func findElement(root: AXUIElement, selector: ElementSelector) -> FoundElement? {
    switch selector {
    case .path(let path):
        return findByPath(root: root, path: path)
    case .identifier(let id):
        if let found = findByAttribute(root: root, attribute: kAXIdentifierAttribute as String, value: id, exact: true) {
            return found
        }
        return nil
    case .label(let text):
        if let found = findByAttribute(root: root, attribute: kAXTitleAttribute as String, value: text, exact: true) {
            return found
        }
        if let found = findByAttribute(root: root, attribute: kAXDescriptionAttribute as String, value: text, exact: true) {
            return found
        }
        if let found = findByAttribute(root: root, attribute: kAXTitleAttribute as String, value: text, exact: false) {
            return found
        }
        if let found = findByAttribute(root: root, attribute: kAXDescriptionAttribute as String, value: text, exact: false) {
            return found
        }
        return nil
    case .sheet(let labelFilter):
        return findFrontmostSheet(appElement: root, alertOnly: false, labelFilter: labelFilter)
    case .alert(let labelFilter):
        return findFrontmostSheet(appElement: root, alertOnly: true, labelFilter: labelFilter)
    }
}
```

3c. Append `findFrontmostSheet` at the end of the `// MARK: - Element Finding` section (after `collectMatches`):

```swift
/// Find the frontmost AXSheet attached to the app's active window.
/// If `alertOnly` is true, only returns sheets whose role description is
/// "alert" or whose subrole is "AXSystemDialog". If `labelFilter` is non-nil,
/// searches inside the sheet for a descendant matching that label.
private func findFrontmostSheet(appElement: AXUIElement, alertOnly: Bool, labelFilter: String?) -> FoundElement? {
    // Find the focused/active window on the app.
    var focusedWindow: AXUIElement? = nil
    var raw: AnyObject?
    if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &raw) == .success,
       let w = raw {
        focusedWindow = (w as! AXUIElement)
    }
    // Fall back: first window.
    if focusedWindow == nil {
        let windows: [AXUIElement] = axAttribute(appElement, kAXWindowsAttribute as String) ?? []
        focusedWindow = windows.first
    }
    guard let window = focusedWindow else { return nil }

    // Look for AXSheet children of the window.
    let sheets: [AXUIElement] = axAttribute(window, "AXSheets") ?? []
    let candidate: AXUIElement?
    if alertOnly {
        candidate = sheets.first(where: { isAlertLike($0) })
    } else {
        candidate = sheets.first
    }
    guard let sheet = candidate else { return nil }

    if let filter = labelFilter {
        // Descend into the sheet to find a labeled element.
        return findElement(root: sheet, selector: .label(filter))
    }

    return FoundElement(
        element: sheet,
        role: axStringAttribute(sheet, kAXRoleAttribute as String),
        title: axStringAttribute(sheet, kAXTitleAttribute as String),
        identifier: axStringAttribute(sheet, kAXIdentifierAttribute as String)
    )
}

private func isAlertLike(_ element: AXUIElement) -> Bool {
    if let subrole: String = axStringAttribute(element, kAXSubroleAttribute as String) {
        if subrole == "AXSystemDialog" || subrole == "AXDialog" { return true }
    }
    if let roleDesc: String = axStringAttribute(element, "AXRoleDescription") {
        if roleDesc.localizedCaseInsensitiveContains("alert") { return true }
    }
    return false
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter AxonUnitTests`
Expected: PASS (including the 4 new `SheetResolverTests`).

- [ ] **Step 5: Commit**

```bash
git add Sources/AxonLib/AXHelpers.swift Tests/AxonUnitTests/SheetResolverTests.swift
git commit -m "Add .sheet and .alert cases to ElementSelector"
```

---

## Task 8: Extend `resolveElement` to accept `--sheet`/`--alert`

**Files:**
- Modify: `Sources/AxonLib/AppDiscovery.swift`
- Modify: `Tests/AxonUnitTests/SheetResolverTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `SheetResolverTests.swift`:

```swift
// MARK: - resolveElement integration

// Note: resolveElement exits the process on missing element, so we can't easily
// unit test the error path. We do verify it accepts the new signature without crashing.

func testResolveElementSignatureAcceptsSheetFlag() {
    // Compile-time check: the new signature exists.
    let _: (AXUIElement, String?, String?, String?, Bool, Bool, String) -> FoundElement = resolveElement(appElement:identifier:label:path:sheet:alert:appName:)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AxonUnitTests/SheetResolverTests/testResolveElementSignatureAcceptsSheetFlag`
Expected: FAIL — compile error, resolveElement doesn't have that signature.

- [ ] **Step 3: Write minimal implementation**

Edit `Sources/AxonLib/AppDiscovery.swift`, replace the existing `resolveElement`:

```swift
/// Resolve an element selector from CLI arguments, printing error and exiting if not found.
///
/// Priority: `--sheet`/`--alert` (combined with optional `--label` as a descendant filter),
/// then `--identifier`, then `--label`, then `--path`. At most one of sheet/alert should be true.
public func resolveElement(
    appElement: AXUIElement,
    identifier: String?,
    label: String?,
    path: String?,
    sheet: Bool = false,
    alert: Bool = false,
    appName: String
) -> FoundElement {
    let selector: ElementSelector
    if sheet {
        selector = .sheet(labelFilter: label)
    } else if alert {
        selector = .alert(labelFilter: label)
    } else if let id = identifier {
        selector = .identifier(id)
    } else if let lbl = label {
        selector = .label(lbl)
    } else if let p = path {
        selector = .path(p)
    } else {
        printError(code: "missing_selector", message: "Provide --identifier, --label, --path, --sheet, or --alert to select an element")
        exit(1)
    }

    guard let found = findElement(root: appElement, selector: selector) else {
        let available = collectAvailableIdentifiers(root: appElement)
        let selectorDesc: String
        switch selector {
        case .identifier(let v): selectorDesc = "identifier '\(v)'"
        case .label(let v): selectorDesc = "label '\(v)'"
        case .path(let v): selectorDesc = "path '\(v)'"
        case .sheet(let f): selectorDesc = f.map { "sheet with label '\($0)'" } ?? "frontmost sheet"
        case .alert(let f): selectorDesc = f.map { "alert with label '\($0)'" } ?? "frontmost alert"
        }
        printError(
            code: "element_not_found",
            message: "No element with \(selectorDesc) found in \(appName)",
            available: available
        )
        exit(1)
    }

    return found
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter AxonUnitTests`
Expected: PASS. All existing call-sites still compile because the new `sheet`/`alert` parameters default to `false`.

Also run: `swift build -c release` — confirm main.swift still compiles (existing callers do not pass sheet/alert and the defaults kick in).

- [ ] **Step 5: Commit**

```bash
git add Sources/AxonLib/AppDiscovery.swift Tests/AxonUnitTests/SheetResolverTests.swift
git commit -m "resolveElement accepts --sheet/--alert flags"
```

---

## Task 9: Wire `--sheet`/`--alert` into all element-targeting commands in main.swift

**Files:**
- Modify: `Sources/axon/main.swift`

This is a wiring task (not a new feature). Every call site of `resolveElement` must forward `--sheet`/`--alert` flags. Then a follow-up test verifies one call site works end-to-end via `axon click --app Y --sheet` exit paths.

- [ ] **Step 1: Write the failing integration test**

Append to `CLIIntegrationTests.swift`:

```swift
// MARK: - --sheet / --alert wiring

func testClickSheetHelpMentionsSheetFlag() {
    let result = runAxon(["click", "--help"])
    XCTAssertEqual(result.exitCode, 0)
    XCTAssertTrue(
        result.stderr.contains("--sheet") || result.stderr.contains("sheet"),
        "click --help should mention sheet targeting"
    )
}

func testMainHelpMentionsSheetFlag() {
    let result = runAxon(["--help"])
    XCTAssertTrue(result.stderr.contains("--sheet"), "main --help should document --sheet")
}

func testMainHelpMentionsAlertFlag() {
    let result = runAxon(["--help"])
    XCTAssertTrue(result.stderr.contains("--alert"), "main --help should document --alert")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift build -c release && swift test --filter AxonIntegrationTests/CLIIntegrationTests/testMainHelpMentionsSheetFlag`
Expected: FAIL.

- [ ] **Step 3: Write minimal implementation**

3a. In `Sources/axon/main.swift`, find every call to `resolveElement(` and add the two new kwargs. There are ~12 call sites (from grep earlier). Use sed or manual edit. For each call that looks like:

```swift
let found = resolveElement(
    appElement: axApp,
    identifier: cli.option("identifier"),
    label: cli.option("label"),
    path: cli.option("path"),
    appName: appName
)
```

Replace with:

```swift
let found = resolveElement(
    appElement: axApp,
    identifier: cli.option("identifier"),
    label: cli.option("label"),
    path: cli.option("path"),
    sheet: cli.flag("sheet"),
    alert: cli.flag("alert"),
    appName: appName
)
```

Do this for every call site (click, right-click, double-click, type, hover, drag [both from and to], screenshot [element variant], set-value, get-value, and any others). For the `drag` command, pass the flags through for the `fromFound` / `toFound` calls (note: `--sheet`/`--alert` on drag are an edge case — applying them to both from and to would rarely make sense, so for `drag` keep `sheet: false, alert: false` for now and document that in the help if needed).

Use grep to verify all call sites are updated:

Run: `grep -n 'resolveElement(' Sources/axon/main.swift`
Expected: every call now has `sheet:` and `alert:` parameters (except the two drag-from/drag-to calls, which explicitly pass `sheet: false, alert: false`).

3b. In `helpMain`, add `--sheet` / `--alert` to the Element targeting section. Find the block starting with `Element targeting (<target> in click, type, scroll, wait):` and append:

```
  --sheet             Frontmost sheet attached to the active window
  --alert             Frontmost sheet recognized as an alert
  (--sheet and --alert compose with --label to pick a descendant.)
```

3c. Also append the new resolver flags to each element-targeting subcommand's help text (`helpClick`, `helpType`, `helpRightClick`, `helpDoubleClick`, `helpGetValue`, etc.). For a first pass, add a one-line note to `helpClick`:

Find the `let helpClick = """` block and add at the bottom of the targeting section:

```
  --sheet               Target the frontmost sheet (e.g. unsaved-changes dialog)
  --alert               Target the frontmost alert
```

(Other subcommand help blocks can mirror this wording when user-visible polish matters, but `helpMain` is the canonical reference.)

- [ ] **Step 4: Rebuild and run tests**

Run: `swift build -c release && swift test --filter AxonIntegrationTests`
Expected: PASS (new 3 tests pass, no regressions).

Run: `swift test --filter AxonUnitTests`
Expected: PASS, no regressions.

- [ ] **Step 5: Commit**

```bash
git add Sources/axon/main.swift Tests/AxonIntegrationTests/CLIIntegrationTests.swift
git commit -m "Wire --sheet/--alert resolvers into all element-targeting commands"
```

---

## Task 10: Add output models for `assert` and `exists`

**Files:**
- Modify: `Sources/AxonLib/Models.swift`
- Modify: `Tests/AxonUnitTests/ModelsTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `ModelsTests.swift`:

```swift
// MARK: - AssertOutput / ExistsOutput

func testAssertOutputPassEncoding() throws {
    let out = AssertOutput(success: true, passed: true, element: ElementInfo(role: "AXButton", title: "OK", identifier: "okBtn"), failures: [])
    let data = try jsonEncoder.encode(out)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["passed"] as? Bool, true)
    // failures array omitted when empty
    XCTAssertNil(json["failures"])
}

func testAssertOutputFailEncodingShowsFailures() throws {
    let out = AssertOutput(
        success: false,
        passed: false,
        element: ElementInfo(role: "AXButton", title: nil, identifier: "okBtn"),
        failures: [AssertFailure(assertion: "enabled", expected: "true", actual: "false")]
    )
    let data = try jsonEncoder.encode(out)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["passed"] as? Bool, false)
    let fails = json["failures"] as! [[String: Any]]
    XCTAssertEqual(fails.count, 1)
    XCTAssertEqual(fails[0]["assertion"] as? String, "enabled")
    XCTAssertEqual(fails[0]["expected"] as? String, "true")
    XCTAssertEqual(fails[0]["actual"] as? String, "false")
}

func testExistsOutputEncoding() throws {
    let out = ExistsOutput(success: true, exists: true, count: 1)
    let data = try jsonEncoder.encode(out)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["exists"] as? Bool, true)
    XCTAssertEqual(json["count"] as? Int, 1)
}

func testWaitReadyOutputEncoding() throws {
    let out = WaitReadyOutput(success: true, elapsed_ms: 340)
    let data = try jsonEncoder.encode(out)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["success"] as? Bool, true)
    XCTAssertEqual(json["elapsed_ms"] as? Int, 340)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AxonUnitTests/ModelsTests/testAssertOutputPassEncoding`
Expected: FAIL — "Cannot find 'AssertOutput'".

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/AxonLib/Models.swift` just before `// MARK: - Error Output`:

```swift
// MARK: - Assert / Exists / WaitReady Output

public struct AssertFailure: Codable {
    public let assertion: String
    public let expected: String
    public let actual: String

    public init(assertion: String, expected: String, actual: String) {
        self.assertion = assertion
        self.expected = expected
        self.actual = actual
    }
}

public struct AssertOutput: Codable {
    public let success: Bool
    public let passed: Bool
    public let element: ElementInfo
    public let failures: [AssertFailure]

    public init(success: Bool, passed: Bool, element: ElementInfo, failures: [AssertFailure]) {
        self.success = success
        self.passed = passed
        self.element = element
        self.failures = failures
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(success, forKey: .success)
        try c.encode(passed, forKey: .passed)
        try c.encode(element, forKey: .element)
        if !failures.isEmpty { try c.encode(failures, forKey: .failures) }
    }

    enum CodingKeys: String, CodingKey {
        case success, passed, element, failures
    }
}

public struct ExistsOutput: Codable {
    public let success: Bool
    public let exists: Bool
    public let count: Int

    public init(success: Bool, exists: Bool, count: Int) {
        self.success = success
        self.exists = exists
        self.count = count
    }
}

public struct WaitReadyOutput: Codable {
    public let success: Bool
    public let elapsed_ms: Int

    public init(success: Bool, elapsed_ms: Int) {
        self.success = success
        self.elapsed_ms = elapsed_ms
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter AxonUnitTests/ModelsTests`
Expected: PASS (4 new tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AxonLib/Models.swift Tests/AxonUnitTests/ModelsTests.swift
git commit -m "Add AssertOutput/ExistsOutput/WaitReadyOutput models"
```

---

## Task 11: `performAssert` — core with `--exists` / `--not-exists`

**Files:**
- Create: `Sources/AxonLib/Assertions.swift`
- Create: `Tests/AxonUnitTests/AssertionsTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/AxonUnitTests/AssertionsTests.swift`:

```swift
import XCTest
@testable import AxonLib

final class AssertionsTests: XCTestCase {

    // MARK: - AssertionSpec equality / defaults

    func testEmptyAssertionSpecIsNoOp() {
        let spec = AssertionSpec()
        // With no assertions, evaluateAssertions returns [] (no failures).
        let failures = evaluateAssertions(spec, on: nil)
        XCTAssertTrue(failures.isEmpty)
    }

    // MARK: - exists / not-exists

    func testExistsAssertionPassesWhenElementFound() {
        var spec = AssertionSpec()
        spec.exists = true
        let selfApp = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let failures = evaluateAssertions(spec, on: selfApp)
        XCTAssertTrue(failures.isEmpty)
    }

    func testExistsAssertionFailsWhenElementMissing() {
        var spec = AssertionSpec()
        spec.exists = true
        let failures = evaluateAssertions(spec, on: nil)
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures[0].assertion, "exists")
        XCTAssertEqual(failures[0].expected, "true")
        XCTAssertEqual(failures[0].actual, "false")
    }

    func testNotExistsAssertionPassesWhenElementMissing() {
        var spec = AssertionSpec()
        spec.notExists = true
        let failures = evaluateAssertions(spec, on: nil)
        XCTAssertTrue(failures.isEmpty)
    }

    func testNotExistsAssertionFailsWhenElementFound() {
        var spec = AssertionSpec()
        spec.notExists = true
        let selfApp = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let failures = evaluateAssertions(spec, on: selfApp)
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures[0].assertion, "not-exists")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AxonUnitTests/AssertionsTests`
Expected: FAIL — compile error, `AssertionSpec` and `evaluateAssertions` don't exist.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/AxonLib/Assertions.swift`:

```swift
import Cocoa
import ApplicationServices

/// Declarative description of all assertions to evaluate on a single element.
/// Nil fields mean "skip this assertion".
public struct AssertionSpec {
    public var exists: Bool = false
    public var notExists: Bool = false
    public var value: String? = nil
    public var valueMatches: String? = nil
    public var enabled: Bool = false
    public var disabled: Bool = false
    public var focused: Bool = false

    public init() {}
}

/// Evaluate every assertion in `spec` against `element`. An element of nil means "not found".
/// Returns all failing assertions (empty array = pass).
public func evaluateAssertions(_ spec: AssertionSpec, on element: AXUIElement?) -> [AssertFailure] {
    var failures: [AssertFailure] = []

    if spec.exists {
        if element == nil {
            failures.append(AssertFailure(assertion: "exists", expected: "true", actual: "false"))
        }
    }
    if spec.notExists {
        if element != nil {
            failures.append(AssertFailure(assertion: "not-exists", expected: "true", actual: "false"))
        }
    }

    return failures
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter AxonUnitTests/AssertionsTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AxonLib/Assertions.swift Tests/AxonUnitTests/AssertionsTests.swift
git commit -m "Add AssertionSpec and evaluateAssertions with exists/not-exists"
```

---

## Task 12: `performAssert` — value / value-matches

**Files:**
- Modify: `Sources/AxonLib/Assertions.swift`
- Modify: `Tests/AxonUnitTests/AssertionsTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `AssertionsTests.swift`:

```swift
// MARK: - value / value-matches

func testValueAssertionPasses() {
    var spec = AssertionSpec()
    spec.value = "hello"
    let failures = evaluateAssertions(spec, on: nil, resolvedValue: "hello")
    XCTAssertTrue(failures.isEmpty)
}

func testValueAssertionFailsOnMismatch() {
    var spec = AssertionSpec()
    spec.value = "hello"
    let failures = evaluateAssertions(spec, on: nil, resolvedValue: "world")
    XCTAssertEqual(failures.count, 1)
    XCTAssertEqual(failures[0].assertion, "value")
    XCTAssertEqual(failures[0].expected, "hello")
    XCTAssertEqual(failures[0].actual, "world")
}

func testValueAssertionFailsOnNilValue() {
    var spec = AssertionSpec()
    spec.value = "hello"
    let failures = evaluateAssertions(spec, on: nil, resolvedValue: nil)
    XCTAssertEqual(failures.count, 1)
    XCTAssertEqual(failures[0].actual, "<nil>")
}

func testValueMatchesPassesOnRegexMatch() {
    var spec = AssertionSpec()
    spec.valueMatches = "^hel+o$"
    let failures = evaluateAssertions(spec, on: nil, resolvedValue: "hellllo")
    XCTAssertTrue(failures.isEmpty)
}

func testValueMatchesFailsOnNoMatch() {
    var spec = AssertionSpec()
    spec.valueMatches = "^hello$"
    let failures = evaluateAssertions(spec, on: nil, resolvedValue: "world")
    XCTAssertEqual(failures.count, 1)
    XCTAssertEqual(failures[0].assertion, "value-matches")
}

func testValueMatchesFailsOnNilValue() {
    var spec = AssertionSpec()
    spec.valueMatches = "x"
    let failures = evaluateAssertions(spec, on: nil, resolvedValue: nil)
    XCTAssertEqual(failures.count, 1)
    XCTAssertEqual(failures[0].actual, "<nil>")
}
```

Note: these tests call `evaluateAssertions(_:on:resolvedValue:)` — a new overload. The existing tests use the 2-arg form. We will keep both.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AxonUnitTests/AssertionsTests/testValueAssertionPasses`
Expected: FAIL — no matching overload.

- [ ] **Step 3: Write minimal implementation**

Refactor `Sources/AxonLib/Assertions.swift` so `evaluateAssertions` takes a resolved element state:

```swift
import Cocoa
import ApplicationServices

public struct AssertionSpec {
    public var exists: Bool = false
    public var notExists: Bool = false
    public var value: String? = nil
    public var valueMatches: String? = nil
    public var enabled: Bool = false
    public var disabled: Bool = false
    public var focused: Bool = false

    public init() {}
}

/// Snapshot of an element's state sampled once so assertions see a consistent view.
public struct ElementSnapshot {
    public let value: String?
    public let enabled: Bool?
    public let focused: Bool?

    public init(value: String?, enabled: Bool?, focused: Bool?) {
        self.value = value
        self.enabled = enabled
        self.focused = focused
    }

    public static func capture(from element: AXUIElement) -> ElementSnapshot {
        let value: String? = {
            var raw: AnyObject?
            let r = AXUIElementCopyAttributeValue(element, kAXValueAttribute as String as CFString, &raw)
            guard r == .success, let v = raw else { return nil }
            if let s = v as? String { return s }
            if let n = v as? NSNumber { return n.stringValue }
            return nil
        }()
        let enabled: Bool? = axBoolAttribute(element, kAXEnabledAttribute as String)
        let focused: Bool? = axBoolAttribute(element, kAXFocusedAttribute as String)
        return ElementSnapshot(value: value, enabled: enabled, focused: focused)
    }
}

public func evaluateAssertions(_ spec: AssertionSpec, on element: AXUIElement?) -> [AssertFailure] {
    let snapshot: ElementSnapshot? = element.map { ElementSnapshot.capture(from: $0) }
    return evaluateAssertions(spec, on: element, snapshot: snapshot)
}

/// Overload used by tests to inject a value without needing a real AXUIElement.
public func evaluateAssertions(_ spec: AssertionSpec, on element: AXUIElement?, resolvedValue: String?) -> [AssertFailure] {
    let snap = ElementSnapshot(value: resolvedValue, enabled: nil, focused: nil)
    return evaluateAssertions(spec, on: element, snapshot: snap)
}

public func evaluateAssertions(_ spec: AssertionSpec, on element: AXUIElement?, snapshot: ElementSnapshot?) -> [AssertFailure] {
    var failures: [AssertFailure] = []

    if spec.exists {
        if element == nil {
            failures.append(AssertFailure(assertion: "exists", expected: "true", actual: "false"))
        }
    }
    if spec.notExists {
        if element != nil {
            failures.append(AssertFailure(assertion: "not-exists", expected: "true", actual: "false"))
        }
    }

    if let expected = spec.value {
        let actual = snapshot?.value
        if actual != expected {
            failures.append(AssertFailure(assertion: "value", expected: expected, actual: actual ?? "<nil>"))
        }
    }
    if let pattern = spec.valueMatches {
        let actual = snapshot?.value
        guard let actual = actual else {
            failures.append(AssertFailure(assertion: "value-matches", expected: pattern, actual: "<nil>"))
            return failures
        }
        let matched = (try? NSRegularExpression(pattern: pattern))
            .flatMap { regex -> Bool? in
                let range = NSRange(actual.startIndex..., in: actual)
                return regex.firstMatch(in: actual, range: range) != nil
            } ?? false
        if !matched {
            failures.append(AssertFailure(assertion: "value-matches", expected: pattern, actual: actual))
        }
    }

    return failures
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter AxonUnitTests/AssertionsTests`
Expected: PASS (all 11 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AxonLib/Assertions.swift Tests/AxonUnitTests/AssertionsTests.swift
git commit -m "Add value/value-matches assertions with ElementSnapshot"
```

---

## Task 13: `performAssert` — enabled / disabled / focused

**Files:**
- Modify: `Sources/AxonLib/Assertions.swift`
- Modify: `Tests/AxonUnitTests/AssertionsTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `AssertionsTests.swift`:

```swift
// MARK: - enabled / disabled / focused

private func snap(enabled: Bool? = nil, focused: Bool? = nil, value: String? = nil) -> ElementSnapshot {
    return ElementSnapshot(value: value, enabled: enabled, focused: focused)
}

func testEnabledPasses() {
    var spec = AssertionSpec()
    spec.enabled = true
    let failures = evaluateAssertions(spec, on: AXUIElementCreateSystemWide(), snapshot: snap(enabled: true))
    XCTAssertTrue(failures.isEmpty)
}

func testEnabledFails() {
    var spec = AssertionSpec()
    spec.enabled = true
    let failures = evaluateAssertions(spec, on: AXUIElementCreateSystemWide(), snapshot: snap(enabled: false))
    XCTAssertEqual(failures.count, 1)
    XCTAssertEqual(failures[0].assertion, "enabled")
}

func testEnabledFailsOnUnknown() {
    var spec = AssertionSpec()
    spec.enabled = true
    let failures = evaluateAssertions(spec, on: AXUIElementCreateSystemWide(), snapshot: snap(enabled: nil))
    XCTAssertEqual(failures.count, 1)
    XCTAssertEqual(failures[0].actual, "<nil>")
}

func testDisabledPasses() {
    var spec = AssertionSpec()
    spec.disabled = true
    let failures = evaluateAssertions(spec, on: AXUIElementCreateSystemWide(), snapshot: snap(enabled: false))
    XCTAssertTrue(failures.isEmpty)
}

func testDisabledFails() {
    var spec = AssertionSpec()
    spec.disabled = true
    let failures = evaluateAssertions(spec, on: AXUIElementCreateSystemWide(), snapshot: snap(enabled: true))
    XCTAssertEqual(failures.count, 1)
    XCTAssertEqual(failures[0].assertion, "disabled")
}

func testFocusedPasses() {
    var spec = AssertionSpec()
    spec.focused = true
    let failures = evaluateAssertions(spec, on: AXUIElementCreateSystemWide(), snapshot: snap(focused: true))
    XCTAssertTrue(failures.isEmpty)
}

func testFocusedFails() {
    var spec = AssertionSpec()
    spec.focused = true
    let failures = evaluateAssertions(spec, on: AXUIElementCreateSystemWide(), snapshot: snap(focused: false))
    XCTAssertEqual(failures.count, 1)
    XCTAssertEqual(failures[0].assertion, "focused")
}

func testMultipleAssertionsCompose() {
    var spec = AssertionSpec()
    spec.enabled = true
    spec.focused = true
    let failures = evaluateAssertions(spec, on: AXUIElementCreateSystemWide(), snapshot: snap(enabled: false, focused: false))
    XCTAssertEqual(failures.count, 2)
    let names = Set(failures.map(\.assertion))
    XCTAssertEqual(names, ["enabled", "focused"])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AxonUnitTests/AssertionsTests/testEnabledFails`
Expected: FAIL — enabled/disabled/focused not yet handled.

- [ ] **Step 3: Write minimal implementation**

In `Sources/AxonLib/Assertions.swift`, inside the main `evaluateAssertions(_:on:snapshot:)` function, add before `return failures`:

```swift
    if spec.enabled {
        let actual = snapshot?.enabled
        if actual != true {
            failures.append(AssertFailure(assertion: "enabled", expected: "true", actual: actual.map(String.init) ?? "<nil>"))
        }
    }
    if spec.disabled {
        let actual = snapshot?.enabled
        if actual != false {
            failures.append(AssertFailure(assertion: "disabled", expected: "false", actual: actual.map(String.init) ?? "<nil>"))
        }
    }
    if spec.focused {
        let actual = snapshot?.focused
        if actual != true {
            failures.append(AssertFailure(assertion: "focused", expected: "true", actual: actual.map(String.init) ?? "<nil>"))
        }
    }
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter AxonUnitTests/AssertionsTests`
Expected: PASS (all 19 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AxonLib/Assertions.swift Tests/AxonUnitTests/AssertionsTests.swift
git commit -m "Add enabled/disabled/focused assertions"
```

---

## Task 14: `axon assert` — CLI wiring

**Files:**
- Modify: `Sources/axon/main.swift`
- Modify: `Tests/AxonIntegrationTests/CLIIntegrationTests.swift`

- [ ] **Step 1: Write the failing integration test**

Append to `CLIIntegrationTests.swift`:

```swift
// MARK: - assert

func testAssertWithoutAppFails() {
    let result = runAxon(["assert"])
    XCTAssertNotEqual(result.exitCode, 0)
}

func testAssertHelp() {
    let result = runAxon(["assert", "--help"])
    XCTAssertEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("axon assert"))
    XCTAssertTrue(result.stderr.contains("--exists"))
}

func testAssertAppNotFoundExitsOne() {
    // App-not-found flows through the shared resolveApp path and exits 1.
    // (Exit code 2 is reserved for element-lookup errors in a present app; that path
    // would require a live app + missing element, exercised only in the M2 E2E suite.)
    let result = runAxon(["assert", "--app", "NonExistentApp_XYZ_999", "--identifier", "x", "--exists"])
    XCTAssertEqual(result.exitCode, 1, "assert should exit 1 when the app itself isn't running")
}

func testMainHelpListsAssert() {
    let result = runAxon(["--help"])
    XCTAssertTrue(result.stderr.contains("assert"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift build -c release && swift test --filter AxonIntegrationTests/CLIIntegrationTests/testAssertHelp`
Expected: FAIL — "Unknown command 'assert'".

- [ ] **Step 3: Write minimal implementation**

3a. Add `helpAssert` constant near other help blocks in `Sources/axon/main.swift`:

```swift
let helpAssert = """
axon assert - verify UI state with clean exit codes

  axon assert --app <app> <target> [assertions...]

Targeting (choose one or combine --sheet/--alert with --label):
  --identifier <id>     Accessibility identifier
  --label <text>        Title or description
  --path <treepath>     Tree path from 'axon tree'
  --sheet               Frontmost sheet attached to active window
  --alert               Frontmost alert

Assertions (all must pass):
  --exists              Element must be present
  --not-exists          Element must not be present
  --value <str>         AXValue must equal str (exact)
  --value-matches <rx>  AXValue must match regex
  --enabled             Element must be enabled
  --disabled            Element must be disabled
  --focused             Element must be focused

Exit codes:
  0  all assertions passed
  1  at least one assertion failed (details on stderr)
  2  element lookup error (app missing, element missing on --exists=false)

Examples:
  axon assert --app MyApp --identifier ok --exists --enabled
  axon assert --app MyApp --label "Save" --value-matches "^Sav"
  axon assert --app MyApp --sheet --label "Don't Save" --exists
"""
```

3b. Add `case "assert": text = helpAssert` to `showHelp(for:)`.

3c. Add dispatch in the main switch (before `default:`):

```swift
case "assert":
    checkAccessibilityPermission()
    let appName = cli.requireOption("app")
    let (app, axApp) = resolveApp(name: appName)

    if !noActivate { activateApp(app) }

    var spec = AssertionSpec()
    spec.exists = cli.flag("exists")
    spec.notExists = cli.flag("not-exists")
    spec.value = cli.option("value")
    spec.valueMatches = cli.option("value-matches")
    spec.enabled = cli.flag("enabled")
    spec.disabled = cli.flag("disabled")
    spec.focused = cli.flag("focused")

    let anySpec = spec.exists || spec.notExists || spec.value != nil ||
                  spec.valueMatches != nil || spec.enabled || spec.disabled || spec.focused
    if !anySpec {
        printError(code: "missing_option", message: "Provide at least one assertion: --exists, --not-exists, --value, --value-matches, --enabled, --disabled, --focused")
        exit(1)
    }

    // Try to find the element; allow missing if user is asserting --not-exists only.
    let selector: ElementSelector?
    if cli.flag("sheet") {
        selector = .sheet(labelFilter: cli.option("label"))
    } else if cli.flag("alert") {
        selector = .alert(labelFilter: cli.option("label"))
    } else if let id = cli.option("identifier") {
        selector = .identifier(id)
    } else if let lbl = cli.option("label") {
        selector = .label(lbl)
    } else if let p = cli.option("path") {
        selector = .path(p)
    } else {
        selector = nil
    }

    let foundOpt: FoundElement? = selector.flatMap { findElement(root: axApp, selector: $0) }

    // If caller asked for anything beyond --not-exists and the element isn't there, exit 2.
    let requiresElement = spec.exists || spec.value != nil || spec.valueMatches != nil ||
                          spec.enabled || spec.disabled || spec.focused
    if requiresElement && foundOpt == nil {
        let available = collectAvailableIdentifiers(root: axApp)
        printError(code: "element_not_found", message: "No element found for assertion in \(appName)", available: available)
        exit(2)
    }

    let snapshot = foundOpt.map { ElementSnapshot.capture(from: $0.element) }
    let failures = evaluateAssertions(spec, on: foundOpt?.element, snapshot: snapshot)

    let passed = failures.isEmpty
    let info = ElementInfo(role: foundOpt?.role, title: foundOpt?.title, identifier: foundOpt?.identifier)
    let out = AssertOutput(success: true, passed: passed, element: info, failures: failures)

    if passed {
        printJSON(out)
    } else {
        // Print pass/fail structure to stdout, detailed failures to stderr.
        printJSON(out)
        for f in failures {
            FileHandle.standardError.write("assert \(f.assertion): expected \(f.expected), actual \(f.actual)\n".data(using: .utf8)!)
        }
        exit(1)
    }
```

3d. Add `assert` to `helpMain` under the Interaction block (or a new Assertions block). Concretely, add a new section to `helpMain` after the Inspection block:

```
Assertions:
  axon assert --app <app> <target> [--exists|--not-exists|--value <s>|--value-matches <r>|--enabled|--disabled|--focused]
```

- [ ] **Step 4: Rebuild and run tests**

Run: `swift build -c release && swift test --filter AxonIntegrationTests`
Expected: PASS (4 new tests).

Run: `swift test --filter AxonUnitTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/axon/main.swift Tests/AxonIntegrationTests/CLIIntegrationTests.swift
git commit -m "Wire axon assert command"
```

---

## Task 15: `axon exists` — CLI wiring

**Files:**
- Modify: `Sources/axon/main.swift`
- Modify: `Tests/AxonIntegrationTests/CLIIntegrationTests.swift`

- [ ] **Step 1: Write the failing integration test**

Append to `CLIIntegrationTests.swift`:

```swift
// MARK: - exists

func testExistsHelp() {
    let result = runAxon(["exists", "--help"])
    XCTAssertEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("axon exists"))
}

func testExistsAppNotFoundStillExitsZero() {
    // exists is designed to not fail on lookup errors. App missing = {"exists": false, "count": 0}, exit 0.
    let result = runAxon(["exists", "--app", "NonExistentApp_XYZ_999", "--identifier", "x"])
    XCTAssertEqual(result.exitCode, 0)
    let json = parseJSON(result.stdout)
    XCTAssertEqual(json?["exists"] as? Bool, false)
    XCTAssertEqual(json?["count"] as? Int, 0)
}

func testMainHelpListsExists() {
    let result = runAxon(["--help"])
    XCTAssertTrue(result.stderr.contains("exists"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift build -c release && swift test --filter AxonIntegrationTests/CLIIntegrationTests/testExistsHelp`
Expected: FAIL — "Unknown command 'exists'".

- [ ] **Step 3: Write minimal implementation**

3a. Add `helpExists`:

```swift
let helpExists = """
axon exists - check if an element exists without failing

  axon exists --app <app> <target>

Targeting: same as 'assert' (--identifier/--label/--path/--sheet/--alert).

Always exits 0 on successful lookup. If the app is missing or the element
is not found, returns {"exists": false, "count": 0}. Use 'axon assert
--exists' if you want non-zero exit on absence.

Output:
  {"exists": true, "count": 1}
"""
```

3b. Add `case "exists": text = helpExists` to `showHelp(for:)`.

3c. Add dispatch in the main switch:

```swift
case "exists":
    // Unlike other commands, exists is designed to always exit 0 on any lookup result.
    // It short-circuits the "app not found exits 1" behavior by catching that case explicitly.
    guard AXIsProcessTrusted() else {
        printError(code: "accessibility_not_trusted", message: "axon does not have accessibility permissions.")
        exit(1)
    }
    let appName = cli.requireOption("app")
    guard let appRunning = findApp(name: appName) else {
        printJSON(ExistsOutput(success: true, exists: false, count: 0))
        exit(0)
    }
    let axApp = appElement(for: appRunning)

    let selector: ElementSelector?
    if cli.flag("sheet") {
        selector = .sheet(labelFilter: cli.option("label"))
    } else if cli.flag("alert") {
        selector = .alert(labelFilter: cli.option("label"))
    } else if let id = cli.option("identifier") {
        selector = .identifier(id)
    } else if let lbl = cli.option("label") {
        selector = .label(lbl)
    } else if let p = cli.option("path") {
        selector = .path(p)
    } else {
        printError(code: "missing_selector", message: "Provide --identifier, --label, --path, --sheet, or --alert")
        exit(1)
    }

    let found = selector.flatMap { findElement(root: axApp, selector: $0) }
    printJSON(ExistsOutput(success: true, exists: found != nil, count: found == nil ? 0 : 1))
```

3d. Add `exists` to `helpMain` under the Inspection block. Find `Inspection:` and add:

```
  axon exists --app <app> <target>                   Check existence (always exits 0)
```

- [ ] **Step 4: Rebuild and run tests**

Run: `swift build -c release && swift test --filter AxonIntegrationTests`
Expected: PASS (3 new tests).

Run: `swift test --filter AxonUnitTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/axon/main.swift Tests/AxonIntegrationTests/CLIIntegrationTests.swift
git commit -m "Wire axon exists command"
```

---

## Task 16: `performWaitReady` — core

**Files:**
- Modify: `Sources/AxonLib/Actions.swift`
- Modify: `Tests/AxonUnitTests/ActionsTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `ActionsTests.swift`:

```swift
// MARK: - performWaitReady

func testWaitReadyTimesOutOnUnreadyElement() {
    // Self app has no windows; wait-ready should time out.
    let selfApp = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
    let elapsed = performWaitReady(appElement: selfApp, timeout: 0.5)
    XCTAssertNil(elapsed)
}

func testWaitReadyReturnsQuicklyOnReadyApp() throws {
    // Finder is almost always running and ready.
    guard let finder = findApp(name: "Finder") else {
        throw XCTSkip("Finder not running")
    }
    let axFinder = appElement(for: finder)
    let elapsed = performWaitReady(appElement: axFinder, timeout: 5.0)
    XCTAssertNotNil(elapsed)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AxonUnitTests/ActionsTests/testWaitReadyTimesOutOnUnreadyElement`
Expected: FAIL — "Cannot find 'performWaitReady' in scope".

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/AxonLib/Actions.swift`:

```swift
// MARK: - Wait Ready

/// Poll until the app's AX tree has at least one window with at least one child,
/// and responds to attribute copies within 500ms. Returns elapsed ms or nil on timeout.
public func performWaitReady(appElement: AXUIElement, timeout: TimeInterval) -> Int? {
    let start = Date()
    let pollInterval: TimeInterval = 0.2

    while Date().timeIntervalSince(start) < timeout {
        if appIsReady(appElement) {
            return Int(Date().timeIntervalSince(start) * 1000)
        }
        Thread.sleep(forTimeInterval: pollInterval)
    }
    return nil
}

private func appIsReady(_ appElement: AXUIElement) -> Bool {
    // 1. Has at least one window.
    let windows: [AXUIElement] = axAttribute(appElement, kAXWindowsAttribute as String) ?? []
    guard let window = windows.first else { return false }
    // 2. Window has at least one child.
    let kids = axChildren(window)
    guard !kids.isEmpty else { return false }
    // 3. App responds to a basic attribute copy within 500ms (best effort via actual call).
    let callStart = Date()
    var raw: AnyObject?
    _ = AXUIElementCopyAttributeValue(appElement, kAXTitleAttribute as CFString, &raw)
    let callMs = Date().timeIntervalSince(callStart) * 1000
    return callMs < 500
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter AxonUnitTests/ActionsTests`
Expected: PASS (Finder test may be skipped on a fresh boot — acceptable).

- [ ] **Step 5: Commit**

```bash
git add Sources/AxonLib/Actions.swift Tests/AxonUnitTests/ActionsTests.swift
git commit -m "Add performWaitReady"
```

---

## Task 17: `axon wait-ready` — CLI wiring

**Files:**
- Modify: `Sources/axon/main.swift`
- Modify: `Tests/AxonIntegrationTests/CLIIntegrationTests.swift`

- [ ] **Step 1: Write the failing integration test**

Append to `CLIIntegrationTests.swift`:

```swift
// MARK: - wait-ready

func testWaitReadyHelp() {
    let result = runAxon(["wait-ready", "--help"])
    XCTAssertEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("axon wait-ready"))
}

func testWaitReadyAppNotFoundExitsOne() {
    let result = runAxon(["wait-ready", "--app", "NonExistentApp_XYZ_999", "--timeout", "1"])
    XCTAssertEqual(result.exitCode, 1)
}

func testMainHelpListsWaitReady() {
    let result = runAxon(["--help"])
    XCTAssertTrue(result.stderr.contains("wait-ready"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift build -c release && swift test --filter AxonIntegrationTests/CLIIntegrationTests/testWaitReadyHelp`
Expected: FAIL.

- [ ] **Step 3: Write minimal implementation**

3a. Add `helpWaitReady`:

```swift
let helpWaitReady = """
axon wait-ready - wait until an app's UI is ready to be driven

  axon wait-ready --app <app> [--timeout <seconds>]

Polls every 200ms until the app's AX tree has at least one window with
at least one child and responds to attribute queries within 500ms.

Defaults: --timeout 10.

Use after 'axon launch' to replace sleep-based warmups.

Output:
  {"success": true, "elapsed_ms": 420}

On timeout:
  {"error": "timeout", "message": "App did not become ready within 10s"}
"""
```

3b. Add `case "wait-ready": text = helpWaitReady` to `showHelp(for:)`.

3c. Add dispatch:

```swift
case "wait-ready":
    checkAccessibilityPermission()
    let appName = cli.requireOption("app")
    let timeout = TimeInterval(cli.intOption("timeout", default: 10))
    let (_, axApp) = resolveApp(name: appName)

    if let elapsed = performWaitReady(appElement: axApp, timeout: timeout) {
        emit(WaitReadyOutput(success: true, elapsed_ms: elapsed), plain: [("ready", "\(elapsed)ms")])
    } else {
        printError(code: "timeout", message: "App '\(appName)' did not become ready within \(Int(timeout))s")
        exit(1)
    }
```

3d. In `helpMain`, add under Waiting:

```
  axon wait-ready --app <app> [--timeout <s>]        Wait until app's UI is ready
```

- [ ] **Step 4: Rebuild and run tests**

Run: `swift build -c release && swift test --filter AxonIntegrationTests`
Expected: PASS (3 new tests).

Run: `swift test --filter AxonUnitTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/axon/main.swift Tests/AxonIntegrationTests/CLIIntegrationTests.swift
git commit -m "Wire axon wait-ready command"
```

---

## Task 18: Final verification and main help polish

**Files:**
- Modify: `Sources/axon/main.swift` (polish only)
- Modify: `Tests/AxonIntegrationTests/CLIIntegrationTests.swift`

- [ ] **Step 1: Write verification tests**

Append to `CLIIntegrationTests.swift`:

```swift
// MARK: - M1 final verification

func testAllNewCommandsAppearInHelp() {
    let result = runAxon(["--help"])
    XCTAssertTrue(result.stderr.contains("doctor"), "help missing doctor")
    XCTAssertTrue(result.stderr.contains("assert"), "help missing assert")
    XCTAssertTrue(result.stderr.contains("exists"), "help missing exists")
    XCTAssertTrue(result.stderr.contains("wait-ready"), "help missing wait-ready")
    XCTAssertTrue(result.stderr.contains("--sheet"), "help missing --sheet")
    XCTAssertTrue(result.stderr.contains("--alert"), "help missing --alert")
}

func testEachNewCommandHasDedicatedHelp() {
    for cmd in ["doctor", "assert", "exists", "wait-ready"] {
        let result = runAxon([cmd, "--help"])
        XCTAssertEqual(result.exitCode, 0, "\(cmd) --help should exit 0")
        XCTAssertTrue(result.stderr.contains("axon \(cmd)"), "\(cmd) --help should contain 'axon \(cmd)'")
    }
}
```

- [ ] **Step 2: Run tests**

Run: `swift build -c release && swift test --filter AxonIntegrationTests`
Expected: If any fail, read the failure and polish `helpMain` or the per-command help text until all pass. Typical issue: help sections missing `--sheet`/`--alert` in `helpMain`.

- [ ] **Step 3: Full regression sweep**

Run: `swift test --filter AxonUnitTests --filter AxonIntegrationTests`
Expected: ALL tests PASS, zero regressions.

- [ ] **Step 4: Confirm file sizes reasonable**

Run: `wc -l Sources/AxonLib/*.swift Sources/axon/main.swift`
Expected:
- `Diagnostics.swift` — under 150 lines
- `Assertions.swift` — under 200 lines
- `Actions.swift` — unchanged structure, +~30 lines for `performWaitReady`
- `main.swift` — grew by ~300 lines (help + dispatch); if it's uncomfortable, that's a M3 polish task, not an M1 task.

- [ ] **Step 5: Commit**

Only if Task 18 added anything:

```bash
git add Tests/AxonIntegrationTests/CLIIntegrationTests.swift
git commit -m "Final M1 verification tests"
```

If no new code was added in this task (all help text was already complete), skip the commit.

---

## End-of-milestone checklist

At this point:
- `swift test --filter AxonUnitTests --filter AxonIntegrationTests` — all green.
- `git log --oneline` shows ~16-18 new commits, each a small red-green cycle.
- `axon --help` lists `doctor`, `assert`, `exists`, `wait-ready`, `--sheet`, `--alert`.
- Each new command has `--help` that works.
- No new external dependencies.
- No E2E tests run (those come in M2).

If all of the above holds, M1 is done. Open a PR titled `M1: new commands (doctor, assert, exists, wait-ready, sheet/alert resolvers)`.
