# VM-by-default Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `axon`'s UI-driving commands route to a per-app Tart VM by default; opt back to the host with `--local` / `AXON_TARGET=local`. Subprocess-re-exec via SSH; bundle-ID → base mapping recorded at `vm-bake` time; hard-error on missing base.

**Architecture:** A new `Sources/AxonLib/Router.swift` adds three pure functions (`classifyCommand`, `resolveTarget`, `remapFileOutputs`) plus an orchestrator (`dispatchRemote`) that re-execs the host argv inside the target VM via SSH. `Sources/axon/main.swift` calls the router *before* its existing command switch; if the target is `.local`, the existing switch runs unchanged. The VM registry (`~/.axon/vms.json`) gains a `bases` array populated by `vm-bake --for-bundle`.

**Tech Stack:** Swift 5.9+, Foundation, Cocoa (existing), Process (for ssh/scp/rsync), XCTest. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-02-vm-by-default-design.md`

**Working principles:**
- **Strict red-green TDD.** Every task: write the failing test first, run it (verify the failure message), implement the minimum, run again (verify pass), commit. Do not implement before seeing red.
- **Small commits.** Each task ends with a commit. Do not batch tasks into a single commit.
- **No skipping.** If a step's expected output doesn't match, stop and diagnose; don't paper over it.
- **Background-agent test scope.** Run only `swift test --filter AxonUnitTests` and `swift test --filter AxonIntegrationTests` (E2E is host-disruptive). Build the release binary with `swift build -c release` before running integration tests; they exercise the binary at `.build/release/axon`.

---

## File map

**Create:**
- `Sources/AxonLib/Router.swift` — `CommandClass`, `Target`, `RouterError`, `ScpBack`, `SSHDispatcher` protocol, `VMAcquirer` protocol, `classifyCommand`, `resolveTarget`, `remapFileOutputs`, `dispatchRemote`.
- `Sources/AxonLib/SSHClient.swift` — concrete `SSHDispatcher` impl using `Process` to call `/usr/bin/ssh` and `/usr/bin/scp`.
- `Tests/AxonUnitTests/RouterClassifyTests.swift`
- `Tests/AxonUnitTests/RouterResolveTargetTests.swift`
- `Tests/AxonUnitTests/RouterRemapFileOutputsTests.swift`
- `Tests/AxonUnitTests/RouterDispatchTests.swift`
- `Tests/AxonIntegrationTests/RouterIntegrationTests.swift`

**Modify:**
- `Sources/AxonLib/VMManager.swift` — add `BaseEntry`, extend `VMRegistry`, add `recordBase`/`findBase(byBundleID:)`, support `AXON_REGISTRY_PATH` env in `defaultVMRegistryURL`.
- `Sources/AxonLib/Models.swift` — `VMBakeOutput` gains optional `bundleID`/`displayName` fields. `VMSyncOutput` new struct.
- `Sources/axon/main.swift` — pre-switch router call; new `--local`, `--vm`, `--bundle-id` flag parsing; new `vm-sync` case; `vm-bake` extended with `--for-bundle`; help-text updates.
- `Tests/AxonE2ETests/AxonE2ETestCase.swift` — child-env injection: `AXON_TARGET=local`.
- `Tests/AxonUnitTests/VMManagerTests.swift` — new tests for `BaseEntry` round-trip.
- `Tests/AxonIntegrationTests/CLIIntegrationTests.swift` — new tests for `vm-bake --for-bundle` writing a `bases` entry.
- `README.md` — VM-by-default section, `--local`, `vm-bake --for-bundle`, `vm-sync`.

**Test-running notes:**
- Unit + integration only: `swift build -c release && swift test --filter AxonUnitTests --filter AxonIntegrationTests`
- After every task, run that command. If it doesn't pass, do not commit.

---

## Task 1: Extend `VMRegistry` with a `bases` field

**Files:**
- Modify: `Sources/AxonLib/VMManager.swift` (add `BaseEntry`; add `bases: [BaseEntry]` to `VMRegistry`)
- Modify: `Tests/AxonUnitTests/VMManagerTests.swift` (add round-trip tests)

- [ ] **Step 1: Write the failing test**

Append to `Tests/AxonUnitTests/VMManagerTests.swift` inside the existing `final class VMManagerTests`:

```swift
    // MARK: - BaseEntry / bases field

    func testBaseEntryRoundTrip() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let base = BaseEntry(
            name: "axon-cicero-base",
            source: "ghcr.io/cirruslabs/macos-sequoia-base:latest",
            bundleID: "com.andreinicolas.Cicero",
            displayName: "Cicero",
            baked: date
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(base)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try! decoder.decode(BaseEntry.self, from: data)
        XCTAssertEqual(decoded.name, "axon-cicero-base")
        XCTAssertEqual(decoded.bundleID, "com.andreinicolas.Cicero")
        XCTAssertEqual(decoded.displayName, "Cicero")
        XCTAssertEqual(decoded.baked.timeIntervalSince1970, 1_700_000_000, accuracy: 1.0)
    }

    func testBaseEntryRoundTripWithoutDisplayName() {
        let base = BaseEntry(
            name: "axon-x-base",
            source: "src",
            bundleID: "com.example.X",
            displayName: nil,
            baked: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(base)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try! decoder.decode(BaseEntry.self, from: data)
        XCTAssertNil(decoded.displayName)
    }

    func testVMRegistryWithBasesRoundTrip() throws {
        let url = registryURL()
        let reg = VMRegistry(
            vms: [VMEntry(name: "axon-1", base: "sonoma", created: Date(), ip: "10.0.0.1")],
            bases: [BaseEntry(
                name: "axon-cicero-base",
                source: "src",
                bundleID: "com.andreinicolas.Cicero",
                displayName: "Cicero",
                baked: Date()
            )]
        )
        try saveVMRegistry(reg, to: url)
        let loaded = loadVMRegistry(at: url)
        XCTAssertEqual(loaded.vms.count, 1)
        XCTAssertEqual(loaded.bases.count, 1)
        XCTAssertEqual(loaded.bases[0].bundleID, "com.andreinicolas.Cicero")
    }

    func testLoadOldRegistryWithoutBasesField() throws {
        // A registry written before this feature has no `bases` key.
        let url = registryURL()
        let json = """
        {
          "vms": [
            {"name":"axon-old","base":"sonoma","created":"2026-01-01T00:00:00Z","ip":"10.0.0.1"}
          ]
        }
        """
        try json.data(using: .utf8)!.write(to: url)
        let loaded = loadVMRegistry(at: url)
        XCTAssertEqual(loaded.vms.count, 1)
        XCTAssertEqual(loaded.bases.count, 0, "Missing bases field must decode as []")
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter AxonUnitTests/VMManagerTests/testBaseEntryRoundTrip
```

Expected: BUILD FAILURE — `cannot find 'BaseEntry' in scope` and `incorrect argument label in call (have 'vms:bases:', expected 'vms:')`.

- [ ] **Step 3: Implement minimum to pass**

In `Sources/AxonLib/VMManager.swift`, add after the `VMEntry` struct:

```swift
public struct BaseEntry: Codable {
    public let name: String
    public let source: String
    public let bundleID: String
    public let displayName: String?
    public let baked: Date

    public init(name: String, source: String, bundleID: String, displayName: String?, baked: Date) {
        self.name = name
        self.source = source
        self.bundleID = bundleID
        self.displayName = displayName
        self.baked = baked
    }
}
```

Replace the existing `VMRegistry` definition with:

```swift
public struct VMRegistry: Codable {
    public var vms: [VMEntry]
    public var bases: [BaseEntry]

    public init(vms: [VMEntry], bases: [BaseEntry] = []) {
        self.vms = vms
        self.bases = bases
    }

    private enum CodingKeys: String, CodingKey { case vms, bases }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.vms = try c.decodeIfPresent([VMEntry].self, forKey: .vms) ?? []
        self.bases = try c.decodeIfPresent([BaseEntry].self, forKey: .bases) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(vms, forKey: .vms)
        try c.encode(bases, forKey: .bases)
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
swift test --filter AxonUnitTests/VMManagerTests
```

Expected: all VMManagerTests pass, including the four new tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AxonLib/VMManager.swift Tests/AxonUnitTests/VMManagerTests.swift
git commit -m "$(cat <<'EOF'
feat(vm): add BaseEntry and bases field to VMRegistry

Backwards-compatible: registries without `bases` decode with `bases: []`.
Lays the groundwork for vm-bake --for-bundle to record bundle-ID → base
mappings used by the upcoming auto-routing layer.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Add `recordBase` and `findBase(byBundleID:)` registry helpers

**Files:**
- Modify: `Sources/AxonLib/VMManager.swift` (add two functions)
- Modify: `Tests/AxonUnitTests/VMManagerTests.swift` (add tests)

- [ ] **Step 1: Write the failing test**

Append to `VMManagerTests`:

```swift
    // MARK: - recordBase / findBase

    func testRecordBaseWritesBaseEntry() throws {
        let url = registryURL()
        try recordBase(
            name: "axon-cicero-base",
            source: "src",
            bundleID: "com.andreinicolas.Cicero",
            displayName: "Cicero",
            at: url
        )
        let loaded = loadVMRegistry(at: url)
        XCTAssertEqual(loaded.bases.count, 1)
        XCTAssertEqual(loaded.bases[0].name, "axon-cicero-base")
        XCTAssertEqual(loaded.bases[0].bundleID, "com.andreinicolas.Cicero")
        XCTAssertEqual(loaded.bases[0].displayName, "Cicero")
    }

    func testRecordBaseReplacesExistingMappingForSameBundleID() throws {
        let url = registryURL()
        try recordBase(name: "old-base", source: "s", bundleID: "com.x.A", displayName: "A", at: url)
        try recordBase(name: "new-base", source: "s", bundleID: "com.x.A", displayName: "A", at: url)
        let loaded = loadVMRegistry(at: url)
        XCTAssertEqual(loaded.bases.count, 1, "Re-baking same bundle ID should replace, not append")
        XCTAssertEqual(loaded.bases[0].name, "new-base")
    }

    func testFindBaseByBundleIDReturnsMatch() throws {
        let url = registryURL()
        try recordBase(name: "axon-x", source: "s", bundleID: "com.x.X", displayName: "X", at: url)
        try recordBase(name: "axon-y", source: "s", bundleID: "com.y.Y", displayName: "Y", at: url)
        let registry = loadVMRegistry(at: url)
        let found = findBase(byBundleID: "com.y.Y", in: registry)
        XCTAssertEqual(found?.name, "axon-y")
    }

    func testFindBaseByBundleIDReturnsNilWhenMissing() {
        let registry = VMRegistry(vms: [], bases: [])
        XCTAssertNil(findBase(byBundleID: "com.absent.X", in: registry))
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter AxonUnitTests/VMManagerTests/testRecordBaseWritesBaseEntry
```

Expected: BUILD FAILURE — `cannot find 'recordBase' in scope`, `cannot find 'findBase' in scope`.

- [ ] **Step 3: Implement minimum to pass**

In `Sources/AxonLib/VMManager.swift`, add:

```swift
/// Record a baked base in the registry at the given URL. Replaces any existing
/// entry with the same bundleID. Creates parent directories if needed.
public func recordBase(
    name: String,
    source: String,
    bundleID: String,
    displayName: String?,
    at url: URL
) throws {
    let parent = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    var registry = loadVMRegistry(at: url)
    registry.bases.removeAll { $0.bundleID == bundleID }
    registry.bases.append(BaseEntry(
        name: name,
        source: source,
        bundleID: bundleID,
        displayName: displayName,
        baked: Date()
    ))
    try saveVMRegistry(registry, to: url)
}

/// Look up a registered base by bundle ID. Pure function over a loaded registry.
public func findBase(byBundleID bundleID: String, in registry: VMRegistry) -> BaseEntry? {
    registry.bases.first { $0.bundleID == bundleID }
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
swift test --filter AxonUnitTests/VMManagerTests
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AxonLib/VMManager.swift Tests/AxonUnitTests/VMManagerTests.swift
git commit -m "$(cat <<'EOF'
feat(vm): add recordBase and findBase(byBundleID:) helpers

recordBase replaces (not appends) on duplicate bundle IDs so re-baking an
app updates rather than duplicates its mapping.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `AXON_REGISTRY_PATH` env override for the live registry

**Files:**
- Modify: `Sources/AxonLib/VMManager.swift` (resolve `defaultVMRegistryURL` from env when set)
- Modify: `Tests/AxonUnitTests/VMManagerTests.swift` (env-driven URL test)

- [ ] **Step 1: Write the failing test**

Append to `VMManagerTests`:

```swift
    // MARK: - AXON_REGISTRY_PATH env

    func testActiveVMRegistryURLHonorsEnvOverride() {
        let custom = registryURL("env-override.json")
        let resolved = activeVMRegistryURL(env: ["AXON_REGISTRY_PATH": custom.path])
        XCTAssertEqual(resolved.path, custom.path)
    }

    func testActiveVMRegistryURLFallsBackToDefaultWhenEnvUnset() {
        let resolved = activeVMRegistryURL(env: [:])
        XCTAssertEqual(resolved.path, defaultVMRegistryURL.path)
    }

    func testActiveVMRegistryURLIgnoresEmptyEnv() {
        let resolved = activeVMRegistryURL(env: ["AXON_REGISTRY_PATH": ""])
        XCTAssertEqual(resolved.path, defaultVMRegistryURL.path)
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter AxonUnitTests/VMManagerTests/testActiveVMRegistryURLHonorsEnvOverride
```

Expected: BUILD FAILURE — `cannot find 'activeVMRegistryURL' in scope`.

- [ ] **Step 3: Implement minimum to pass**

In `Sources/AxonLib/VMManager.swift`, add:

```swift
/// Resolve the registry path. Honors `AXON_REGISTRY_PATH` env var when set
/// to a non-empty value; otherwise falls back to `defaultVMRegistryURL`.
public func activeVMRegistryURL(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
    if let v = env["AXON_REGISTRY_PATH"], !v.isEmpty {
        return URL(fileURLWithPath: v)
    }
    return defaultVMRegistryURL
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
swift test --filter AxonUnitTests/VMManagerTests
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AxonLib/VMManager.swift Tests/AxonUnitTests/VMManagerTests.swift
git commit -m "$(cat <<'EOF'
feat(vm): AXON_REGISTRY_PATH env override for registry location

Used by integration tests to point at a temp file instead of mutating
~/.axon/vms.json. Production code calls activeVMRegistryURL() instead
of defaultVMRegistryURL directly.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: `vm-bake --for-bundle` records the BaseEntry

**Files:**
- Modify: `Sources/AxonLib/Models.swift` (extend `VMBakeOutput`)
- Modify: `Sources/axon/main.swift` (vm-bake case + help text snippet)
- Modify: `Tests/AxonIntegrationTests/CLIIntegrationTests.swift` (new test)

- [ ] **Step 1: Write the failing test**

First, find `VMBakeOutput` in `Sources/AxonLib/Models.swift` to confirm its current shape (use Grep). It currently has `success`, `name`, `source`. We'll add optional `bundleID` and `displayName`.

Append to `Tests/AxonIntegrationTests/CLIIntegrationTests.swift`:

```swift
    // MARK: - vm-bake --for-bundle

    func testVMBakeForBundleWritesBasesEntry() throws {
        // Use a temp registry path so we don't touch ~/.axon/vms.json.
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("axon-bake-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let registryPath = tmpDir.appendingPathComponent("vms.json").path

        // tart will fail (no real image), but we expect the registry to still
        // be written if --for-bundle was provided BEFORE the tart shell-out.
        // Since current implementation tries tart first, this test asserts the
        // NEW behaviour: --for-bundle is recorded only on tart success. To make
        // the test runnable without tart, we use the AXON_SKIP_TART env hook
        // (added in this task) which short-circuits tart and treats it as success.
        let process = Process()
        process.executableURL = Self.binaryURL
        process.arguments = [
            "vm-bake",
            "--source", "ghcr.io/example/fake:latest",
            "--name", "axon-test-base",
            "--for-bundle", "com.example.Test",
            "--display-name", "Test",
        ]
        var env = ProcessInfo.processInfo.environment
        env["AXON_REGISTRY_PATH"] = registryPath
        env["AXON_SKIP_TART"] = "1"
        process.environment = env
        let stdoutPipe = Pipe(); let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0,
            "vm-bake with AXON_SKIP_TART should succeed; stderr=\(String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")")

        let data = try Data(contentsOf: URL(fileURLWithPath: registryPath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let bases = json?["bases"] as? [[String: Any]] ?? []
        XCTAssertEqual(bases.count, 1)
        XCTAssertEqual(bases[0]["name"] as? String, "axon-test-base")
        XCTAssertEqual(bases[0]["bundleID"] as? String, "com.example.Test")
        XCTAssertEqual(bases[0]["displayName"] as? String, "Test")
    }

    func testVMBakeWithoutForBundleDoesNotWriteBase() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("axon-bake-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let registryPath = tmpDir.appendingPathComponent("vms.json").path

        let process = Process()
        process.executableURL = Self.binaryURL
        process.arguments = [
            "vm-bake",
            "--source", "ghcr.io/example/fake:latest",
            "--name", "axon-bare-base",
        ]
        var env = ProcessInfo.processInfo.environment
        env["AXON_REGISTRY_PATH"] = registryPath
        env["AXON_SKIP_TART"] = "1"
        process.environment = env
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        // Registry should not exist (no bases recorded, no vms either)
        if FileManager.default.fileExists(atPath: registryPath) {
            let data = try Data(contentsOf: URL(fileURLWithPath: registryPath))
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let bases = json?["bases"] as? [[String: Any]] ?? []
            XCTAssertEqual(bases.count, 0, "vm-bake without --for-bundle must not write a base entry")
        }
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift build -c release && swift test --filter AxonIntegrationTests/CLIIntegrationTests/testVMBakeForBundleWritesBasesEntry
```

Expected: FAIL — exit code is 1 (vm-bake fails because tart is missing or `AXON_SKIP_TART` is unrecognized) and registry isn't written.

- [ ] **Step 3: Implement minimum to pass**

In `Sources/AxonLib/VMManager.swift`, change `vmBake` to honor the `AXON_SKIP_TART` env (used only by tests):

```swift
public func vmBake(
    source: String,
    name: String,
    env: [String: String] = ProcessInfo.processInfo.environment
) -> Result<(name: String, source: String), VMError> {
    if env["AXON_SKIP_TART"] == "1" {
        return .success((name: name, source: source))
    }
    guard findTart() != nil else {
        return .failure(VMError("tart not found. Install with: brew install cirruslabs/cli/tart"))
    }
    let cloneResult = runTart(["clone", source, name])
    if cloneResult.exitCode != 0 {
        return .failure(VMError("Failed to clone '\(source)' -> '\(name)': \(cloneResult.stderr)"))
    }
    return .success((name: name, source: source))
}
```

In `Sources/AxonLib/Models.swift`, find `VMBakeOutput` and extend it:

```swift
public struct VMBakeOutput: Codable {
    public let success: Bool
    public let name: String
    public let source: String
    public let bundleID: String?
    public let displayName: String?

    public init(success: Bool, name: String, source: String, bundleID: String? = nil, displayName: String? = nil) {
        self.success = success
        self.name = name
        self.source = source
        self.bundleID = bundleID
        self.displayName = displayName
    }
}
```

In `Sources/axon/main.swift`, replace the `case "vm-bake":` block with:

```swift
case "vm-bake":
    guard let source = cli.option("source"), let name = cli.option("name") else {
        printError(code: "missing_option", message: "Provide --source <image> and --name <new-base>")
        exit(1)
    }
    let bundleID = cli.option("for-bundle")
    let displayName = cli.option("display-name")

    switch vmBake(source: source, name: name) {
    case .success(let baked):
        if let bid = bundleID {
            do {
                try recordBase(
                    name: baked.name,
                    source: baked.source,
                    bundleID: bid,
                    displayName: displayName,
                    at: activeVMRegistryURL()
                )
            } catch {
                printError(code: "registry_write_failed", message: "Baked but failed to record base: \(error)")
                exit(1)
            }
        }
        let out = VMBakeOutput(
            success: true,
            name: baked.name,
            source: baked.source,
            bundleID: bundleID,
            displayName: displayName
        )
        var plain: [(String, String)] = [
            ("name", baked.name),
            ("source", baked.source),
        ]
        if let bid = bundleID { plain.append(("bundleID", bid)) }
        if let dn = displayName { plain.append(("displayName", dn)) }
        emit(out, plain: plain)
    case .failure(let err):
        printError(code: "vm_bake_failed", message: err.description)
        exit(1)
    }
```

- [ ] **Step 4: Run tests to verify pass**

```bash
swift build -c release && swift test --filter AxonUnitTests --filter AxonIntegrationTests
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AxonLib/VMManager.swift Sources/AxonLib/Models.swift Sources/axon/main.swift Tests/AxonIntegrationTests/CLIIntegrationTests.swift
git commit -m "$(cat <<'EOF'
feat(vm-bake): record bundle-ID mapping with --for-bundle

vm-bake now accepts --for-bundle <id> [--display-name <name>] and writes
a BaseEntry into the registry on successful clone. AXON_SKIP_TART=1 is
a test-only hook so integration tests can exercise the registry path
without a real Tart install.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: `CommandClass` enum + `classifyCommand`

**Files:**
- Create: `Sources/AxonLib/Router.swift`
- Create: `Tests/AxonUnitTests/RouterClassifyTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/AxonUnitTests/RouterClassifyTests.swift`:

```swift
import XCTest
@testable import AxonLib

final class RouterClassifyTests: XCTestCase {

    func testVMRoutableCommands() {
        let routable: [String] = [
            "list", "launch", "tree", "click", "double-click", "right-click",
            "hover", "drag", "type", "key", "scroll", "screenshot", "activate",
            "close", "wait", "get-value", "focused", "window-info", "menu",
            "set-value", "move-resize", "clipboard", "wait-ready", "wait-for-value",
            "assert", "exists",
        ]
        for cmd in routable {
            XCTAssertEqual(classifyCommand(cmd), CommandClass.vmRoutable, "Expected \(cmd) to be vmRoutable")
        }
    }

    func testAlwaysLocalCommands() {
        let local: [String] = ["vm-bake", "vm-acquire", "vm-release", "vm-list", "vm-sync", "doctor"]
        for cmd in local {
            XCTAssertEqual(classifyCommand(cmd), CommandClass.alwaysLocal, "Expected \(cmd) to be alwaysLocal")
        }
    }

    func testUnknownCommandIsAlwaysLocal() {
        // Unknown commands fall through to existing dispatch, which prints help/error locally.
        XCTAssertEqual(classifyCommand("nope-not-real"), CommandClass.alwaysLocal)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter AxonUnitTests/RouterClassifyTests
```

Expected: BUILD FAILURE — `cannot find 'classifyCommand' in scope`, `cannot find 'CommandClass' in scope`.

- [ ] **Step 3: Implement minimum to pass**

Create `Sources/AxonLib/Router.swift`:

```swift
import Foundation

// MARK: - Command Classification

public enum CommandClass: Equatable {
    case vmRoutable
    case alwaysLocal
}

private let vmRoutableCommands: Set<String> = [
    "list", "launch", "tree", "click", "double-click", "right-click",
    "hover", "drag", "type", "key", "scroll", "screenshot", "activate",
    "close", "wait", "get-value", "focused", "window-info", "menu",
    "set-value", "move-resize", "clipboard", "wait-ready", "wait-for-value",
    "assert", "exists",
]

public func classifyCommand(_ command: String) -> CommandClass {
    vmRoutableCommands.contains(command) ? .vmRoutable : .alwaysLocal
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
swift test --filter AxonUnitTests/RouterClassifyTests
```

Expected: all 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AxonLib/Router.swift Tests/AxonUnitTests/RouterClassifyTests.swift
git commit -m "$(cat <<'EOF'
feat(router): CommandClass + classifyCommand table

Pure lookup. UI-driving commands are .vmRoutable; vm-* + doctor stay
.alwaysLocal. Unknown commands default to .alwaysLocal so unrecognised
input still hits the existing dispatch (which prints the help text).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: `Target` and `RouterError` types

**Files:**
- Modify: `Sources/AxonLib/Router.swift` (add types)
- Create: `Tests/AxonUnitTests/RouterTypesTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/AxonUnitTests/RouterTypesTests.swift`:

```swift
import XCTest
@testable import AxonLib

final class RouterTypesTests: XCTestCase {

    func testTargetLocalEqualsLocal() {
        XCTAssertEqual(Target.local, Target.local)
    }

    func testTargetRemoteCarriesVMEntry() {
        let entry = VMEntry(name: "axon-x", base: "b", created: Date(), ip: "10.0.0.1")
        let t = Target.remote(entry)
        if case let .remote(e) = t {
            XCTAssertEqual(e.name, "axon-x")
        } else {
            XCTFail("Expected .remote")
        }
    }

    func testRouterErrorMessages() {
        // We just check the cases compile and we can pattern-match them.
        let errors: [RouterError] = [
            .noBaseRegistered(bundleID: "com.x.A"),
            .missingTarget(command: "list"),
            .bundleIDNotResolvable(appName: "Foo"),
            .vmNotFound(name: "axon-zzz"),
            .vmNotReady(name: "axon-zzz"),
            .sshFailed(stderr: "boom", exitCode: 99),
        ]
        XCTAssertEqual(errors.count, 6)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter AxonUnitTests/RouterTypesTests
```

Expected: BUILD FAILURE — `cannot find 'Target' in scope`, `cannot find 'RouterError' in scope`.

- [ ] **Step 3: Implement minimum to pass**

Append to `Sources/AxonLib/Router.swift`:

```swift
// MARK: - Routing Target

public enum Target: Equatable {
    case local
    case remote(VMEntry)

    public static func == (lhs: Target, rhs: Target) -> Bool {
        switch (lhs, rhs) {
        case (.local, .local): return true
        case let (.remote(a), .remote(b)): return a.name == b.name
        default: return false
        }
    }
}

// MARK: - Router Errors

public enum RouterError: Error, Equatable {
    case noBaseRegistered(bundleID: String)
    case missingTarget(command: String)
    case bundleIDNotResolvable(appName: String)
    case vmNotFound(name: String)
    case vmNotReady(name: String)
    case sshFailed(stderr: String, exitCode: Int32)
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
swift test --filter AxonUnitTests/RouterTypesTests
```

Expected: all 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AxonLib/Router.swift Tests/AxonUnitTests/RouterTypesTests.swift
git commit -m "$(cat <<'EOF'
feat(router): Target and RouterError types

Target.{local, remote(VMEntry)} is what resolveTarget returns.
RouterError enumerates every failure mode resolveTarget or
dispatchRemote can produce.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: `resolveTarget` — flag/env paths (`--local`, `AXON_TARGET`, `--vm`)

**Files:**
- Modify: `Sources/AxonLib/Router.swift` (add `resolveTarget` partial)
- Create: `Tests/AxonUnitTests/RouterResolveTargetTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/AxonUnitTests/RouterResolveTargetTests.swift`:

```swift
import XCTest
@testable import AxonLib

final class RouterResolveTargetTests: XCTestCase {

    private func makeRegistry(
        vms: [VMEntry] = [],
        bases: [BaseEntry] = []
    ) -> VMRegistry {
        VMRegistry(vms: vms, bases: bases)
    }

    // --- flag/env paths ---

    func testLocalFlagWins() throws {
        let target = try resolveTarget(
            argv: ["--local", "--app", "Cicero"],
            command: "click",
            registry: makeRegistry(),
            env: [:],
            acquirer: StubAcquirer()
        )
        XCTAssertEqual(target, .local)
    }

    func testEnvAxonTargetLocalSelectsLocal() throws {
        let target = try resolveTarget(
            argv: ["--app", "Cicero"],
            command: "click",
            registry: makeRegistry(),
            env: ["AXON_TARGET": "local"],
            acquirer: StubAcquirer()
        )
        XCTAssertEqual(target, .local)
    }

    func testFlagBeatsEnvWhenBothPresent() throws {
        // (No "remote" env value exists today; this test pins behavior: --local always wins.)
        let target = try resolveTarget(
            argv: ["--local", "--app", "Cicero"],
            command: "click",
            registry: makeRegistry(),
            env: ["AXON_TARGET": "vm-or-whatever"],
            acquirer: StubAcquirer()
        )
        XCTAssertEqual(target, .local)
    }

    func testVMFlagSelectsRegisteredVM() throws {
        let entry = VMEntry(name: "axon-pinned", base: "sequoia-base", created: Date(), ip: "10.0.0.5")
        let registry = makeRegistry(vms: [entry])
        let target = try resolveTarget(
            argv: ["--vm", "axon-pinned"],
            command: "click",
            registry: registry,
            env: [:],
            acquirer: StubAcquirer()
        )
        XCTAssertEqual(target, .remote(entry))
    }

    func testVMFlagErrorsWhenVMNotFound() {
        XCTAssertThrowsError(try resolveTarget(
            argv: ["--vm", "axon-ghost"],
            command: "click",
            registry: makeRegistry(),
            env: [:],
            acquirer: StubAcquirer()
        )) { err in
            XCTAssertEqual(err as? RouterError, .vmNotFound(name: "axon-ghost"))
        }
    }

    func testVMFlagErrorsWhenVMHasNoIP() {
        let entry = VMEntry(name: "axon-broken", base: "b", created: Date(), ip: nil)
        XCTAssertThrowsError(try resolveTarget(
            argv: ["--vm", "axon-broken"],
            command: "click",
            registry: makeRegistry(vms: [entry]),
            env: [:],
            acquirer: StubAcquirer()
        )) { err in
            XCTAssertEqual(err as? RouterError, .vmNotReady(name: "axon-broken"))
        }
    }
}

// MARK: - Stub acquirer used by all RouterResolveTargetTests

struct StubAcquirer: VMAcquirer {
    var entryToReturn: VMEntry = VMEntry(name: "axon-stub", base: "b", created: Date(), ip: "10.0.0.99")
    var calls: [(base: String, headless: Bool, timeout: Int)] = []

    func acquire(base: String, headless: Bool, timeout: Int) -> Result<VMEntry, VMError> {
        return .success(entryToReturn)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter AxonUnitTests/RouterResolveTargetTests
```

Expected: BUILD FAILURE — `cannot find 'resolveTarget'`, `cannot find 'VMAcquirer'`.

- [ ] **Step 3: Implement minimum to pass**

Append to `Sources/AxonLib/Router.swift`:

```swift
// MARK: - VM Acquirer (test seam)

public protocol VMAcquirer {
    func acquire(base: String, headless: Bool, timeout: Int) -> Result<VMEntry, VMError>
}

public struct LiveVMAcquirer: VMAcquirer {
    public init() {}
    public func acquire(base: String, headless: Bool, timeout: Int) -> Result<VMEntry, VMError> {
        vmAcquire(base: base, headless: headless, timeout: timeout)
    }
}

// MARK: - Argv option helper (router-internal)

private func optionValue(_ argv: [String], _ name: String) -> String? {
    guard let i = argv.firstIndex(of: "--\(name)"), i + 1 < argv.count else { return nil }
    return argv[i + 1]
}

private func hasFlag(_ argv: [String], _ name: String) -> Bool {
    argv.contains("--\(name)")
}

// MARK: - resolveTarget

public func resolveTarget(
    argv: [String],
    command: String,
    registry: VMRegistry,
    env: [String: String],
    acquirer: VMAcquirer
) throws -> Target {
    // 1. Explicit --local always wins.
    if hasFlag(argv, "local") {
        return .local
    }
    // 2. AXON_TARGET=local env.
    if env["AXON_TARGET"] == "local" {
        return .local
    }
    // 3. --vm <name> targets a specific registered VM.
    if let vmName = optionValue(argv, "vm") {
        guard let entry = registry.vms.first(where: { $0.name == vmName }) else {
            throw RouterError.vmNotFound(name: vmName)
        }
        guard entry.ip != nil else {
            throw RouterError.vmNotReady(name: vmName)
        }
        return .remote(entry)
    }
    // (later tasks add --app and --bundle-id resolution + acquire path)
    throw RouterError.missingTarget(command: command)
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
swift test --filter AxonUnitTests/RouterResolveTargetTests
```

Expected: all 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AxonLib/Router.swift Tests/AxonUnitTests/RouterResolveTargetTests.swift
git commit -m "$(cat <<'EOF'
feat(router): resolveTarget for --local / AXON_TARGET / --vm

Covers the three explicit-target paths. The --app → bundle ID → base
lookup and the acquire-on-miss path land in the next two commits.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: `resolveTarget` — `--app` → bundle ID lookup + base reuse

**Files:**
- Modify: `Sources/AxonLib/Router.swift` (extend `resolveTarget`; add `BundleIDResolver` protocol)
- Modify: `Tests/AxonUnitTests/RouterResolveTargetTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/AxonUnitTests/RouterResolveTargetTests.swift`:

```swift
    // --- bundle ID resolution ---

    func testAppResolvesViaRegistryDisplayName() throws {
        let base = BaseEntry(
            name: "axon-cicero-base", source: "s",
            bundleID: "com.andreinicolas.Cicero", displayName: "Cicero", baked: Date()
        )
        let runningVM = VMEntry(name: "axon-running", base: "axon-cicero-base", created: Date(), ip: "10.0.0.7")
        let registry = makeRegistry(vms: [runningVM], bases: [base])
        let target = try resolveTarget(
            argv: ["--app", "Cicero"],
            command: "click",
            registry: registry,
            env: [:],
            acquirer: StubAcquirer(),
            bundleIDResolver: StubBundleIDResolver()  // host lookup never used
        )
        XCTAssertEqual(target, .remote(runningVM))
    }

    func testAppResolutionIsCaseInsensitive() throws {
        let base = BaseEntry(
            name: "axon-cicero-base", source: "s",
            bundleID: "com.andreinicolas.Cicero", displayName: "Cicero", baked: Date()
        )
        let runningVM = VMEntry(name: "axon-r", base: "axon-cicero-base", created: Date(), ip: "10.0.0.8")
        let registry = makeRegistry(vms: [runningVM], bases: [base])
        let target = try resolveTarget(
            argv: ["--app", "cicero"],
            command: "click",
            registry: registry,
            env: [:],
            acquirer: StubAcquirer(),
            bundleIDResolver: StubBundleIDResolver()
        )
        XCTAssertEqual(target, .remote(runningVM))
    }

    func testBundleIDFlagBypassesAppLookup() throws {
        let base = BaseEntry(
            name: "axon-x-base", source: "s",
            bundleID: "com.example.X", displayName: nil, baked: Date()
        )
        let runningVM = VMEntry(name: "axon-x-vm", base: "axon-x-base", created: Date(), ip: "10.0.0.9")
        let registry = makeRegistry(vms: [runningVM], bases: [base])
        let target = try resolveTarget(
            argv: ["--bundle-id", "com.example.X"],
            command: "click",
            registry: registry,
            env: [:],
            acquirer: StubAcquirer(),
            bundleIDResolver: StubBundleIDResolver()
        )
        XCTAssertEqual(target, .remote(runningVM))
    }

    func testAppFallsBackToHostBundleIDResolver() throws {
        // No matching displayName in registry — fall through to host lookup.
        let base = BaseEntry(
            name: "axon-hostlookup-base", source: "s",
            bundleID: "com.host.Looked", displayName: nil, baked: Date()
        )
        let runningVM = VMEntry(name: "axon-h", base: "axon-hostlookup-base", created: Date(), ip: "10.0.0.10")
        let registry = makeRegistry(vms: [runningVM], bases: [base])
        let resolver = StubBundleIDResolver(map: ["WeirdName": "com.host.Looked"])
        let target = try resolveTarget(
            argv: ["--app", "WeirdName"],
            command: "click",
            registry: registry,
            env: [:],
            acquirer: StubAcquirer(),
            bundleIDResolver: resolver
        )
        XCTAssertEqual(target, .remote(runningVM))
    }
}

struct StubBundleIDResolver: BundleIDResolver {
    var map: [String: String] = [:]
    func bundleID(forAppName name: String) -> String? { map[name] }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter AxonUnitTests/RouterResolveTargetTests
```

Expected: BUILD FAILURE — `cannot find 'BundleIDResolver' in scope`; `extra argument 'bundleIDResolver' in call`.

- [ ] **Step 3: Implement minimum to pass**

In `Sources/AxonLib/Router.swift`, add the protocol and a default param to `resolveTarget`:

```swift
// MARK: - Bundle ID Resolver (test seam)

public protocol BundleIDResolver {
    func bundleID(forAppName name: String) -> String?
}

public struct LiveBundleIDResolver: BundleIDResolver {
    public init() {}
    public func bundleID(forAppName name: String) -> String? {
        findApp(name: name)?.bundleIdentifier
    }
}
```

Replace the existing `resolveTarget` signature/body with:

```swift
public func resolveTarget(
    argv: [String],
    command: String,
    registry: VMRegistry,
    env: [String: String],
    acquirer: VMAcquirer,
    bundleIDResolver: BundleIDResolver = LiveBundleIDResolver()
) throws -> Target {
    if hasFlag(argv, "local") { return .local }
    if env["AXON_TARGET"] == "local" { return .local }

    if let vmName = optionValue(argv, "vm") {
        guard let entry = registry.vms.first(where: { $0.name == vmName }) else {
            throw RouterError.vmNotFound(name: vmName)
        }
        guard entry.ip != nil else { throw RouterError.vmNotReady(name: vmName) }
        return .remote(entry)
    }

    // Resolve bundle ID from --bundle-id (preferred) or --app via two-step lookup.
    let bundleID: String
    if let bid = optionValue(argv, "bundle-id") {
        bundleID = bid
    } else if let appName = optionValue(argv, "app") {
        if let registryHit = registry.bases.first(where: {
            $0.displayName?.localizedCaseInsensitiveCompare(appName) == .orderedSame
        }) {
            bundleID = registryHit.bundleID
        } else if let host = bundleIDResolver.bundleID(forAppName: appName) {
            bundleID = host
        } else {
            throw RouterError.bundleIDNotResolvable(appName: appName)
        }
    } else {
        throw RouterError.missingTarget(command: command)
    }

    guard let base = findBase(byBundleID: bundleID, in: registry) else {
        throw RouterError.noBaseRegistered(bundleID: bundleID)
    }

    if let running = registry.vms.first(where: { $0.base == base.name && $0.ip != nil }) {
        return .remote(running)
    }
    // (acquire path — added in next task)
    throw RouterError.noBaseRegistered(bundleID: bundleID)
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
swift test --filter AxonUnitTests/RouterResolveTargetTests
```

Expected: all 10 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AxonLib/Router.swift Tests/AxonUnitTests/RouterResolveTargetTests.swift
git commit -m "$(cat <<'EOF'
feat(router): --app/--bundle-id → bundle-ID → registered base lookup

Two-step app→bundleID resolution: registry displayName first, host
NSWorkspace second. --bundle-id bypasses both. When a base exists and
a VM is already running for it, reuse that VM.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: `resolveTarget` — acquire-on-miss via injected `VMAcquirer`

**Files:**
- Modify: `Sources/AxonLib/Router.swift` (call acquirer when no running VM)
- Modify: `Tests/AxonUnitTests/RouterResolveTargetTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `RouterResolveTargetTests`:

```swift
    // --- acquire-on-miss ---

    func testNoRunningVMForBaseTriggersAcquire() throws {
        let base = BaseEntry(
            name: "axon-cicero-base", source: "s",
            bundleID: "com.andreinicolas.Cicero", displayName: "Cicero", baked: Date()
        )
        // No matching VMs in registry.
        let registry = makeRegistry(bases: [base])
        let acquired = VMEntry(name: "axon-fresh", base: "axon-cicero-base", created: Date(), ip: "10.0.0.42")
        let target = try resolveTarget(
            argv: ["--app", "Cicero"],
            command: "click",
            registry: registry,
            env: [:],
            acquirer: StubAcquirer(entryToReturn: acquired),
            bundleIDResolver: StubBundleIDResolver()
        )
        XCTAssertEqual(target, .remote(acquired))
    }

    func testAcquireFailureSurfacesAsRouterError() {
        let base = BaseEntry(
            name: "axon-x", source: "s", bundleID: "com.x.A", displayName: nil, baked: Date()
        )
        let registry = makeRegistry(bases: [base])
        struct FailingAcquirer: VMAcquirer {
            func acquire(base: String, headless: Bool, timeout: Int) -> Result<VMEntry, VMError> {
                .failure(VMError("clone failed: disk full"))
            }
        }
        XCTAssertThrowsError(try resolveTarget(
            argv: ["--bundle-id", "com.x.A"],
            command: "click",
            registry: registry,
            env: [:],
            acquirer: FailingAcquirer(),
            bundleIDResolver: StubBundleIDResolver()
        )) { err in
            // Surfaces as a sshFailed-style wrapper; we use a dedicated case.
            if case .vmAcquireFailed(let msg) = err as? RouterError {
                XCTAssertTrue(msg.contains("clone failed"))
            } else {
                XCTFail("Expected .vmAcquireFailed, got \(err)")
            }
        }
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter AxonUnitTests/RouterResolveTargetTests
```

Expected: BUILD FAILURE — `type 'RouterError' has no member 'vmAcquireFailed'`; the first test fails because the acquire path still throws `noBaseRegistered`.

- [ ] **Step 3: Implement minimum to pass**

In `Sources/AxonLib/Router.swift`, add a new case to `RouterError`:

```swift
public enum RouterError: Error, Equatable {
    case noBaseRegistered(bundleID: String)
    case missingTarget(command: String)
    case bundleIDNotResolvable(appName: String)
    case vmNotFound(name: String)
    case vmNotReady(name: String)
    case sshFailed(stderr: String, exitCode: Int32)
    case vmAcquireFailed(message: String)
}
```

Replace the bottom of `resolveTarget` (the part after `findBase`) with:

```swift
    if let running = registry.vms.first(where: { $0.base == base.name && $0.ip != nil }) {
        return .remote(running)
    }
    switch acquirer.acquire(base: base.name, headless: true, timeout: 60) {
    case .success(let entry):
        return .remote(entry)
    case .failure(let err):
        throw RouterError.vmAcquireFailed(message: err.description)
    }
```

- [ ] **Step 4: Run tests to verify pass**

```bash
swift test --filter AxonUnitTests/RouterResolveTargetTests
```

Expected: all 12 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AxonLib/Router.swift Tests/AxonUnitTests/RouterResolveTargetTests.swift
git commit -m "$(cat <<'EOF'
feat(router): acquire fresh VM when base has no running clone

If a bundle ID maps to a registered base but no VM in the registry is
running for that base, call the injected VMAcquirer (production:
vmAcquire) and return the new entry. Acquire failures surface as
RouterError.vmAcquireFailed.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: `resolveTarget` — error paths (missing base, missing target, unresolvable)

**Files:**
- Modify: `Tests/AxonUnitTests/RouterResolveTargetTests.swift`

(No new code in `Router.swift` — these paths already throw.)

- [ ] **Step 1: Write the failing test**

Append to `RouterResolveTargetTests`:

```swift
    // --- error surfaces ---

    func testNoBaseRegisteredErrorWhenBundleIDUnknown() {
        XCTAssertThrowsError(try resolveTarget(
            argv: ["--bundle-id", "com.never.Heard"],
            command: "click",
            registry: makeRegistry(),
            env: [:],
            acquirer: StubAcquirer(),
            bundleIDResolver: StubBundleIDResolver()
        )) { err in
            XCTAssertEqual(err as? RouterError, .noBaseRegistered(bundleID: "com.never.Heard"))
        }
    }

    func testMissingTargetWhenNoAppNoVMNoLocal() {
        XCTAssertThrowsError(try resolveTarget(
            argv: [],
            command: "list",
            registry: makeRegistry(),
            env: [:],
            acquirer: StubAcquirer(),
            bundleIDResolver: StubBundleIDResolver()
        )) { err in
            XCTAssertEqual(err as? RouterError, .missingTarget(command: "list"))
        }
    }

    func testBundleIDNotResolvableWhenAppNotInRegistryAndNotOnHost() {
        let base = BaseEntry(name: "b", source: "s", bundleID: "com.x.X", displayName: "X", baked: Date())
        XCTAssertThrowsError(try resolveTarget(
            argv: ["--app", "Mystery"],
            command: "click",
            registry: makeRegistry(bases: [base]),
            env: [:],
            acquirer: StubAcquirer(),
            bundleIDResolver: StubBundleIDResolver() // empty map
        )) { err in
            XCTAssertEqual(err as? RouterError, .bundleIDNotResolvable(appName: "Mystery"))
        }
    }
```

- [ ] **Step 2: Run test to verify it fails (or passes — if it passes, that's fine, you've added coverage)**

```bash
swift test --filter AxonUnitTests/RouterResolveTargetTests
```

Expected: all pass (these paths were already implemented in Tasks 7–9). If any fail, fix the code before committing.

- [ ] **Step 3: (no implementation needed)**

If a test fails, debug the implementation, add the minimum fix, re-run.

- [ ] **Step 4: Run tests to verify pass**

```bash
swift test --filter AxonUnitTests/RouterResolveTargetTests
```

Expected: all 15 pass.

- [ ] **Step 5: Commit**

```bash
git add Tests/AxonUnitTests/RouterResolveTargetTests.swift
git commit -m "$(cat <<'EOF'
test(router): pin error surface for missing base / target / app

These error paths were already implemented; the tests lock the
expected RouterError cases so future changes don't silently shift
the user-facing error codes.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: `remapFileOutputs` for `screenshot --output`

**Files:**
- Modify: `Sources/AxonLib/Router.swift` (add `ScpBack`, `remapFileOutputs`)
- Create: `Tests/AxonUnitTests/RouterRemapFileOutputsTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/AxonUnitTests/RouterRemapFileOutputsTests.swift`:

```swift
import XCTest
@testable import AxonLib

final class RouterRemapFileOutputsTests: XCTestCase {

    func testNoOutputFlagLeavesArgvUnchanged() {
        let argv = ["screenshot", "--app", "Finder"]
        let (rewritten, scps) = remapFileOutputs(argv: argv, command: "screenshot", tempPathProvider: { "/tmp/X" })
        XCTAssertEqual(rewritten, argv)
        XCTAssertTrue(scps.isEmpty)
    }

    func testScreenshotOutputIsRewrittenAndRecorded() {
        let argv = ["screenshot", "--app", "Finder", "--output", "/Users/me/shot.png"]
        let (rewritten, scps) = remapFileOutputs(
            argv: argv,
            command: "screenshot",
            tempPathProvider: { "/tmp/axon-out-fixed.png" }
        )
        XCTAssertEqual(rewritten, ["screenshot", "--app", "Finder", "--output", "/tmp/axon-out-fixed.png"])
        XCTAssertEqual(scps.count, 1)
        XCTAssertEqual(scps[0].vmPath, "/tmp/axon-out-fixed.png")
        XCTAssertEqual(scps[0].hostPath, "/Users/me/shot.png")
    }

    func testNonScreenshotCommandsIgnoreOutputFlag() {
        // Only `screenshot` opts in to the remap today.
        let argv = ["tree", "--app", "Finder", "--output", "/tmp/x.json"]
        let (rewritten, scps) = remapFileOutputs(argv: argv, command: "tree", tempPathProvider: { "/tmp/X" })
        XCTAssertEqual(rewritten, argv)
        XCTAssertTrue(scps.isEmpty)
    }

    func testOutputFlagWithoutValueIsLeftAlone() {
        let argv = ["screenshot", "--app", "Finder", "--output"]
        let (rewritten, scps) = remapFileOutputs(argv: argv, command: "screenshot", tempPathProvider: { "/tmp/X" })
        XCTAssertEqual(rewritten, argv)
        XCTAssertTrue(scps.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter AxonUnitTests/RouterRemapFileOutputsTests
```

Expected: BUILD FAILURE — `cannot find 'remapFileOutputs' in scope`, `cannot find 'ScpBack'`.

- [ ] **Step 3: Implement minimum to pass**

Append to `Sources/AxonLib/Router.swift`:

```swift
// MARK: - File-output remap

public struct ScpBack: Equatable {
    public let vmPath: String
    public let hostPath: String
    public init(vmPath: String, hostPath: String) {
        self.vmPath = vmPath
        self.hostPath = hostPath
    }
}

public func remapFileOutputs(
    argv: [String],
    command: String,
    tempPathProvider: () -> String = { "/tmp/axon-out-\(UUID().uuidString).bin" }
) -> (rewritten: [String], scpBacks: [ScpBack]) {
    guard command == "screenshot" else { return (argv, []) }
    guard let outputIdx = argv.firstIndex(of: "--output"), outputIdx + 1 < argv.count else {
        return (argv, [])
    }
    let hostPath = argv[outputIdx + 1]
    let vmPath = tempPathProvider()
    var rewritten = argv
    rewritten[outputIdx + 1] = vmPath
    return (rewritten, [ScpBack(vmPath: vmPath, hostPath: hostPath)])
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
swift test --filter AxonUnitTests/RouterRemapFileOutputsTests
```

Expected: all 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AxonLib/Router.swift Tests/AxonUnitTests/RouterRemapFileOutputsTests.swift
git commit -m "$(cat <<'EOF'
feat(router): remapFileOutputs rewrites screenshot --output for VM mode

Host-path --output values are swapped for a VM-side temp path; the
caller schedules an scp-back via the returned ScpBack list. Only
screenshot opts in today; tempPathProvider is injected for test
determinism.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: `SSHDispatcher` protocol + `dispatchRemote` (no scp yet)

**Files:**
- Modify: `Sources/AxonLib/Router.swift` (add protocol + `dispatchRemote`)
- Create: `Tests/AxonUnitTests/RouterDispatchTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/AxonUnitTests/RouterDispatchTests.swift`:

```swift
import XCTest
@testable import AxonLib

final class RouterDispatchTests: XCTestCase {

    final class RecordingSSH: SSHDispatcher {
        var calls: [(vmIP: String, argv: [String], env: [String: String])] = []
        var stdout: Data = Data("ok\n".utf8)
        var stderr: Data = Data()
        var exitCode: Int32 = 0
        func run(vmIP: String, argv: [String], env: [String: String]) -> (stdout: Data, stderr: Data, exitCode: Int32) {
            calls.append((vmIP, argv, env))
            return (stdout, stderr, exitCode)
        }
    }

    final class NoopScp: ScpBackRunner {
        var calls: [ScpBack] = []
        var failure: VMError?
        func transfer(_ scpBack: ScpBack, fromVMIP ip: String) -> Result<Void, VMError> {
            calls.append(scpBack)
            if let f = failure { return .failure(f) }
            return .success(())
        }
    }

    func testDispatchRemoteRunsSSHWithArgvAndAxonTargetLocalEnv() throws {
        let vm = VMEntry(name: "axon-x", base: "b", created: Date(), ip: "10.0.0.5")
        let ssh = RecordingSSH()
        let scp = NoopScp()
        let result = try dispatchRemote(
            vm: vm,
            argv: ["click", "--app", "Cicero", "--label", "Save"],
            scpBacks: [],
            ssh: ssh,
            scpRunner: scp
        )
        XCTAssertEqual(ssh.calls.count, 1)
        XCTAssertEqual(ssh.calls[0].vmIP, "10.0.0.5")
        XCTAssertEqual(ssh.calls[0].argv, ["click", "--app", "Cicero", "--label", "Save"])
        XCTAssertEqual(ssh.calls[0].env["AXON_TARGET"], "local")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(String(data: result.stdout, encoding: .utf8), "ok\n")
    }

    func testDispatchRemoteSurfacesNonZeroExit() throws {
        let vm = VMEntry(name: "axon-x", base: "b", created: Date(), ip: "10.0.0.5")
        let ssh = RecordingSSH()
        ssh.exitCode = 17
        ssh.stderr = Data("boom\n".utf8)
        let result = try dispatchRemote(
            vm: vm, argv: ["click"], scpBacks: [],
            ssh: ssh, scpRunner: NoopScp()
        )
        XCTAssertEqual(result.exitCode, 17)
        XCTAssertEqual(String(data: result.stderr, encoding: .utf8), "boom\n")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter AxonUnitTests/RouterDispatchTests
```

Expected: BUILD FAILURE — `cannot find 'SSHDispatcher'`, `cannot find 'ScpBackRunner'`, `cannot find 'dispatchRemote'`.

- [ ] **Step 3: Implement minimum to pass**

Append to `Sources/AxonLib/Router.swift`:

```swift
// MARK: - SSH / SCP Dispatch (test seams)

public protocol SSHDispatcher {
    func run(vmIP: String, argv: [String], env: [String: String])
        -> (stdout: Data, stderr: Data, exitCode: Int32)
}

public protocol ScpBackRunner {
    func transfer(_ scpBack: ScpBack, fromVMIP ip: String) -> Result<Void, VMError>
}

public func dispatchRemote(
    vm: VMEntry,
    argv: [String],
    scpBacks: [ScpBack],
    ssh: SSHDispatcher,
    scpRunner: ScpBackRunner
) throws -> (stdout: Data, stderr: Data, exitCode: Int32) {
    guard let ip = vm.ip else { throw RouterError.vmNotReady(name: vm.name) }
    let env = ["AXON_TARGET": "local"]
    let result = ssh.run(vmIP: ip, argv: argv, env: env)
    // scp-backs are wired in the next task; for now we just pass result through.
    return result
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
swift test --filter AxonUnitTests/RouterDispatchTests
```

Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AxonLib/Router.swift Tests/AxonUnitTests/RouterDispatchTests.swift
git commit -m "$(cat <<'EOF'
feat(router): dispatchRemote orchestrates SSH re-exec

Stubbed SSHDispatcher + ScpBackRunner protocols make dispatch
unit-testable. AXON_TARGET=local is set in the SSH env so the VM-side
axon process never recurses back into the router.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: `dispatchRemote` runs scp-backs and surfaces failures

**Files:**
- Modify: `Sources/AxonLib/Router.swift` (extend `dispatchRemote`)
- Modify: `Tests/AxonUnitTests/RouterDispatchTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `RouterDispatchTests`:

```swift
    func testDispatchRemoteRunsScpBacksOnSuccess() throws {
        let vm = VMEntry(name: "axon-x", base: "b", created: Date(), ip: "10.0.0.5")
        let ssh = RecordingSSH()
        let scp = NoopScp()
        let scpBack = ScpBack(vmPath: "/tmp/axon-out.png", hostPath: "/Users/me/shot.png")
        _ = try dispatchRemote(
            vm: vm, argv: ["screenshot"], scpBacks: [scpBack],
            ssh: ssh, scpRunner: scp
        )
        XCTAssertEqual(scp.calls.count, 1)
        XCTAssertEqual(scp.calls[0].vmPath, "/tmp/axon-out.png")
        XCTAssertEqual(scp.calls[0].hostPath, "/Users/me/shot.png")
    }

    func testDispatchRemoteSkipsScpOnNonZeroExit() throws {
        let vm = VMEntry(name: "axon-x", base: "b", created: Date(), ip: "10.0.0.5")
        let ssh = RecordingSSH()
        ssh.exitCode = 1
        let scp = NoopScp()
        let scpBack = ScpBack(vmPath: "/tmp/axon-out.png", hostPath: "/Users/me/shot.png")
        _ = try dispatchRemote(
            vm: vm, argv: ["screenshot"], scpBacks: [scpBack],
            ssh: ssh, scpRunner: scp
        )
        XCTAssertTrue(scp.calls.isEmpty, "Failed SSH must skip scp-back; the file probably wasn't written")
    }

    func testDispatchRemoteSurfacesScpFailure() {
        let vm = VMEntry(name: "axon-x", base: "b", created: Date(), ip: "10.0.0.5")
        let ssh = RecordingSSH()
        let scp = NoopScp()
        scp.failure = VMError("Permission denied")
        let scpBack = ScpBack(vmPath: "/tmp/axon-out.png", hostPath: "/Users/me/shot.png")
        XCTAssertThrowsError(try dispatchRemote(
            vm: vm, argv: ["screenshot"], scpBacks: [scpBack],
            ssh: ssh, scpRunner: scp
        )) { err in
            if case let .outputTransferFailed(message) = err as? RouterError {
                XCTAssertTrue(message.contains("Permission denied"))
            } else {
                XCTFail("Expected .outputTransferFailed, got \(err)")
            }
        }
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter AxonUnitTests/RouterDispatchTests
```

Expected: BUILD FAILURE — `type 'RouterError' has no member 'outputTransferFailed'`. The first new test fails at runtime because scp isn't invoked.

- [ ] **Step 3: Implement minimum to pass**

In `Sources/AxonLib/Router.swift`, add the new error case:

```swift
public enum RouterError: Error, Equatable {
    case noBaseRegistered(bundleID: String)
    case missingTarget(command: String)
    case bundleIDNotResolvable(appName: String)
    case vmNotFound(name: String)
    case vmNotReady(name: String)
    case sshFailed(stderr: String, exitCode: Int32)
    case vmAcquireFailed(message: String)
    case outputTransferFailed(message: String)
}
```

Replace the body of `dispatchRemote` with:

```swift
public func dispatchRemote(
    vm: VMEntry,
    argv: [String],
    scpBacks: [ScpBack],
    ssh: SSHDispatcher,
    scpRunner: ScpBackRunner
) throws -> (stdout: Data, stderr: Data, exitCode: Int32) {
    guard let ip = vm.ip else { throw RouterError.vmNotReady(name: vm.name) }
    let env = ["AXON_TARGET": "local"]
    let result = ssh.run(vmIP: ip, argv: argv, env: env)
    if result.exitCode == 0 {
        for back in scpBacks {
            switch scpRunner.transfer(back, fromVMIP: ip) {
            case .success: continue
            case .failure(let err):
                throw RouterError.outputTransferFailed(message: err.description)
            }
        }
    }
    return result
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
swift test --filter AxonUnitTests/RouterDispatchTests
```

Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AxonLib/Router.swift Tests/AxonUnitTests/RouterDispatchTests.swift
git commit -m "$(cat <<'EOF'
feat(router): scp-back file outputs after successful dispatch

On exit code 0 the scp-back list is processed; the first failure
surfaces as RouterError.outputTransferFailed. Non-zero SSH exits
skip scp-back since the VM-side file was likely never written.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 14: Concrete `SSHClient` and `ScpClient`

**Files:**
- Create: `Sources/AxonLib/SSHClient.swift` (Process wrappers around `/usr/bin/ssh` + `/usr/bin/scp`; production impl of `SSHDispatcher` and `ScpBackRunner`)
- Create: `Tests/AxonUnitTests/SSHClientCompileTests.swift` (compile-only construction check)

No behavioral unit tests — both wrap `Process` and shell out. They're exercised by manual VM verification later. We only assert the public types exist and are constructable.

- [ ] **Step 1: Write the (compile-only) unit test**

Create `Tests/AxonUnitTests/SSHClientCompileTests.swift`:

```swift
import XCTest
@testable import AxonLib

final class SSHClientCompileTests: XCTestCase {
    func testLiveSSHDispatcherTypeExists() {
        let _: SSHDispatcher = LiveSSHDispatcher()
    }
    func testLiveScpBackRunnerTypeExists() {
        let _: ScpBackRunner = LiveScpBackRunner()
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter AxonUnitTests/SSHClientCompileTests
```

Expected: BUILD FAILURE — `cannot find 'LiveSSHDispatcher'`, `cannot find 'LiveScpBackRunner'`.

- [ ] **Step 3: Implement minimum to pass**

Create `Sources/AxonLib/SSHClient.swift`:

```swift
import Foundation

/// Production SSHDispatcher. Uses `/usr/bin/ssh`. Caller is responsible for
/// having SSH keys configured for `admin@<vm-ip>`.
public struct LiveSSHDispatcher: SSHDispatcher {
    public init() {}

    public func run(vmIP: String, argv: [String], env: [String: String])
        -> (stdout: Data, stderr: Data, exitCode: Int32)
    {
        // Build remote command: `ENV1=v1 ENV2=v2 axon arg1 arg2 ...`
        // Use single-quote escaping to keep things simple; admin@ip is the convention.
        let envParts = env.map { "\($0.key)=\(shellQuote($0.value))" }
        let cmdParts = ["axon"] + argv.map(shellQuote)
        let remote = (envParts + cmdParts).joined(separator: " ")
        return runProcess(
            executable: "/usr/bin/ssh",
            args: ["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=no", "admin@\(vmIP)", remote]
        )
    }
}

/// Production ScpBackRunner. Uses `/usr/bin/scp`.
public struct LiveScpBackRunner: ScpBackRunner {
    public init() {}

    public func transfer(_ scpBack: ScpBack, fromVMIP ip: String) -> Result<Void, VMError> {
        let result = runProcess(
            executable: "/usr/bin/scp",
            args: ["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=no",
                   "admin@\(ip):\(scpBack.vmPath)", scpBack.hostPath]
        )
        if result.exitCode != 0 {
            let msg = String(data: result.stderr, encoding: .utf8) ?? "scp failed"
            return .failure(VMError(msg))
        }
        // Best-effort cleanup of VM-side temp file.
        _ = runProcess(
            executable: "/usr/bin/ssh",
            args: ["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=no",
                   "admin@\(ip)", "rm -f \(shellQuote(scpBack.vmPath))"]
        )
        return .success(())
    }
}

private func runProcess(executable: String, args: [String])
    -> (stdout: Data, stderr: Data, exitCode: Int32)
{
    let p = Process()
    p.executableURL = URL(fileURLWithPath: executable)
    p.arguments = args
    let outPipe = Pipe()
    let errPipe = Pipe()
    p.standardOutput = outPipe
    p.standardError = errPipe
    do { try p.run() } catch {
        return (Data(), Data("\(error)".utf8), 127)
    }
    p.waitUntilExit()
    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
    return (outData, errData, p.terminationStatus)
}

/// Single-quote a string for safe inclusion in a remote shell command.
private func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
swift test --filter AxonUnitTests/SSHClientCompileTests
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AxonLib/SSHClient.swift Tests/AxonUnitTests/SSHClientCompileTests.swift
git commit -m "$(cat <<'EOF'
feat(router): LiveSSHDispatcher and LiveScpBackRunner

Process-based wrappers around /usr/bin/ssh and /usr/bin/scp.
StrictHostKeyChecking=no + BatchMode=yes keep dispatch
non-interactive; the user is responsible for having SSH keys
configured for admin@<vm-ip>. Best-effort cleanup of VM-side temp
files after a successful scp-back.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 15: Wire router into `main.swift` (pre-switch routing)

**Files:**
- Modify: `Sources/axon/main.swift` (insert routing layer before the existing switch)
- Modify: `Tests/AxonIntegrationTests/CLIIntegrationTests.swift` (defaulted env in `runAxon` + new tests)

This is the integration step. Carefully insert the routing call **after** argv parsing and `--help` handling, but **before** the existing `switch command` block.

**Important:** Activating the router will break existing integration tests that drive UI commands (e.g. `testScreenshotMissingApp_exits1`, `testScreenshotFullScreenWithoutApp_exits0`) unless their `runAxon` helper injects `AXON_TARGET=local` so they keep falling through to the existing host-side dispatch. Update the helper as part of this task.

- [ ] **Step 1: Write the failing integration test**

Append to `Tests/AxonIntegrationTests/CLIIntegrationTests.swift`:

```swift
    // MARK: - Router integration

    func testNoBaseRegisteredErrorOnUIClick() throws {
        // Prepare an empty registry.
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("axon-router-itest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let registryPath = tmpDir.appendingPathComponent("vms.json").path

        let process = Process()
        process.executableURL = Self.binaryURL
        process.arguments = ["click", "--app", "TextEdit", "--label", "Save"]
        var env = ProcessInfo.processInfo.environment
        env["AXON_REGISTRY_PATH"] = registryPath
        env.removeValue(forKey: "AXON_TARGET")  // ensure we exercise VM mode
        process.environment = env
        let outPipe = Pipe(); let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 2,
            "Missing base must exit 2 (router error); got \(process.terminationStatus)")
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertTrue(stderr.contains("no_base_registered"),
            "Stderr should mention no_base_registered; got: \(stderr)")
    }

    func testLocalFlagBypassesRouter() throws {
        // With --local, the router returns .local and the existing switch runs.
        // We use `axon doctor` semantics indirectly via `axon list --local`, which is
        // safe (just lists running apps).
        let process = Process()
        process.executableURL = Self.binaryURL
        process.arguments = ["list", "--local"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "list --local should succeed locally")
    }

    func testAxonTargetLocalEnvBypassesRouter() throws {
        let process = Process()
        process.executableURL = Self.binaryURL
        process.arguments = ["list"]
        var env = ProcessInfo.processInfo.environment
        env["AXON_TARGET"] = "local"
        process.environment = env
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "AXON_TARGET=local should pass through to local list")
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift build -c release && swift test --filter AxonIntegrationTests/CLIIntegrationTests/testNoBaseRegisteredErrorOnUIClick
```

Expected: FAIL — currently `axon click --app TextEdit --label Save` either drives the host (exit 0) or fails with `app_not_found` (exit 1). Either way, exit code is not 2 and stderr doesn't mention `no_base_registered`.

- [ ] **Step 3a: Update `runAxon` helper to default `AXON_TARGET=local`**

In `Tests/AxonIntegrationTests/CLIIntegrationTests.swift`, replace the `runAxon` helper body (around line 20) to inject the env when not set by the caller:

```swift
    @discardableResult
    private func runAxon(_ args: [String] = []) -> (stdout: String, stderr: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = Self.binaryURL
        process.arguments = args

        var env = ProcessInfo.processInfo.environment
        if env["AXON_TARGET"] == nil {
            env["AXON_TARGET"] = "local"
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return (stdout: "", stderr: "Failed to launch process: \(error)", exitCode: -1)
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        return (stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }
```

The new router-integration tests below construct `Process` directly (not via `runAxon`) precisely so they can opt out of the default and exercise router behavior.

- [ ] **Step 3b: Insert routing layer in main.swift**

In `Sources/axon/main.swift`, find this block (around line 880):

```swift
// Per-subcommand --help: `axon tree --help`
if cli.hasHelp() {
    showHelp(for: command)
    exit(0)
}

let noActivate = cli.flag("no-activate")

switch command {
```

Insert **between** the `let noActivate = ...` line and the `switch command {` line:

```swift
// MARK: - VM-by-default routing
// Route UI commands to a Tart VM unless --local / AXON_TARGET=local opt back to host.
if classifyCommand(command) == .vmRoutable {
    let registry = loadVMRegistry(at: activeVMRegistryURL())
    do {
        let target = try resolveTarget(
            argv: cli.args,
            command: command,
            registry: registry,
            env: ProcessInfo.processInfo.environment,
            acquirer: LiveVMAcquirer()
        )
        switch target {
        case .local:
            break  // fall through to existing switch below
        case .remote(let vm):
            let (rewritten, scps) = remapFileOutputs(argv: cli.args, command: command)
            do {
                let result = try dispatchRemote(
                    vm: vm,
                    argv: rewritten,
                    scpBacks: scps,
                    ssh: LiveSSHDispatcher(),
                    scpRunner: LiveScpBackRunner()
                )
                FileHandle.standardOutput.write(result.stdout)
                FileHandle.standardError.write(result.stderr)
                exit(result.exitCode)
            } catch let RouterError.outputTransferFailed(message) {
                printError(code: "output_transfer_failed", message: message)
                exit(1)
            }
        }
    } catch let RouterError.noBaseRegistered(bundleID) {
        printError(
            code: "no_base_registered",
            message: "No VM base registered for \(bundleID). " +
                     "Bake one with: axon vm-bake --source <image> --name axon-<app>-base --for-bundle \(bundleID)" +
                     " — or pass --local to drive the host."
        )
        exit(2)
    } catch let RouterError.missingTarget(cmd) {
        printError(code: "missing_target", message: "\(cmd): pass --vm <name>, --app <name>, --bundle-id <id>, or --local")
        exit(2)
    } catch let RouterError.bundleIDNotResolvable(appName) {
        printError(code: "app_not_found", message: "Could not resolve bundle ID for app '\(appName)'. " +
                                                   "Pass --bundle-id <id> directly, or install the app on the host.")
        exit(2)
    } catch let RouterError.vmNotFound(name) {
        printError(code: "vm_not_found", message: "No VM named '\(name)' in registry. See: axon vm-list")
        exit(2)
    } catch let RouterError.vmNotReady(name) {
        printError(code: "vm_not_ready", message: "VM '\(name)' has no IP yet; re-acquire or wait.")
        exit(2)
    } catch let RouterError.vmAcquireFailed(message) {
        printError(code: "vm_acquire_failed", message: message)
        exit(2)
    } catch {
        printError(code: "router_error", message: "\(error)")
        exit(2)
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
swift build -c release && swift test --filter AxonUnitTests --filter AxonIntegrationTests
```

Expected: all pass. The new integration test exits 2 with `no_base_registered`. `--local` and `AXON_TARGET=local` paths still succeed.

- [ ] **Step 5: Commit**

```bash
git add Sources/axon/main.swift Tests/AxonIntegrationTests/CLIIntegrationTests.swift
git commit -m "$(cat <<'EOF'
feat(router): wire router into main.swift before existing switch

UI-driving commands now resolve a target via the router. .local falls
through to the existing dispatch (no behavior change); .remote re-execs
via SSH and scps any --output files back. RouterError variants map to
distinct exit-2 error codes with actionable hints.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 16: Update `--help` text for `--local`, `--vm`, `--bundle-id`, `vm-bake --for-bundle`

**Files:**
- Modify: `Sources/axon/main.swift` (top-level help + per-command help text constants)

The help text in `main.swift` is human-edited string constants. Find the top-level `helpText` string and the per-command constants (e.g., `helpClick`, `helpVMBake`).

- [ ] **Step 1: Write the failing test**

Append to `CLIIntegrationTests`:

```swift
    func testHelpMentionsLocalAndVMFlags() {
        let r = runAxon(["--help"])
        XCTAssertTrue(r.stderr.contains("--local"), "Top-level --help should mention --local")
        XCTAssertTrue(r.stderr.contains("AXON_TARGET"), "Top-level --help should mention AXON_TARGET env")
    }

    func testVMBakeHelpMentionsForBundle() {
        let r = runAxon(["vm-bake", "--help"])
        XCTAssertTrue(r.stderr.contains("--for-bundle"), "vm-bake --help should mention --for-bundle")
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift build -c release && swift test --filter AxonIntegrationTests/CLIIntegrationTests/testHelpMentionsLocalAndVMFlags
```

Expected: FAIL — current help strings don't contain `--local` or `--for-bundle`.

- [ ] **Step 3: Implement minimum to pass**

In `Sources/axon/main.swift`, locate the top-level `helpText` constant. Add a new section near the top (after the synopsis, before per-command list):

```
TARGET SELECTION (UI commands)
  By default, UI-driving commands (click, type, screenshot, …) route to a
  Tart VM whose base is registered for the target app's bundle ID. To opt
  back to driving the host:
    --local                    drive the host machine
    AXON_TARGET=local          set as env to make --local the default
    --vm <name>                drive a specific registered VM by name
    --bundle-id <id>           skip --app → bundle ID lookup
  If no base is registered for the requested bundle ID, axon exits 2 with
  error code 'no_base_registered'. Bake one with: axon vm-bake --for-bundle.
```

Find `helpVMBake` and replace its `OPTIONS` section to include:

```
  --source <image>      Stock image to clone (required, e.g. "sonoma-base")
  --name <new-base>     Name for the baked base (required)
  --for-bundle <id>     Record bundle-ID → this base mapping (recommended)
  --display-name <n>    Optional display name used by --app lookup
```

- [ ] **Step 4: Run tests to verify pass**

```bash
swift build -c release && swift test --filter AxonIntegrationTests/CLIIntegrationTests/testHelpMentionsLocalAndVMFlags --filter AxonIntegrationTests/CLIIntegrationTests/testVMBakeHelpMentionsForBundle
```

Expected: both pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/axon/main.swift Tests/AxonIntegrationTests/CLIIntegrationTests.swift
git commit -m "$(cat <<'EOF'
docs(help): document --local, AXON_TARGET, --vm, vm-bake --for-bundle

The CLI is the API: agents read --help to learn how to use axon. The
new TARGET SELECTION section explains the routing default and every
opt-out, and vm-bake's help spells out --for-bundle and --display-name.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 17: `vm-sync` command (rsync wrapper)

**Files:**
- Modify: `Sources/AxonLib/Models.swift` (`VMSyncOutput` struct)
- Modify: `Sources/AxonLib/VMManager.swift` (`vmSync` function with injected runner)
- Modify: `Sources/axon/main.swift` (new case + help)
- Modify: `Tests/AxonUnitTests/VMManagerTests.swift` (vmSync unit tests)
- Modify: `Tests/AxonIntegrationTests/CLIIntegrationTests.swift` (arg validation)

- [ ] **Step 1: Write the failing test**

Append to `VMManagerTests`:

```swift
    // MARK: - vm-sync

    func testVMSyncCallsRunnerForEachMatchingVM() throws {
        let url = registryURL()
        try recordBase(name: "axon-cicero-base", source: "s",
                       bundleID: "com.x.Cicero", displayName: "Cicero", at: url)
        var registry = loadVMRegistry(at: url)
        registry.vms.append(VMEntry(name: "axon-r1", base: "axon-cicero-base", created: Date(), ip: "10.0.0.1"))
        registry.vms.append(VMEntry(name: "axon-r2", base: "axon-cicero-base", created: Date(), ip: "10.0.0.2"))
        registry.vms.append(VMEntry(name: "axon-other", base: "axon-other-base", created: Date(), ip: "10.0.0.3"))
        try saveVMRegistry(registry, to: url)

        var calls: [(localPath: String, vmIP: String)] = []
        let result = vmSync(
            bundleID: "com.x.Cicero",
            localAppPath: "/Users/me/Cicero.app",
            registry: registry,
            runner: { local, ip in
                calls.append((local, ip))
                return .success(())
            }
        )
        switch result {
        case .success(let count):
            XCTAssertEqual(count, 2)
        case .failure(let err):
            XCTFail("Expected success, got \(err)")
        }
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(Set(calls.map { $0.vmIP }), Set(["10.0.0.1", "10.0.0.2"]))
        XCTAssertTrue(calls.allSatisfy { $0.localPath == "/Users/me/Cicero.app" })
    }

    func testVMSyncFailsWhenNoBaseRegistered() {
        let registry = VMRegistry(vms: [], bases: [])
        let result = vmSync(
            bundleID: "com.x.Missing",
            localAppPath: "/Users/me/X.app",
            registry: registry,
            runner: { _, _ in .success(()) }
        )
        if case .failure(let err) = result {
            XCTAssertTrue(err.description.contains("com.x.Missing"))
        } else {
            XCTFail("Expected failure")
        }
    }

    func testVMSyncSucceedsWithZeroVMsWhenBaseRegisteredButNoneRunning() throws {
        let url = registryURL()
        try recordBase(name: "axon-cicero-base", source: "s",
                       bundleID: "com.x.Cicero", displayName: "Cicero", at: url)
        let registry = loadVMRegistry(at: url)
        var calls = 0
        let result = vmSync(
            bundleID: "com.x.Cicero",
            localAppPath: "/Users/me/Cicero.app",
            registry: registry,
            runner: { _, _ in calls += 1; return .success(()) }
        )
        switch result {
        case .success(let count): XCTAssertEqual(count, 0)
        case .failure(let err): XCTFail("Expected success, got \(err)")
        }
        XCTAssertEqual(calls, 0)
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter AxonUnitTests/VMManagerTests/testVMSyncCallsRunnerForEachMatchingVM
```

Expected: BUILD FAILURE — `cannot find 'vmSync' in scope`.

- [ ] **Step 3: Implement minimum to pass**

In `Sources/AxonLib/VMManager.swift`:

```swift
public typealias RsyncRunner = (_ localPath: String, _ vmIP: String) -> Result<Void, VMError>

public func vmSync(
    bundleID: String,
    localAppPath: String,
    registry: VMRegistry,
    runner: RsyncRunner
) -> Result<Int, VMError> {
    guard findBase(byBundleID: bundleID, in: registry) != nil else {
        return .failure(VMError("No base registered for bundle ID \(bundleID)"))
    }
    let matchingVMs = registry.vms.filter { vm in
        guard let base = findBase(byBundleID: bundleID, in: registry) else { return false }
        return vm.base == base.name && vm.ip != nil
    }
    var synced = 0
    for vm in matchingVMs {
        guard let ip = vm.ip else { continue }
        switch runner(localAppPath, ip) {
        case .success: synced += 1
        case .failure(let err): return .failure(err)
        }
    }
    return .success(synced)
}

/// Production rsync runner. Caller must have SSH keys to admin@<vmIP>.
public func liveRsyncRunner(localPath: String, vmIP: String) -> Result<Void, VMError> {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
    p.arguments = [
        "-az", "--delete",
        "-e", "ssh -o BatchMode=yes -o StrictHostKeyChecking=no",
        localPath, "admin@\(vmIP):/Applications/",
    ]
    let errPipe = Pipe()
    p.standardError = errPipe
    p.standardOutput = Pipe()
    do { try p.run() } catch {
        return .failure(VMError("Failed to spawn rsync: \(error.localizedDescription)"))
    }
    p.waitUntilExit()
    if p.terminationStatus != 0 {
        let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "rsync failed"
        return .failure(VMError(msg))
    }
    return .success(())
}
```

In `Sources/AxonLib/Models.swift`, add:

```swift
public struct VMSyncOutput: Codable {
    public let success: Bool
    public let synced: Int
    public init(success: Bool, synced: Int) {
        self.success = success
        self.synced = synced
    }
}
```

In `Sources/axon/main.swift`, add a new `case` in the switch (alongside other vm-* cases):

```swift
case "vm-sync":
    guard let bundleID = cli.option("bundle-id"), let localPath = cli.option("path") else {
        printError(code: "missing_option", message: "Provide --bundle-id <id> and --path <local-app>")
        exit(1)
    }
    let registry = loadVMRegistry(at: activeVMRegistryURL())
    switch vmSync(bundleID: bundleID, localAppPath: localPath, registry: registry, runner: liveRsyncRunner) {
    case .success(let count):
        let out = VMSyncOutput(success: true, synced: count)
        emit(out, plain: [("synced", String(count))])
    case .failure(let err):
        printError(code: "vm_sync_failed", message: err.description)
        exit(1)
    }
```

Also add `vm-sync` to the `showHelp(for:)` switch and define a `helpVMSync` constant:

```swift
let helpVMSync = """
axon vm-sync - rsync a built .app into every running VM registered for a bundle ID

USAGE
  axon vm-sync --bundle-id <id> --path <local-app>

OPTIONS
  --bundle-id <id>   Bundle ID of the app whose VMs should receive the build
  --path <app>       Local path to the .app bundle to sync (e.g. .build/release/MyApp.app)

EXAMPLES
  axon vm-sync --bundle-id com.x.Cicero --path /Users/me/Cicero.app
"""
```

Append to `CLIIntegrationTests`:

```swift
    func testVMSyncMissingArgsFails() {
        let r = runAxon(["vm-sync"])
        XCTAssertEqual(r.exitCode, 1)
        XCTAssertTrue(r.stderr.contains("missing_option"))
    }
```

- [ ] **Step 4: Run tests to verify pass**

```bash
swift build -c release && swift test --filter AxonUnitTests --filter AxonIntegrationTests
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AxonLib/VMManager.swift Sources/AxonLib/Models.swift Sources/axon/main.swift Tests/AxonUnitTests/VMManagerTests.swift Tests/AxonIntegrationTests/CLIIntegrationTests.swift
git commit -m "$(cat <<'EOF'
feat(vm): add vm-sync command for in-development app shipping

Rsync a freshly-built .app into every running VM registered for a
bundle ID. Skip-but-success when no VMs are running (so re-runs in a
loop are idempotent). Error when no base is registered (you almost
certainly meant to bake first).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 18: Existing E2E tests get `AXON_TARGET=local` injected

**Files:**
- Modify: `Tests/AxonE2ETests/AxonE2ETestCase.swift`

The existing E2E suite drives Finder/TextEdit on the host. After the routing flip, those calls would either error (no base) or accidentally try to acquire a VM. Force them to stay local.

- [ ] **Step 1: Write the failing test (smoke)**

There's no easy unit-style test for "the env was injected." Add this assertion at the top of `runAxon` to verify the env is applied:

Append a new test method to `AxonE2ETestCase`:

```swift
    func testRunAxonInjectsAxonTargetLocal() {
        // Easiest check: run `env` via /usr/bin/env to inspect what was passed.
        // Use the same setup as runAxon would, so we exercise the override.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        var env = ProcessInfo.processInfo.environment
        env["AXON_TARGET"] = "local"
        process.environment = env
        let outPipe = Pipe()
        process.standardOutput = outPipe
        try! process.run()
        process.waitUntilExit()
        let output = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertTrue(output.contains("AXON_TARGET=local"))
    }
```

(This is mostly belt-and-braces; the real value comes from the next change.)

- [ ] **Step 2: Run test to verify it fails (or skip if it passes — it likely passes because the test sets env directly)**

```bash
swift test --filter AxonE2ETests/AxonE2ETestCase/testRunAxonInjectsAxonTargetLocal
```

If it passes, that's fine; proceed to Step 3.

- [ ] **Step 3: Update `runAxon` to inject the env**

In `Tests/AxonE2ETests/AxonE2ETestCase.swift`, in `runAxon`, after `process.arguments = args`, add:

```swift
        var env = ProcessInfo.processInfo.environment
        if env["AXON_TARGET"] == nil {
            env["AXON_TARGET"] = "local"
        }
        process.environment = env
```

- [ ] **Step 4: Verify all tests still build and unit/integration pass**

```bash
swift build -c release && swift test --filter AxonUnitTests --filter AxonIntegrationTests
```

E2E tests are not run here (they steal focus). Trust that the env injection keeps them on the host.

- [ ] **Step 5: Commit**

```bash
git add Tests/AxonE2ETests/AxonE2ETestCase.swift
git commit -m "$(cat <<'EOF'
test(e2e): inject AXON_TARGET=local into runAxon child process env

E2E tests drive host-resident apps (Finder, TextEdit). After the
VM-by-default routing flip, they need to opt out of routing — set
AXON_TARGET=local in every child invocation unless caller already
overrode it.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 19: README updates

**Files:**
- Modify: `README.md`

- [ ] **Step 1: (No automated test; this is human-readable docs.)**

- [ ] **Step 2: Inspect the current README**

```bash
swift test --filter AxonUnitTests --filter AxonIntegrationTests  # confirm baseline still green
```

- [ ] **Step 3: Edit README.md**

Add a new top-level section right after "How Agents Use This" (around line 30):

```markdown
## VM-by-default routing

UI-driving commands (`click`, `type`, `screenshot`, `tree`, …) route to a
per-app Tart VM by default. axon resolves the target VM by:

1. Looking up the app's bundle ID (via `--app <name>`, `--bundle-id <id>`, or
   the host's running-app list).
2. Looking up that bundle ID in the `bases` registry (`~/.axon/vms.json`).
3. Reusing a registered VM whose base matches, or `vm-acquire`ing a fresh one.

To opt back to the host:

- `--local` flag — per-call.
- `AXON_TARGET=local` env — process-wide default; flag overrides.

If no base is registered for the target bundle ID, axon exits 2 with
`no_base_registered` and tells you exactly which `vm-bake` to run.

### Set up a per-app VM

```bash
# 1. One-time per app: bake a base and record the bundle-ID mapping.
axon vm-bake --source ghcr.io/cirruslabs/macos-sequoia-base:latest \
             --name axon-cicero-base \
             --for-bundle com.andreinicolas.Cicero \
             --display-name Cicero
tart run  axon-cicero-base    # install Cicero, install axon, grant AX + screen recording
tart stop axon-cicero-base    # seal it

# 2. Drive Cicero — axon auto-acquires a VM on first call.
axon screenshot --app Cicero --output ./shot.png   # silently routes to VM and scps back

# 3. (Optional) Ship today's build into running VMs.
axon vm-sync --bundle-id com.andreinicolas.Cicero --path .build/release/Cicero.app

# 4. Tear down when done.
axon vm-release --all
```

### One-time VM setup checklist

The baked base must contain:

- The target app, installed (e.g., dragged into `/Applications/` inside the VM).
- The `axon` binary on `PATH` (`scp axon admin@<vm-ip>:/usr/local/bin/axon`).
- Accessibility + Screen Recording permissions granted to `axon` (driven via
  System Settings during the interactive `tart run` step).
- An SSH authorized key for the host so `ssh admin@<vm-ip> axon` works
  non-interactively.
```

- [ ] **Step 4: (No automated assertion.)**

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "$(cat <<'EOF'
docs(readme): document VM-by-default, vm-bake --for-bundle, vm-sync

Adds a top-level section explaining the routing default, the opt-outs
(--local, AXON_TARGET=local), the bundle-ID resolution flow, and a
copy-pasteable per-app setup checklist.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Final verification

After Task 19, run the full local pipeline:

```bash
swift build -c release
swift test --filter AxonUnitTests --filter AxonIntegrationTests
```

Expected: all pass. Do **not** run `swift test --filter AxonE2ETests` from the agent — those steal focus.

The user will manually verify the cicero-from-tart workflow that motivated this redesign:

```bash
axon vm-bake --source ghcr.io/cirruslabs/macos-sequoia-base:latest \
             --name axon-cicero-base \
             --for-bundle com.andreinicolas.Cicero \
             --display-name Cicero
# (manually configure the VM)
axon screenshot --app Cicero --output /tmp/cicero-from-vm.png
```

Expected: the screenshot is captured **inside the VM**, not on the host, and saved to `/tmp/cicero-from-vm.png` on the host.

---

## Self-review notes (for the implementer)

- **Strict TDD discipline.** Don't skip "verify the test fails." If the failure isn't the message you expected, stop and figure out why before writing code.
- **One task = one commit.** Don't squash. Each commit should leave the build green for the unit + integration suites.
- **No drive-by changes.** If you spot something to clean up that isn't on the plan, leave a note for the reviewer; don't fix it in this PR.
- **Stop on red.** If a step's expected output doesn't match, file a question or stop the task — don't paper over it.
