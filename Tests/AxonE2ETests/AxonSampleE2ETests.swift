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
}
