import Foundation
import XCTest

final class CLIIntegrationTests: XCTestCase {

    // MARK: - Helper

    /// Path to the project root, derived from the test source file location.
    private static let projectRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // AxonIntegrationTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // project root

    /// Path to the release binary built via `swift build -c release`.
    private static let binaryURL: URL = projectRoot
        .appendingPathComponent(".build/release/axon")

    /// Runs the axon binary with the given arguments and returns stdout, stderr, and exit code.
    @discardableResult
    private func runAxon(_ args: [String] = []) -> (stdout: String, stderr: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = Self.binaryURL
        process.arguments = args

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

    /// Parses a JSON string into a dictionary.
    private func parseJSON(_ string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    // MARK: - Test: Binary exists

    func testBinaryExists() {
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: Self.binaryURL.path),
            "Release binary not found at \(Self.binaryURL.path). Run `swift build -c release` first."
        )
    }

    // MARK: - 1. No args

    func testNoArgs_exitsWithError() {
        let result = runAxon()
        XCTAssertEqual(result.exitCode, 1, "No-args invocation should exit 1")
        // No args shows help text to stderr (not JSON error)
        XCTAssertTrue(result.stderr.contains("axon"), "stderr should contain help text")
    }

    // MARK: - 2. --help

    func testDashDashHelp_exits0() {
        let result = runAxon(["--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("axon - macOS Accessibility CLI"),
            "stderr should contain main help text"
        )
    }

    // MARK: - 3. help

    func testHelpCommand_exits0() {
        let result = runAxon(["help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("axon - macOS Accessibility CLI"),
            "stderr should contain help text"
        )
    }

    // MARK: - 4. -h

    func testDashH_exits0() {
        let result = runAxon(["-h"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("axon - macOS Accessibility CLI"))
    }

    // MARK: - 5. help tree

    func testHelpTree_exits0() {
        let result = runAxon(["help", "tree"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("axon tree"),
            "stderr should contain tree-specific help"
        )
    }

    // MARK: - 6. tree --help

    func testTreeDashDashHelp_exits0() {
        let result = runAxon(["tree", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("axon tree"),
            "stderr should contain tree-specific help"
        )
    }

    // MARK: - 7. Unknown command

    func testUnknownCommand_exits1() {
        let result = runAxon(["foobar"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json, "stderr should be valid JSON")
        XCTAssertEqual(json?["error"] as? String, "unknown_command")
    }

    // MARK: - 8. list

    func testList_exits0_validJSON() {
        let result = runAxon(["list"])
        XCTAssertEqual(result.exitCode, 0, "list should exit 0")
        let json = parseJSON(result.stdout)
        XCTAssertNotNil(json, "stdout should be valid JSON")
        XCTAssertNotNil(json?["apps"] as? [Any], "JSON should have 'apps' array")
    }

    // MARK: - 9. list output format

    func testList_appFields() {
        let result = runAxon(["list"])
        XCTAssertEqual(result.exitCode, 0)
        let json = parseJSON(result.stdout)
        guard let apps = json?["apps"] as? [[String: Any]] else {
            XCTFail("Expected 'apps' to be an array of dictionaries")
            return
        }
        // There should be at least one running GUI app (e.g., Finder)
        XCTAssertFalse(apps.isEmpty, "Should have at least one running app")
        if let first = apps.first {
            XCTAssertNotNil(first["name"] as? String, "App should have 'name' field")
            // bundleID can be null for some apps, so just check key exists
            XCTAssertTrue(first.keys.contains("bundleID"), "App should have 'bundleID' field")
            XCTAssertNotNil(first["pid"], "App should have 'pid' field")
        }
    }

    // MARK: - 10. launch missing options

    func testLaunchMissingOptions_exits1() {
        let result = runAxon(["launch"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json, "stderr should be valid JSON")
        XCTAssertEqual(json?["error"] as? String, "missing_option")
    }

    // MARK: - 11. tree missing --app

    func testTreeMissingApp_exits1() {
        let result = runAxon(["tree"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json, "stderr should be valid JSON")
        XCTAssertEqual(json?["error"] as? String, "missing_option")
    }

    // MARK: - double-click --help

    func testDoubleClickHelp_exits0() {
        let result = runAxon(["double-click", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("axon double-click"))
    }

    // MARK: - double-click missing --app

    func testDoubleClickMissingApp_exits1() {
        let result = runAxon(["double-click"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["error"] as? String, "missing_option")
    }

    // MARK: - right-click --help

    func testRightClickHelp_exits0() {
        let result = runAxon(["right-click", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("axon right-click"))
    }

    // MARK: - right-click missing --app

    func testRightClickMissingApp_exits1() {
        let result = runAxon(["right-click"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["error"] as? String, "missing_option")
    }

    // MARK: - 12. click missing --app

    func testClickMissingApp_exits1() {
        let result = runAxon(["click"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json, "stderr should be valid JSON")
        XCTAssertEqual(json?["error"] as? String, "missing_option")
    }

    // MARK: - key --help

    func testKeyHelp_exits0() {
        let result = runAxon(["key", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("axon key"))
    }

    // MARK: - key missing --app

    func testKeyMissingApp_exits1() {
        let result = runAxon(["key"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["error"] as? String, "missing_option")
    }

    // MARK: - key missing --key

    func testKeyMissingKey_exits1() {
        let result = runAxon(["key", "--app", "Finder"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["error"] as? String, "missing_option")
    }

    // MARK: - hover --help

    func testHoverHelp_exits0() {
        let result = runAxon(["hover", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("axon hover"))
    }

    // MARK: - hover missing --app

    func testHoverMissingApp_exits1() {
        let result = runAxon(["hover"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["error"] as? String, "missing_option")
    }

    // MARK: - 13. type missing --app

    func testTypeMissingApp_exits1() {
        let result = runAxon(["type"])
        XCTAssertEqual(result.exitCode, 1)
    }

    // MARK: - 14. scroll missing --app

    func testScrollMissingApp_exits1() {
        let result = runAxon(["scroll"])
        XCTAssertEqual(result.exitCode, 1)
    }

    // MARK: - scroll --help mentions --amount

    func testScrollHelpMentionsAmount() {
        let result = runAxon(["scroll", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("--amount"))
    }

    // MARK: - 15. screenshot missing --app

    func testScreenshotMissingApp_exits1() {
        let result = runAxon(["screenshot"])
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("--app is required"))
    }

    // MARK: - screenshot --full-screen without --app succeeds

    func testScreenshotFullScreenWithoutApp_exits0() {
        let result = runAxon(["screenshot", "--full-screen", "--output", "/tmp/axon-test-fullscreen.png"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("path"))
    }

    // MARK: - screenshot --help includes --identifier

    func testScreenshotElementHelp() {
        let result = runAxon(["screenshot", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("--identifier"))
    }

    // MARK: - 16. activate missing --app

    func testActivateMissingApp_exits1() {
        let result = runAxon(["activate"])
        XCTAssertEqual(result.exitCode, 1)
    }

    // MARK: - 17. close missing --app

    func testCloseMissingApp_exits1() {
        let result = runAxon(["close"])
        XCTAssertEqual(result.exitCode, 1)
    }

    // MARK: - 18. wait missing --app

    func testWaitMissingApp_exits1() {
        let result = runAxon(["wait"])
        XCTAssertEqual(result.exitCode, 1)
    }

    // MARK: - 19. wait missing appear/disappear

    func testWaitMissingAppearDisappear_exits1() {
        let result = runAxon(["wait", "--app", "Finder"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json, "stderr should be valid JSON")
        XCTAssertEqual(json?["error"] as? String, "missing_option")
    }

    // MARK: - 20. get-value --help

    func testGetValueHelp_exits0() {
        let result = runAxon(["get-value", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("axon get-value"))
    }

    // MARK: - 21. get-value missing --app

    func testGetValueMissingApp_exits1() {
        let result = runAxon(["get-value"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json, "stderr should be valid JSON")
        XCTAssertEqual(json?["error"] as? String, "missing_option")
    }

    // MARK: - 22. get-value missing selector

    func testGetValueMissingSelector_exits1() {
        let result = runAxon(["get-value", "--app", "Finder"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json, "stderr should be valid JSON")
        XCTAssertEqual(json?["error"] as? String, "missing_selector")
    }

    // MARK: - 23. focused --help

    func testFocusedHelp_exits0() {
        let result = runAxon(["focused", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("axon focused"))
    }

    // MARK: - 24. focused missing --app

    func testFocusedMissingApp_exits1() {
        let result = runAxon(["focused"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json, "stderr should be valid JSON")
        XCTAssertEqual(json?["error"] as? String, "missing_option")
    }

    // MARK: - 25. window-info --help

    func testWindowInfoHelp_exits0() {
        let result = runAxon(["window-info", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("axon window-info"))
    }

    // MARK: - 26. window-info missing --app

    func testWindowInfoMissingApp_exits1() {
        let result = runAxon(["window-info"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json, "stderr should be valid JSON")
        XCTAssertEqual(json?["error"] as? String, "missing_option")
    }

    // MARK: - 27. menu --help

    func testMenuHelp_exits0() {
        let result = runAxon(["menu", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("axon menu"))
    }

    // MARK: - 28. menu missing --app

    func testMenuMissingApp_exits1() {
        let result = runAxon(["menu"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json, "stderr should be valid JSON")
        XCTAssertEqual(json?["error"] as? String, "missing_option")
    }

    // MARK: - 29. menu missing --path (when --list not provided)

    func testMenuMissingPath_exits1() {
        let result = runAxon(["menu", "--app", "Finder"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json, "stderr should be valid JSON")
        XCTAssertEqual(json?["error"] as? String, "missing_option")
    }

    // MARK: - 30. scroll invalid direction

    func testScrollInvalidDirection_exits1() {
        let result = runAxon(["scroll", "--app", "Finder", "--identifier", "x", "--direction", "diagonal"])
        XCTAssertEqual(result.exitCode, 1)
        // The error could be about AX permissions or invalid direction depending on execution order.
        // If AX permission check happens first, we get that error. Otherwise invalid_direction.
        // Either way, it should exit 1 and have JSON error on stderr.
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json, "stderr should be valid JSON for invalid direction or AX error")
        let errorCode = json?["error"] as? String
        XCTAssertNotNil(errorCode, "Error JSON should have 'error' field")
    }

    // MARK: - move-resize

    func testMoveResizeHelp_exits0() {
        let result = runAxon(["move-resize", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("axon move-resize"))
    }

    func testMoveResizeMissingApp_exits1() {
        let result = runAxon(["move-resize"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["error"] as? String, "missing_option")
    }

    func testMoveResizeMissingDimensions_exits1() {
        let result = runAxon(["move-resize", "--app", "Finder"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["error"] as? String, "missing_option")
        let msg = json?["message"] as? String ?? ""
        XCTAssertTrue(msg.contains("--x") || msg.contains("--y") || msg.contains("--width") || msg.contains("--height"))
    }

    func testMoveResizeHelpMentionsMinimize() {
        let result = runAxon(["move-resize", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("--minimize"))
    }

    func testMoveResizeHelpMentionsFullscreen() {
        let result = runAxon(["move-resize", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("--fullscreen"))
    }

    // MARK: - clipboard

    func testClipboardHelp_exits0() {
        let result = runAxon(["clipboard", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("axon clipboard"))
    }

    func testClipboardMissingMode_exits1() {
        let result = runAxon(["clipboard"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["error"] as? String, "missing_option")
    }

    func testClipboardSetMissingText_exits1() {
        let result = runAxon(["clipboard", "--set"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["error"] as? String, "missing_option")
    }

    func testClipboardGet_exits0() {
        let result = runAxon(["clipboard", "--get"])
        XCTAssertEqual(result.exitCode, 0)
        let json = parseJSON(result.stdout)
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["success"] as? Bool, true)
        XCTAssertTrue(json?.keys.contains("text") == true)
    }

    func testClipboardSetThenGet_roundTrip() {
        let testText = "axon-test-\(UUID().uuidString)"
        let setResult = runAxon(["clipboard", "--set", "--text", testText])
        XCTAssertEqual(setResult.exitCode, 0)
        let setJSON = parseJSON(setResult.stdout)
        XCTAssertEqual(setJSON?["success"] as? Bool, true)
        let getResult = runAxon(["clipboard", "--get"])
        XCTAssertEqual(getResult.exitCode, 0)
        let getJSON = parseJSON(getResult.stdout)
        XCTAssertEqual(getJSON?["success"] as? Bool, true)
        XCTAssertEqual(getJSON?["text"] as? String, testText)
    }

    // MARK: - wait-for-value

    func testWaitForValueHelp_exits0() {
        let result = runAxon(["wait-for-value", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("axon wait-for-value"))
    }

    func testWaitForValueMissingApp_exits1() {
        let result = runAxon(["wait-for-value"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["error"] as? String, "missing_option")
    }

    func testWaitForValueMissingSelector_exits1() {
        let result = runAxon(["wait-for-value", "--app", "Finder"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["error"] as? String, "missing_selector")
    }

    // MARK: - click/double-click/right-click --modifiers in help

    func testClickModifiersHelp() {
        let result = runAxon(["click", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("--modifiers"), "click --help should mention --modifiers")
    }

    func testDoubleClickModifiersHelp() {
        let result = runAxon(["double-click", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("--modifiers"), "double-click --help should mention --modifiers")
    }

    func testRightClickModifiersHelp() {
        let result = runAxon(["right-click", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("--modifiers"), "right-click --help should mention --modifiers")
    }

    // MARK: - set-value

    func testSetValueHelp_exits0() {
        let result = runAxon(["set-value", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("axon set-value"))
    }

    func testSetValueMissingApp_exits1() {
        let result = runAxon(["set-value"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["error"] as? String, "missing_option")
    }

    func testSetValueMissingValue_exits1() {
        let result = runAxon(["set-value", "--app", "Finder", "--identifier", "x"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["error"] as? String, "missing_option")
    }

    func testHelpSetValue_exits0() {
        let result = runAxon(["help", "set-value"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("axon set-value"))
    }

    // MARK: - help dispatches for new commands

    func testHelpMoveResize_exits0() {
        let result = runAxon(["help", "move-resize"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("axon move-resize"))
    }

    func testHelpClipboard_exits0() {
        let result = runAxon(["help", "clipboard"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("axon clipboard"))
    }

    func testHelpWaitForValue_exits0() {
        let result = runAxon(["help", "wait-for-value"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("axon wait-for-value"))
    }

    // MARK: - vm-acquire

    func testVMAcquireHelp_exits0() {
        let result = runAxon(["vm-acquire", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("axon vm-acquire"),
            "stderr should contain vm-acquire-specific help"
        )
    }

    func testHelpVMAcquire_exits0() {
        let result = runAxon(["help", "vm-acquire"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("axon vm-acquire"))
    }

    func testVMAcquireMissingBase_exits1() {
        let result = runAxon(["vm-acquire"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json, "stderr should be valid JSON")
        XCTAssertEqual(json?["error"] as? String, "missing_option")
    }

    // MARK: - vm-release

    func testVMReleaseHelp_exits0() {
        let result = runAxon(["vm-release", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("axon vm-release"),
            "stderr should contain vm-release-specific help"
        )
    }

    func testHelpVMRelease_exits0() {
        let result = runAxon(["help", "vm-release"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("axon vm-release"))
    }

    func testVMReleaseMissingNameAndAll_exits1() {
        let result = runAxon(["vm-release"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json, "stderr should be valid JSON")
        XCTAssertEqual(json?["error"] as? String, "missing_option")
    }

    // MARK: - vm-list

    func testVMListHelp_exits0() {
        let result = runAxon(["vm-list", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("axon vm-list"),
            "stderr should contain vm-list-specific help"
        )
    }

    func testHelpVMList_exits0() {
        let result = runAxon(["help", "vm-list"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("axon vm-list"))
    }

    func testVMList_exits0_validJSON() {
        let result = runAxon(["vm-list"])
        XCTAssertEqual(result.exitCode, 0, "vm-list should exit 0 even with empty registry")
        let json = parseJSON(result.stdout)
        XCTAssertNotNil(json, "stdout should be valid JSON")
        XCTAssertEqual(json?["success"] as? Bool, true)
        XCTAssertNotNil(json?["vms"] as? [Any], "JSON should have 'vms' array")
    }

    // MARK: - vm-bake

    func testVMBakeHelp_exits0() {
        let result = runAxon(["vm-bake", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("axon vm-bake"),
            "stderr should contain vm-bake-specific help"
        )
    }

    func testHelpVMBake_exits0() {
        let result = runAxon(["help", "vm-bake"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("axon vm-bake"))
    }

    func testVMBakeMissingSource_exits1() {
        let result = runAxon(["vm-bake", "--name", "axon-myapp-base"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json, "stderr should be valid JSON")
        XCTAssertEqual(json?["error"] as? String, "missing_option")
    }

    func testVMBakeMissingName_exits1() {
        let result = runAxon(["vm-bake", "--source", "sonoma-base"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json, "stderr should be valid JSON")
        XCTAssertEqual(json?["error"] as? String, "missing_option")
    }

    // MARK: - launch --help mentions accessory/menu bar apps

    func testLaunchHelpMentionsAccessoryApps() {
        let result = runAxon(["launch", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("menu bar"),
            "launch --help should mention menu bar / accessory app support"
        )
        XCTAssertTrue(
            result.stderr.contains("LSUIElement"),
            "launch --help should mention LSUIElement"
        )
    }

    // MARK: - launch --help mentions /Applications fallback

    func testLaunchHelpMentionsFallback() {
        let result = runAxon(["launch", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("/Applications"),
            "launch --help should mention /Applications fallback"
        )
    }

    // MARK: - main --help mentions VM commands

    func testMainHelpMentionsVMCommands() {
        let result = runAxon(["--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("vm-acquire"),
            "Main help should advertise vm-acquire"
        )
        XCTAssertTrue(
            result.stderr.contains("vm-release"),
            "Main help should advertise vm-release"
        )
        XCTAssertTrue(
            result.stderr.contains("vm-list"),
            "Main help should advertise vm-list"
        )
        XCTAssertTrue(
            result.stderr.contains("vm-bake"),
            "Main help should advertise vm-bake"
        )
    }

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

    func testAssertAppNotFoundExitsTwoWhenElementRequired() {
        let result = runAxon(["assert", "--app", "NonExistentApp_XYZ_999", "--identifier", "x", "--exists"])
        XCTAssertEqual(result.exitCode, 2, "assert should exit 2 when the app is missing and the assertion requires the element")
    }

    func testAssertNotExistsPassesOnMissingApp() {
        let result = runAxon(["assert", "--app", "NonExistentApp_XYZ_999", "--identifier", "x", "--not-exists"])
        XCTAssertEqual(result.exitCode, 0, "assert --not-exists should pass (exit 0) when the app is missing")
    }

    func testMainHelpListsAssert() {
        let result = runAxon(["--help"])
        XCTAssertTrue(result.stderr.contains("assert"))
    }

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

    // MARK: - wait --sheet / --alert

    func testWaitHelpMentionsSheetAlert() {
        let result = runAxon(["wait", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        // Wait help may list --sheet or sheet; be permissive
        XCTAssertTrue(
            result.stderr.contains("sheet") || result.stderr.contains("--sheet"),
            "wait --help should mention sheet targeting"
        )
    }

    // MARK: - screenshot --sheet / --alert

    func testScreenshotHelpMentionsSheet() {
        let result = runAxon(["screenshot", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("--sheet") || result.stderr.contains("sheet"),
            "screenshot --help should mention sheet targeting"
        )
    }

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

    // MARK: - assert input validation

    func testAssertNoSelectorIsMissingSelectorError() {
        // Missing selector with any assertion spec must error out, including --not-exists.
        let result = runAxon(["assert", "--app", "NonExistentApp_XYZ_999", "--not-exists"])
        XCTAssertEqual(result.exitCode, 1, "no selector provided should be a missing_option error")
        XCTAssertTrue(
            result.stderr.contains("missing_selector") || result.stderr.lowercased().contains("selector"),
            "stderr should signal a missing selector"
        )
    }

    func testAssertExistsAndNotExistsRejected() {
        let result = runAxon(["assert", "--app", "Finder", "--identifier", "x", "--exists", "--not-exists"])
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(
            result.stderr.contains("conflicting") || result.stderr.contains("incompatible") || result.stderr.lowercased().contains("cannot"),
            "stderr should call out the contradictory flags"
        )
    }

    func testAssertEnabledAndDisabledRejected() {
        let result = runAxon(["assert", "--app", "Finder", "--identifier", "x", "--enabled", "--disabled"])
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(
            result.stderr.contains("conflicting") || result.stderr.contains("incompatible") || result.stderr.lowercased().contains("cannot"),
            "stderr should call out the contradictory flags"
        )
    }

    // MARK: - vm-bake --for-bundle

    func testVMBakeForBundleWritesBasesEntry() throws {
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
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: registryPath),
            "vm-bake without --for-bundle must not create the registry"
        )
    }
}
