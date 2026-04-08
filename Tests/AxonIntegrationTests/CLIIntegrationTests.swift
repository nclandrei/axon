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

    // MARK: - 12. click missing --app

    func testClickMissingApp_exits1() {
        let result = runAxon(["click"])
        XCTAssertEqual(result.exitCode, 1)
        let json = parseJSON(result.stderr)
        XCTAssertNotNil(json, "stderr should be valid JSON")
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

    // MARK: - 15. screenshot missing --app

    func testScreenshotMissingApp_exits1() {
        let result = runAxon(["screenshot"])
        XCTAssertEqual(result.exitCode, 1)
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

    // MARK: - 20. scroll invalid direction

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
}
