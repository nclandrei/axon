# M2 — Sample App + Canonical E2E Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `AxonSample.app` (a standalone SwiftUI notes app bundled in-repo) and the canonical end-to-end test suite that drives it — plus TextEdit sheet/menu scenarios in the existing E2E tests and a `make verify` local test runner.

**Architecture:** Samples live in `Samples/AxonSample/`, an isolated Swift package with its own `Package.swift`. A Makefile in that directory builds a signed-ready `AxonSample.app` bundle under `Samples/AxonSample/.build/AxonSample.app`. The main `axon` package is untouched. E2E tests extend a new `AxonSampleE2ETestCase` helper that launches the sample app at a known path, waits for readiness, and tears down cleanly.

**Tech Stack:** Swift 5.9, SwiftUI, SPM, XCTest, the M1-era `axon` CLI. No new external dependencies.

**Spec:** `docs/superpowers/specs/2026-04-19-axon-public-ready-design.md` (M2 section).

**TDD discipline:** Each sample-app feature is introduced by a failing E2E test. Because background agents must not run E2E tests (they steal focus and open system dialogs), subagents verify only that:

1. The new E2E test compiles.
2. `swift build -c release` succeeds in both `axon` and `Samples/AxonSample/` packages.
3. Unit + integration tests on the `axon` package stay green (`swift test --filter AxonUnitTests --filter AxonIntegrationTests`).

The E2E tests themselves are validated by a human (or privileged session) running `make verify` after M2 lands. Each task must leave the repo in a state where a local `make verify` would pass. The controller orchestrating this plan SHOULD run `make verify` at least once during M2 (ideally after Tasks 3, 8, and 12) to catch drift early.

---

## File Structure

**New files created in this plan:**

- `Samples/AxonSample/Package.swift` — standalone SPM manifest, macOS 14, produces an executable target named `AxonSample`.
- `Samples/AxonSample/Sources/AxonSample/AxonSampleApp.swift` — SwiftUI `@main` entry point, window + commands + app-level state wiring.
- `Samples/AxonSample/Sources/AxonSample/NotesStore.swift` — in-memory `ObservableObject` holding the list of notes and the selected-note state, plus dirty-tracking.
- `Samples/AxonSample/Sources/AxonSample/ContentView.swift` — sidebar + editor layout.
- `Samples/AxonSample/Sources/AxonSample/NoteRow.swift` — per-row view for the sidebar list.
- `Samples/AxonSample/Sources/AxonSample/Editor.swift` — title + body editor pane.
- `Samples/AxonSample/Sources/AxonSample/UnsavedSheet.swift` — the Save / Don't Save / Cancel sheet view.
- `Samples/AxonSample/Makefile` — `build` and `clean` targets, producing `AxonSample.app` under `Samples/AxonSample/.build/`.
- `Samples/AxonSample/Info.plist.template` — plist template copied into the bundle.
- `Tests/AxonE2ETests/AxonSampleE2ETestCase.swift` — shared helpers for launching and closing AxonSample.
- `Tests/AxonE2ETests/AxonSampleE2ETests.swift` — per-feature E2E tests and the canonical end-to-end flow.

**Modified files:**

- `Tests/AxonE2ETests/E2ETests.swift` — appended TextEdit sheet + menu scenarios.
- `Makefile` (repo root) — add a `verify` target that builds release, builds the sample, runs all three test tiers.
- `CLAUDE.md` — one-line update noting `make verify` is the full local check.

**Note on TDD rhythm for M2:** Each feature task writes the E2E test first (that serves as the RED), then builds the sample-app feature so the test would pass when run (the GREEN). The subagent can verify the test compiles via `swift build --target AxonE2ETests --package-path /Users/anicolae/code/axon/.worktrees/m2-sample-app` (or equivalent), but NOT run the test.

---

## Task 1: Set up the `Samples/AxonSample/` skeleton

**Files:**
- Create: `Samples/AxonSample/Package.swift`
- Create: `Samples/AxonSample/Sources/AxonSample/AxonSampleApp.swift`
- Create: `Samples/AxonSample/Makefile`
- Create: `Samples/AxonSample/Info.plist.template`

- [ ] **Step 1: Create `Samples/AxonSample/Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AxonSample",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AxonSample", targets: ["AxonSample"])
    ],
    targets: [
        .executableTarget(
            name: "AxonSample",
            path: "Sources/AxonSample"
        )
    ]
)
```

- [ ] **Step 2: Create `Samples/AxonSample/Sources/AxonSample/AxonSampleApp.swift`** (minimal skeleton — just a window with a placeholder)

```swift
import SwiftUI

@main
struct AxonSampleApp: App {
    var body: some Scene {
        WindowGroup("AxonSample") {
            Text("AxonSample")
                .frame(minWidth: 640, minHeight: 400)
                .accessibilityIdentifier("mainPlaceholder")
        }
    }
}
```

- [ ] **Step 3: Create `Samples/AxonSample/Info.plist.template`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>AxonSample</string>
  <key>CFBundleDisplayName</key>
  <string>AxonSample</string>
  <key>CFBundleIdentifier</key>
  <string>com.nclandrei.axon.sample</string>
  <key>CFBundleExecutable</key>
  <string>AxonSample</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
```

- [ ] **Step 4: Create `Samples/AxonSample/Makefile`**

```makefile
.PHONY: build clean

APP_NAME = AxonSample
APP_BUNDLE = .build/$(APP_NAME).app
BIN = .build/release/$(APP_NAME)

build:
	swift build -c release
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	cp $(BIN) $(APP_BUNDLE)/Contents/MacOS/
	cp Info.plist.template $(APP_BUNDLE)/Contents/Info.plist
	@echo "Built $(APP_BUNDLE)"

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
```

- [ ] **Step 5: Build it**

From the worktree root:

```bash
cd Samples/AxonSample
make build
ls -la .build/AxonSample.app/Contents/MacOS/AxonSample
```

Expected: the binary exists, the Info.plist is in place, no build errors.

- [ ] **Step 6: Verify the main axon package is unaffected**

From the worktree root:

```bash
swift build -c release
swift test --filter AxonUnitTests --filter AxonIntegrationTests
```

Expected: clean build and all tests pass (no regressions).

- [ ] **Step 7: Commit**

```bash
git add Samples/AxonSample/
git commit -m "Add Samples/AxonSample/ skeleton (SwiftUI + Makefile + Info.plist)"
```

---

## Task 2: E2E test case helpers + first smoke test

**Files:**
- Create: `Tests/AxonE2ETests/AxonSampleE2ETestCase.swift`
- Create: `Tests/AxonE2ETests/AxonSampleE2ETests.swift`

- [ ] **Step 1: Create `Tests/AxonE2ETests/AxonSampleE2ETestCase.swift`**

```swift
import Foundation
import XCTest

/// Shared setup/teardown for E2E tests that drive AxonSample.app.
class AxonSampleE2ETestCase: AxonE2ETestCase {
    /// Absolute path to the built sample app bundle.
    static var samplePath: String {
        Self.projectRoot
            .appendingPathComponent("Samples/AxonSample/.build/AxonSample.app")
            .path
    }

    /// Skip the current test if the sample hasn't been built.
    func skipIfSampleNotBuilt() throws {
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: Self.samplePath),
            "AxonSample.app not built — run `make -C Samples/AxonSample build`"
        )
    }

    /// Launch the sample app and wait for its UI to be ready.
    @discardableResult
    func launchSample() throws -> (stdout: String, stderr: String, exitCode: Int32) {
        let launch = runAxon(["launch", "--path", Self.samplePath])
        try skipIfNoAccessibility(launch)
        XCTAssertEqual(launch.exitCode, 0, "launch failed: \(launch.stderr)")

        let ready = runAxon(["wait-ready", "--app", "AxonSample", "--timeout", "5"])
        XCTAssertEqual(ready.exitCode, 0, "wait-ready failed: \(ready.stderr)")

        return launch
    }

    /// Quit the sample app unconditionally. Safe to call in teardown even if never launched.
    func quitSample() {
        _ = runAxon(["close", "--app", "AxonSample", "--quit"])
    }
}
```

- [ ] **Step 2: Create `Tests/AxonE2ETests/AxonSampleE2ETests.swift`** with a single smoke test

```swift
import Foundation
import XCTest

final class AxonSampleE2ETests: AxonSampleE2ETestCase {

    override func tearDown() {
        quitSample()
        super.tearDown()
    }

    // MARK: - 1. Launch smoke test

    func testSampleAppLaunchesAndIsReady() throws {
        try skipIfSampleNotBuilt()
        try launchSample()

        let tree = runAxon(["tree", "--app", "AxonSample", "--depth", "2", "--compact"])
        XCTAssertEqual(tree.exitCode, 0, "tree should succeed on a ready AxonSample")
        let json = parseJSON(tree.stdout)
        XCTAssertNotNil(json, "tree should produce valid JSON")
        XCTAssertNotNil(json?["tree"], "tree JSON should have a 'tree' key")
    }
}
```

- [ ] **Step 3: Compile the E2E tests**

```bash
swift build --target AxonE2ETests
```

Expected: clean build. Do NOT `swift test` — E2E must be run only via `make verify` locally.

- [ ] **Step 4: Confirm unit + integration still green**

```bash
swift test --filter AxonUnitTests --filter AxonIntegrationTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Tests/AxonE2ETests/AxonSampleE2ETestCase.swift Tests/AxonE2ETests/AxonSampleE2ETests.swift
git commit -m "Add AxonSampleE2ETestCase + launch smoke test"
```

---

## Task 3: Notes store + sidebar list + New button

**Files:**
- Create: `Samples/AxonSample/Sources/AxonSample/NotesStore.swift`
- Create: `Samples/AxonSample/Sources/AxonSample/ContentView.swift`
- Create: `Samples/AxonSample/Sources/AxonSample/NoteRow.swift`
- Modify: `Samples/AxonSample/Sources/AxonSample/AxonSampleApp.swift`
- Modify: `Tests/AxonE2ETests/AxonSampleE2ETests.swift` (append new tests)

- [ ] **Step 1: Write the failing E2E test** — append inside `AxonSampleE2ETests`

```swift
// MARK: - 2. New Note creates a sidebar row

func testNewNoteButtonAddsSidebarRow() throws {
    try skipIfSampleNotBuilt()
    try launchSample()

    // Sanity: the New Note button exists.
    let exists = runAxon(["exists", "--app", "AxonSample", "--identifier", "newNoteButton"])
    XCTAssertEqual(exists.exitCode, 0)
    XCTAssertEqual(parseJSON(exists.stdout)?["exists"] as? Bool, true)

    // Click it.
    let click = runAxon(["click", "--app", "AxonSample", "--identifier", "newNoteButton"])
    XCTAssertEqual(click.exitCode, 0, "click failed: \(click.stderr)")

    // Assert: a row labeled "Untitled" shows up in the sidebar.
    let row = runAxon(["exists", "--app", "AxonSample", "--label", "Untitled"])
    XCTAssertEqual(row.exitCode, 0)
    XCTAssertEqual(parseJSON(row.stdout)?["exists"] as? Bool, true)
}
```

- [ ] **Step 2: Create `Samples/AxonSample/Sources/AxonSample/NotesStore.swift`**

```swift
import SwiftUI
import Combine

final class Note: Identifiable, ObservableObject {
    let id = UUID()
    @Published var title: String
    @Published var body: String
    @Published var isDirty: Bool

    init(title: String = "Untitled", body: String = "") {
        self.title = title
        self.body = body
        self.isDirty = false
    }
}

final class NotesStore: ObservableObject {
    @Published var notes: [Note] = []
    @Published var selectedID: UUID? = nil

    func createNote() {
        let note = Note()
        notes.append(note)
        selectedID = note.id
    }

    var selectedNote: Note? {
        guard let id = selectedID else { return nil }
        return notes.first(where: { $0.id == id })
    }
}
```

- [ ] **Step 3: Create `Samples/AxonSample/Sources/AxonSample/NoteRow.swift`**

```swift
import SwiftUI

struct NoteRow: View {
    @ObservedObject var note: Note

    var body: some View {
        Text(note.title)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("noteRow-\(note.id.uuidString)")
            .accessibilityLabel(note.title)
    }
}
```

- [ ] **Step 4: Create `Samples/AxonSample/Sources/AxonSample/ContentView.swift`**

```swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: NotesStore

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    Button(action: { store.createNote() }) {
                        Label("New Note", systemImage: "plus")
                    }
                    .accessibilityIdentifier("newNoteButton")
                    .accessibilityLabel("New Note")
                    Spacer()
                }
                .padding(8)

                List(selection: $store.selectedID) {
                    ForEach(store.notes) { note in
                        NoteRow(note: note).tag(note.id as UUID?)
                    }
                }
                .accessibilityIdentifier("notesList")
            }
        } detail: {
            if let note = store.selectedNote {
                Text("Editor for \(note.title)") // replaced in Task 4
            } else {
                Text("No note selected")
                    .accessibilityIdentifier("noSelectionPlaceholder")
            }
        }
        .frame(minWidth: 640, minHeight: 400)
    }
}
```

- [ ] **Step 5: Update `AxonSampleApp.swift`** to wire the store and use the new `ContentView`

```swift
import SwiftUI

@main
struct AxonSampleApp: App {
    @StateObject private var store = NotesStore()

    var body: some Scene {
        WindowGroup("AxonSample") {
            ContentView()
                .environmentObject(store)
        }
    }
}
```

- [ ] **Step 6: Build the sample**

```bash
cd Samples/AxonSample
make build
```

Expected: clean build.

- [ ] **Step 7: Compile the E2E tests**

```bash
cd ../..
swift build --target AxonE2ETests
```

Expected: clean build.

- [ ] **Step 8: Confirm unit + integration still green**

```bash
swift test --filter AxonUnitTests --filter AxonIntegrationTests
```

- [ ] **Step 9: Commit**

```bash
git add Samples/AxonSample/ Tests/AxonE2ETests/AxonSampleE2ETests.swift
git commit -m "AxonSample: add NotesStore + sidebar + New Note button"
```

---

## Task 4: Editor pane with title + body fields

**Files:**
- Create: `Samples/AxonSample/Sources/AxonSample/Editor.swift`
- Modify: `Samples/AxonSample/Sources/AxonSample/ContentView.swift` (detail pane)
- Modify: `Tests/AxonE2ETests/AxonSampleE2ETests.swift` (append test)

- [ ] **Step 1: Write the failing E2E test** — append inside the class

```swift
// MARK: - 3. Editor reflects typed content

func testTypingUpdatesNoteTitleAndBody() throws {
    try skipIfSampleNotBuilt()
    try launchSample()

    // Create a note
    _ = runAxon(["click", "--app", "AxonSample", "--identifier", "newNoteButton"])

    // Type into the title
    let titleType = runAxon([
        "type", "--app", "AxonSample",
        "--identifier", "noteTitleField",
        "--text", "Groceries",
        "--clear"
    ])
    XCTAssertEqual(titleType.exitCode, 0, titleType.stderr)

    // Type into the body
    let bodyType = runAxon([
        "type", "--app", "AxonSample",
        "--identifier", "noteBodyField",
        "--text", "Milk, eggs, bread",
        "--clear"
    ])
    XCTAssertEqual(bodyType.exitCode, 0, bodyType.stderr)

    // Assert title value using axon assert --value
    let titleAssert = runAxon([
        "assert", "--app", "AxonSample",
        "--identifier", "noteTitleField",
        "--value", "Groceries"
    ])
    XCTAssertEqual(titleAssert.exitCode, 0, "title assert failed: \(titleAssert.stderr)")

    // Assert body via --value-matches
    let bodyAssert = runAxon([
        "assert", "--app", "AxonSample",
        "--identifier", "noteBodyField",
        "--value-matches", "^Milk.*bread$"
    ])
    XCTAssertEqual(bodyAssert.exitCode, 0, "body assert failed: \(bodyAssert.stderr)")
}
```

- [ ] **Step 2: Create `Samples/AxonSample/Sources/AxonSample/Editor.swift`**

```swift
import SwiftUI

struct Editor: View {
    @ObservedObject var note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: Binding(
                get: { note.title },
                set: { new in note.title = new; note.isDirty = true }
            ))
            .font(.title2)
            .textFieldStyle(.plain)
            .accessibilityIdentifier("noteTitleField")

            Divider()

            TextEditor(text: Binding(
                get: { note.body },
                set: { new in note.body = new; note.isDirty = true }
            ))
            .font(.body)
            .accessibilityIdentifier("noteBodyField")
        }
        .padding(16)
    }
}
```

- [ ] **Step 3: Update `ContentView.swift`** detail branch to use the Editor

Replace the placeholder `Text("Editor for \(note.title)")` with `Editor(note: note)`.

- [ ] **Step 4: Build**

```bash
cd Samples/AxonSample && make build && cd ../..
```

- [ ] **Step 5: Compile E2E + run unit/integration**

```bash
swift build --target AxonE2ETests
swift test --filter AxonUnitTests --filter AxonIntegrationTests
```

Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add Samples/AxonSample/Sources/AxonSample/Editor.swift Samples/AxonSample/Sources/AxonSample/ContentView.swift Tests/AxonE2ETests/AxonSampleE2ETests.swift
git commit -m "AxonSample: add Editor with title/body fields"
```

---

## Task 5: File menu with New (⌘N)

**Files:**
- Modify: `Samples/AxonSample/Sources/AxonSample/AxonSampleApp.swift` (add Commands)
- Modify: `Tests/AxonE2ETests/AxonSampleE2ETests.swift` (append test)

- [ ] **Step 1: Write the failing E2E test**

```swift
// MARK: - 4. File > New menu

func testFileNewMenuAddsNote() throws {
    try skipIfSampleNotBuilt()
    try launchSample()

    let before = runAxon(["exists", "--app", "AxonSample", "--label", "Untitled"])
    XCTAssertEqual(parseJSON(before.stdout)?["exists"] as? Bool, false)

    let menu = runAxon(["menu", "--app", "AxonSample", "--path", "File > New"])
    XCTAssertEqual(menu.exitCode, 0, "menu nav failed: \(menu.stderr)")

    let after = runAxon(["exists", "--app", "AxonSample", "--label", "Untitled"])
    XCTAssertEqual(parseJSON(after.stdout)?["exists"] as? Bool, true)
}

func testCommandNAddsNote() throws {
    try skipIfSampleNotBuilt()
    try launchSample()

    let key = runAxon(["key", "--app", "AxonSample", "--key", "n", "--modifiers", "command"])
    XCTAssertEqual(key.exitCode, 0, "⌘N failed: \(key.stderr)")

    let row = runAxon(["exists", "--app", "AxonSample", "--label", "Untitled"])
    XCTAssertEqual(parseJSON(row.stdout)?["exists"] as? Bool, true)
}
```

- [ ] **Step 2: Add Commands to `AxonSampleApp.swift`**

```swift
import SwiftUI

@main
struct AxonSampleApp: App {
    @StateObject private var store = NotesStore()

    var body: some Scene {
        WindowGroup("AxonSample") {
            ContentView()
                .environmentObject(store)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") { store.createNote() }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
```

- [ ] **Step 3: Build + compile E2E + unit/integration**

```bash
cd Samples/AxonSample && make build && cd ../..
swift build --target AxonE2ETests
swift test --filter AxonUnitTests --filter AxonIntegrationTests
```

- [ ] **Step 4: Commit**

```bash
git add Samples/AxonSample/Sources/AxonSample/AxonSampleApp.swift Tests/AxonE2ETests/AxonSampleE2ETests.swift
git commit -m "AxonSample: File > New menu and ⌘N shortcut"
```

---

## Task 6: File > Save (⌘S) + dirty status indicator

**Files:**
- Modify: `Samples/AxonSample/Sources/AxonSample/NotesStore.swift` (add `save()`)
- Modify: `Samples/AxonSample/Sources/AxonSample/AxonSampleApp.swift` (add Save menu)
- Modify: `Samples/AxonSample/Sources/AxonSample/ContentView.swift` (add dirty status label)
- Modify: `Tests/AxonE2ETests/AxonSampleE2ETests.swift` (append test)

- [ ] **Step 1: Write the failing E2E test**

```swift
// MARK: - 5. Save clears the dirty indicator

func testSaveClearsDirty() throws {
    try skipIfSampleNotBuilt()
    try launchSample()

    // Create + edit → dirty
    _ = runAxon(["click", "--app", "AxonSample", "--identifier", "newNoteButton"])
    _ = runAxon([
        "type", "--app", "AxonSample",
        "--identifier", "noteTitleField",
        "--text", "X",
        "--clear"
    ])

    let dirty = runAxon([
        "assert", "--app", "AxonSample",
        "--identifier", "dirtyStatus",
        "--value", "modified"
    ])
    XCTAssertEqual(dirty.exitCode, 0, "dirty assert failed: \(dirty.stderr)")

    // Save via menu
    let save = runAxon(["menu", "--app", "AxonSample", "--path", "File > Save"])
    XCTAssertEqual(save.exitCode, 0, "save failed: \(save.stderr)")

    let clean = runAxon([
        "assert", "--app", "AxonSample",
        "--identifier", "dirtyStatus",
        "--value", "clean"
    ])
    XCTAssertEqual(clean.exitCode, 0, "clean assert failed: \(clean.stderr)")
}
```

- [ ] **Step 2: Extend `NotesStore.swift`**

Append a `save()` method to the class:

```swift
    func save() {
        selectedNote?.isDirty = false
    }
```

- [ ] **Step 3: Update `AxonSampleApp.swift`** commands to include Save

Inside the `.commands { … }` modifier, replace the existing `.newItem` replacement with:

```swift
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") { store.createNote() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { store.save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(store.selectedNote == nil)
            }
        }
```

- [ ] **Step 4: Add dirty status to `ContentView.swift`**

In the detail branch, wrap the `Editor` in a `VStack` with a status label below:

```swift
        } detail: {
            VStack(spacing: 0) {
                if let note = store.selectedNote {
                    Editor(note: note)
                    HStack {
                        Text(note.isDirty ? "modified" : "clean")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .accessibilityIdentifier("dirtyStatus")
                            .accessibilityLabel(note.isDirty ? "modified" : "clean")
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                } else {
                    Text("No note selected")
                        .accessibilityIdentifier("noSelectionPlaceholder")
                }
            }
        }
```

- [ ] **Step 5: Build + compile E2E + unit/integration**

```bash
cd Samples/AxonSample && make build && cd ../..
swift build --target AxonE2ETests
swift test --filter AxonUnitTests --filter AxonIntegrationTests
```

- [ ] **Step 6: Commit**

```bash
git add Samples/AxonSample/ Tests/AxonE2ETests/AxonSampleE2ETests.swift
git commit -m "AxonSample: File > Save + dirty status indicator"
```

---

## Task 7: File > Delete (⌘⌫)

**Files:**
- Modify: `Samples/AxonSample/Sources/AxonSample/NotesStore.swift`
- Modify: `Samples/AxonSample/Sources/AxonSample/AxonSampleApp.swift`
- Modify: `Tests/AxonE2ETests/AxonSampleE2ETests.swift`

- [ ] **Step 1: Write the failing E2E test**

```swift
// MARK: - 6. Delete removes the selected note

func testDeleteRemovesSelectedNote() throws {
    try skipIfSampleNotBuilt()
    try launchSample()

    _ = runAxon(["menu", "--app", "AxonSample", "--path", "File > New"])
    _ = runAxon([
        "type", "--app", "AxonSample",
        "--identifier", "noteTitleField",
        "--text", "Ephemeral",
        "--clear"
    ])

    let existsBefore = runAxon(["exists", "--app", "AxonSample", "--label", "Ephemeral"])
    XCTAssertEqual(parseJSON(existsBefore.stdout)?["exists"] as? Bool, true)

    let delete = runAxon(["menu", "--app", "AxonSample", "--path", "File > Delete"])
    XCTAssertEqual(delete.exitCode, 0, "delete failed: \(delete.stderr)")

    let existsAfter = runAxon(["exists", "--app", "AxonSample", "--label", "Ephemeral"])
    XCTAssertEqual(parseJSON(existsAfter.stdout)?["exists"] as? Bool, false)
}
```

- [ ] **Step 2: Extend `NotesStore.swift`** with a `deleteSelected()` method

Append:

```swift
    func deleteSelected() {
        guard let id = selectedID, let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes.remove(at: idx)
        selectedID = notes.first?.id
    }
```

- [ ] **Step 3: Update `AxonSampleApp.swift`** commands to include Delete

Inside `.commands { … }`, add a third `CommandGroup`:

```swift
            CommandGroup(after: .saveItem) {
                Button("Delete") { store.deleteSelected() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(store.selectedNote == nil)
            }
```

- [ ] **Step 4: Build + verify**

```bash
cd Samples/AxonSample && make build && cd ../..
swift build --target AxonE2ETests
swift test --filter AxonUnitTests --filter AxonIntegrationTests
```

- [ ] **Step 5: Commit**

```bash
git add Samples/AxonSample/ Tests/AxonE2ETests/AxonSampleE2ETests.swift
git commit -m "AxonSample: File > Delete menu and ⌘⌫ shortcut"
```

---

## Task 8: Unsaved-changes sheet on close

**Files:**
- Create: `Samples/AxonSample/Sources/AxonSample/UnsavedSheet.swift`
- Modify: `Samples/AxonSample/Sources/AxonSample/NotesStore.swift` (add flag controlling sheet presentation)
- Modify: `Samples/AxonSample/Sources/AxonSample/ContentView.swift` (present sheet)
- Modify: `Samples/AxonSample/Sources/AxonSample/AxonSampleApp.swift` (intercept ⌘W)
- Modify: `Tests/AxonE2ETests/AxonSampleE2ETests.swift`

- [ ] **Step 1: Write the failing E2E test**

```swift
// MARK: - 7. Unsaved sheet appears on close attempt and responds to --sheet targeting

func testUnsavedSheetOnCloseAttemptDontSave() throws {
    try skipIfSampleNotBuilt()
    try launchSample()

    _ = runAxon(["click", "--app", "AxonSample", "--identifier", "newNoteButton"])
    _ = runAxon([
        "type", "--app", "AxonSample",
        "--identifier", "noteTitleField",
        "--text", "Unsaved",
        "--clear"
    ])

    // Attempt to close the window — triggers the sheet because the note is dirty
    let close = runAxon(["key", "--app", "AxonSample", "--key", "w", "--modifiers", "command"])
    XCTAssertEqual(close.exitCode, 0, close.stderr)

    // Sheet should exist — probe via --sheet
    let sheetExists = runAxon(["exists", "--app", "AxonSample", "--sheet"])
    XCTAssertEqual(parseJSON(sheetExists.stdout)?["exists"] as? Bool, true)

    // Click "Don't Save"
    let dontSave = runAxon([
        "click", "--app", "AxonSample",
        "--sheet", "--label", "Don't Save"
    ])
    XCTAssertEqual(dontSave.exitCode, 0, "don't save click failed: \(dontSave.stderr)")

    // Note should be gone (discarded)
    let stillThere = runAxon(["exists", "--app", "AxonSample", "--label", "Unsaved"])
    XCTAssertEqual(parseJSON(stillThere.stdout)?["exists"] as? Bool, false)
}
```

- [ ] **Step 2: Create `UnsavedSheet.swift`**

```swift
import SwiftUI

struct UnsavedSheet: View {
    let onSave: () -> Void
    let onDontSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("You have unsaved changes.")
                .font(.headline)
            Text("Do you want to save before closing?")

            HStack {
                Button("Cancel") { onCancel() }
                    .accessibilityIdentifier("sheetCancel")
                Spacer()
                Button("Don't Save") { onDontSave() }
                    .accessibilityIdentifier("sheetDontSave")
                Button("Save") { onSave() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("sheetSave")
            }
        }
        .padding(24)
        .frame(minWidth: 340)
    }
}
```

- [ ] **Step 3: Extend `NotesStore.swift`** with a sheet-presentation flag and a handler

Append:

```swift
    @Published var showUnsavedSheet: Bool = false

    /// Called when the user attempts to close a dirty note. Returns true if the
    /// action should proceed immediately; false if the sheet will intercept.
    func attemptClose() -> Bool {
        if let note = selectedNote, note.isDirty {
            showUnsavedSheet = true
            return false
        }
        return true
    }

    func dismissSheetSave() {
        save()
        showUnsavedSheet = false
        deleteSelected()
    }

    func dismissSheetDontSave() {
        showUnsavedSheet = false
        deleteSelected()
    }

    func dismissSheetCancel() {
        showUnsavedSheet = false
    }
```

- [ ] **Step 4: Present the sheet from `ContentView.swift`**

Add `.sheet` modifier on the outermost `NavigationSplitView`:

```swift
        .frame(minWidth: 640, minHeight: 400)
        .sheet(isPresented: $store.showUnsavedSheet) {
            UnsavedSheet(
                onSave: store.dismissSheetSave,
                onDontSave: store.dismissSheetDontSave,
                onCancel: store.dismissSheetCancel
            )
        }
```

- [ ] **Step 5: Intercept ⌘W in `AxonSampleApp.swift`** commands

Replace the whole `.commands { … }` block with the full set (New, Save, Delete, plus a Close override):

```swift
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") { store.createNote() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { store.save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(store.selectedNote == nil)
            }
            CommandGroup(after: .saveItem) {
                Button("Delete") { store.deleteSelected() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(store.selectedNote == nil)
            }
            CommandGroup(replacing: .windowArrangement) {
                Button("Close") {
                    _ = store.attemptClose()
                }
                .keyboardShortcut("w", modifiers: .command)
            }
        }
```

- [ ] **Step 6: Build + verify**

```bash
cd Samples/AxonSample && make build && cd ../..
swift build --target AxonE2ETests
swift test --filter AxonUnitTests --filter AxonIntegrationTests
```

- [ ] **Step 7: Commit**

```bash
git add Samples/AxonSample/ Tests/AxonE2ETests/AxonSampleE2ETests.swift
git commit -m "AxonSample: unsaved-changes sheet on ⌘W for dirty notes"
```

---

## Task 9: Root Makefile `verify` target

**Files:**
- Modify: `Makefile` (repo root)

- [ ] **Step 1: Update the root `Makefile`**

Replace the current Makefile (`build`, `install`, `clean`) with:

```makefile
.PHONY: build install clean verify

build:
	swift build -c release

install: build
	cp .build/release/axon /usr/local/bin/axon

clean:
	swift package clean
	$(MAKE) -C Samples/AxonSample clean

# Full local check: builds axon + sample, runs all three test tiers.
# E2E steals focus — only run locally, never in CI or background agents.
verify: build
	$(MAKE) -C Samples/AxonSample build
	swift test --filter AxonUnitTests
	swift test --filter AxonIntegrationTests
	swift test --filter AxonE2ETests
```

- [ ] **Step 2: Dry-run smoke check**

```bash
make -n verify
```

Expected: prints the command sequence without errors.

- [ ] **Step 3: Commit**

```bash
git add Makefile
git commit -m "Add 'make verify' target running all three test tiers"
```

---

## Task 10: TextEdit sheet scenario (existing E2ETests.swift)

**Files:**
- Modify: `Tests/AxonE2ETests/E2ETests.swift` (append)

- [ ] **Step 1: Append the new test**

Append at the end of the `final class E2ETests` body, before the closing brace:

```swift
    // MARK: - TextEdit sheet scenario

    func testTextEditUnsavedSheetTargetable() throws {
        // Launch TextEdit fresh
        let launch = runAxon(["launch", "--name", "TextEdit"])
        try skipIfNoAccessibility(launch)
        XCTAssertEqual(launch.exitCode, 0)
        defer { _ = runAxon(["close", "--app", "TextEdit", "--quit"]) }

        _ = runAxon(["wait-ready", "--app", "TextEdit", "--timeout", "5"])

        // Find the frontmost text area and type into it to make it dirty.
        let treeResult = runAxon(["tree", "--app", "TextEdit", "--compact"])
        try XCTSkipUnless(treeResult.exitCode == 0, "TextEdit tree failed: \(treeResult.stderr)")

        // Type via the known TextEdit text-area tree path.
        let typeResult = runAxon([
            "type", "--app", "TextEdit",
            "--path", "AXWindow[0]/AXScrollArea[0]/AXTextArea[0]",
            "--text", "Unsaved content"
        ])
        try XCTSkipUnless(typeResult.exitCode == 0, "type failed: \(typeResult.stderr)")

        // Close the window — TextEdit will ask whether to save.
        let close = runAxon(["key", "--app", "TextEdit", "--key", "w", "--modifiers", "command"])
        XCTAssertEqual(close.exitCode, 0, close.stderr)

        // The sheet should exist. Target via --sheet.
        let sheet = runAxon(["exists", "--app", "TextEdit", "--sheet"])
        XCTAssertEqual(sheet.exitCode, 0)
        XCTAssertEqual(parseJSON(sheet.stdout)?["exists"] as? Bool, true, "TextEdit sheet should be findable via --sheet")

        // Dismiss by clicking Don't Save (exact button label varies by macOS version but
        // "Don't Save" is stable across Sonoma/Sequoia).
        let dismiss = runAxon([
            "click", "--app", "TextEdit",
            "--sheet", "--label", "Don't Save"
        ])
        // If the label differs, this click will fail — treat as a skip, not a hard failure.
        if dismiss.exitCode != 0 {
            _ = runAxon(["key", "--app", "TextEdit", "--key", "escape"])
            throw XCTSkip("TextEdit sheet button label may differ on this OS: \(dismiss.stderr)")
        }
        XCTAssertEqual(dismiss.exitCode, 0)
    }
```

- [ ] **Step 2: Compile E2E + run unit/integration**

```bash
swift build --target AxonE2ETests
swift test --filter AxonUnitTests --filter AxonIntegrationTests
```

- [ ] **Step 3: Commit**

```bash
git add Tests/AxonE2ETests/E2ETests.swift
git commit -m "E2E: TextEdit unsaved-changes sheet targetable via --sheet"
```

---

## Task 11: TextEdit menu navigation scenario

**Files:**
- Modify: `Tests/AxonE2ETests/E2ETests.swift` (append)

- [ ] **Step 1: Append the new test**

Append at the end of the `final class E2ETests` body:

```swift
    // MARK: - TextEdit menu navigation

    func testTextEditShowFontsMenu() throws {
        let launch = runAxon(["launch", "--name", "TextEdit"])
        try skipIfNoAccessibility(launch)
        XCTAssertEqual(launch.exitCode, 0)
        defer { _ = runAxon(["close", "--app", "TextEdit", "--quit"]) }

        _ = runAxon(["wait-ready", "--app", "TextEdit", "--timeout", "5"])

        // Make sure there is a frontmost document so Format menu items are enabled.
        // TextEdit launches with an Untitled document by default.
        let menu = runAxon(["menu", "--app", "TextEdit", "--path", "Format > Font > Show Fonts"])
        try XCTSkipUnless(menu.exitCode == 0, "menu nav failed (labels may differ by locale/OS): \(menu.stderr)")

        // The Font panel should now exist. It appears as a separate window titled "Fonts".
        // Give it a moment to appear.
        let fontPanelPresent = runAxon([
            "wait", "--app", "TextEdit",
            "--label", "Fonts",
            "--appear",
            "--timeout", "3"
        ])
        XCTAssertEqual(fontPanelPresent.exitCode, 0, "Font panel did not appear: \(fontPanelPresent.stderr)")

        // Close it.
        _ = runAxon(["key", "--app", "TextEdit", "--key", "t", "--modifiers", "command"])
    }
```

- [ ] **Step 2: Compile E2E + run unit/integration**

```bash
swift build --target AxonE2ETests
swift test --filter AxonUnitTests --filter AxonIntegrationTests
```

- [ ] **Step 3: Commit**

```bash
git add Tests/AxonE2ETests/E2ETests.swift
git commit -m "E2E: TextEdit Format > Font > Show Fonts menu navigation"
```

---

## Task 12: Canonical full end-to-end flow against AxonSample

**Files:**
- Modify: `Tests/AxonE2ETests/AxonSampleE2ETests.swift` (append)

- [ ] **Step 1: Append the canonical test**

Append at the end of the `AxonSampleE2ETests` class body:

```swift
    // MARK: - 8. Canonical end-to-end flow

    func testCanonicalEndToEndFlow() throws {
        try skipIfSampleNotBuilt()

        // Phase 1: launch and sanity-check environment.
        try launchSample()
        let doctor = runAxon(["doctor"])
        // doctor exits 0 or 1 depending on AX state; only fail on non-JSON output.
        XCTAssertNotNil(parseJSON(doctor.stdout), "doctor output should be JSON")

        // Phase 2: create and populate a note via menu.
        _ = runAxon(["menu", "--app", "AxonSample", "--path", "File > New"])
        _ = runAxon([
            "type", "--app", "AxonSample",
            "--identifier", "noteTitleField",
            "--text", "Meeting Notes",
            "--clear"
        ])
        _ = runAxon([
            "type", "--app", "AxonSample",
            "--identifier", "noteBodyField",
            "--text", "Discussed roadmap for Q2",
            "--clear"
        ])

        let titleOk = runAxon([
            "assert", "--app", "AxonSample",
            "--identifier", "noteTitleField",
            "--value", "Meeting Notes"
        ])
        XCTAssertEqual(titleOk.exitCode, 0, "title assert: \(titleOk.stderr)")

        let dirtyOk = runAxon([
            "assert", "--app", "AxonSample",
            "--identifier", "dirtyStatus",
            "--value", "modified"
        ])
        XCTAssertEqual(dirtyOk.exitCode, 0, "dirty assert: \(dirtyOk.stderr)")

        // Phase 3: save via ⌘S, confirm clean.
        _ = runAxon(["key", "--app", "AxonSample", "--key", "s", "--modifiers", "command"])
        let cleanOk = runAxon([
            "assert", "--app", "AxonSample",
            "--identifier", "dirtyStatus",
            "--value", "clean"
        ])
        XCTAssertEqual(cleanOk.exitCode, 0, "clean assert: \(cleanOk.stderr)")

        // Phase 4: a second note via ⌘N, then delete it via menu.
        _ = runAxon(["key", "--app", "AxonSample", "--key", "n", "--modifiers", "command"])
        _ = runAxon([
            "type", "--app", "AxonSample",
            "--identifier", "noteTitleField",
            "--text", "Throwaway",
            "--clear"
        ])
        let beforeDelete = runAxon(["exists", "--app", "AxonSample", "--label", "Throwaway"])
        XCTAssertEqual(parseJSON(beforeDelete.stdout)?["exists"] as? Bool, true)

        _ = runAxon(["menu", "--app", "AxonSample", "--path", "File > Delete"])
        let afterDelete = runAxon(["exists", "--app", "AxonSample", "--label", "Throwaway"])
        XCTAssertEqual(parseJSON(afterDelete.stdout)?["exists"] as? Bool, false)

        // Phase 5: make the remaining note dirty, attempt close, dismiss with Don't Save.
        _ = runAxon([
            "type", "--app", "AxonSample",
            "--identifier", "noteBodyField",
            "--text", " (addendum)",
            "--clear"
        ])
        _ = runAxon(["key", "--app", "AxonSample", "--key", "w", "--modifiers", "command"])

        let sheet = runAxon(["exists", "--app", "AxonSample", "--sheet"])
        XCTAssertEqual(parseJSON(sheet.stdout)?["exists"] as? Bool, true)

        let dontSave = runAxon([
            "click", "--app", "AxonSample",
            "--sheet", "--label", "Don't Save"
        ])
        XCTAssertEqual(dontSave.exitCode, 0, "Don't Save click: \(dontSave.stderr)")

        // Phase 6: take a screenshot for documentation.
        let shotPath = NSTemporaryDirectory() + "axon-sample-canonical.png"
        let shot = runAxon(["screenshot", "--app", "AxonSample", "--output", shotPath])
        // Screenshot may fail if screen recording isn't granted — that's OK, it's not the point of this test.
        XCTAssertTrue(shot.exitCode == 0 || shot.stderr.contains("screen"), "unexpected screenshot failure: \(shot.stderr)")
    }
```

- [ ] **Step 2: Compile E2E + run unit/integration**

```bash
swift build --target AxonE2ETests
swift test --filter AxonUnitTests --filter AxonIntegrationTests
```

- [ ] **Step 3: Commit**

```bash
git add Tests/AxonE2ETests/AxonSampleE2ETests.swift
git commit -m "E2E: canonical end-to-end flow against AxonSample"
```

---

## Task 13: Update CLAUDE.md with `make verify`

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add a one-line pointer to `make verify`**

Open `CLAUDE.md`. Inside the `## Build & Test` section, append:

```bash
make verify                               # Builds axon + sample, runs all three test tiers (local only)
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "CLAUDE.md: document 'make verify' as the full local check"
```

---

## End-of-milestone checklist

At this point:

- `swift test --filter AxonUnitTests --filter AxonIntegrationTests` — all green on both `axon` and any tests in `Samples/AxonSample/` (the sample has no Swift tests, its fitness function is the E2E suite).
- `cd Samples/AxonSample && make build` produces `AxonSample.app`.
- `make verify` (run locally by the maintainer) is green.
- Tree on the branch shows ~13 commits, each a small red-green-commit cycle.
- `Samples/AxonSample/` is not a dependency of the main axon target.
- No new external dependencies.
- E2E tests are NOT run by CI or background agents.

**Human maintainer must confirm** `make verify` is green before merging M2 to main. If any E2E test is flaky (e.g., timing issues with SwiftUI's sheet presentation), add small retries inside the test, not around it.

After M2 merges, M3 writes a plan for LICENSE, README, GHA CI (unit+integration only), signed-notarized release pipeline, and the Homebrew tap formula.
