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

    // MARK: - 4. File > New menu

    func testFileNewMenuAddsNote() throws {
        try skipIfSampleNotBuilt()
        try launchSample()

        let before = runAxon(["exists", "--app", "AxonSample", "--label", "Untitled"])
        XCTAssertEqual(parseJSON(before.stdout)?["exists"] as? Bool, false)

        let menu = runAxon(["menu", "--app", "AxonSample", "--path", "File > New"])
        XCTAssertEqual(menu.exitCode, 0, "menu nav failed: \(menu.stderr)")

        let wait = runAxon(["wait", "--app", "AxonSample", "--label", "Untitled", "--appear", "--timeout", "3"])
        XCTAssertEqual(wait.exitCode, 0, "Untitled row did not appear: \(wait.stderr)")

        let after = runAxon(["exists", "--app", "AxonSample", "--label", "Untitled"])
        XCTAssertEqual(parseJSON(after.stdout)?["exists"] as? Bool, true)
    }

    func testCommandNAddsNote() throws {
        try skipIfSampleNotBuilt()
        try launchSample()

        let key = runAxon(["key", "--app", "AxonSample", "--key", "n", "--modifiers", "command"])
        XCTAssertEqual(key.exitCode, 0, "⌘N failed: \(key.stderr)")

        let wait = runAxon(["wait", "--app", "AxonSample", "--label", "Untitled", "--appear", "--timeout", "3"])
        XCTAssertEqual(wait.exitCode, 0, "Untitled row did not appear: \(wait.stderr)")

        let row = runAxon(["exists", "--app", "AxonSample", "--label", "Untitled"])
        XCTAssertEqual(parseJSON(row.stdout)?["exists"] as? Bool, true)
    }

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
            "--label", "modified",
            "--exists"
        ])
        XCTAssertEqual(dirty.exitCode, 0, "dirty assert failed: \(dirty.stderr)")

        // Save via menu
        let save = runAxon(["menu", "--app", "AxonSample", "--path", "File > Save"])
        XCTAssertEqual(save.exitCode, 0, "save failed: \(save.stderr)")

        let clean = runAxon([
            "assert", "--app", "AxonSample",
            "--label", "clean",
            "--exists"
        ])
        XCTAssertEqual(clean.exitCode, 0, "clean assert failed: \(clean.stderr)")
    }

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

        let sheetWait = runAxon(["wait", "--app", "AxonSample", "--sheet", "--appear", "--timeout", "3"])
        XCTAssertEqual(sheetWait.exitCode, 0, "sheet did not appear: \(sheetWait.stderr)")

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
            "--label", "modified",
            "--exists"
        ])
        XCTAssertEqual(dirtyOk.exitCode, 0, "dirty assert: \(dirtyOk.stderr)")

        // Phase 3: save via ⌘S, confirm clean.
        _ = runAxon(["key", "--app", "AxonSample", "--key", "s", "--modifiers", "command"])
        let cleanOk = runAxon([
            "assert", "--app", "AxonSample",
            "--label", "clean",
            "--exists"
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

        let sheetWait = runAxon(["wait", "--app", "AxonSample", "--sheet", "--appear", "--timeout", "3"])
        XCTAssertEqual(sheetWait.exitCode, 0, "sheet did not appear: \(sheetWait.stderr)")

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
}
