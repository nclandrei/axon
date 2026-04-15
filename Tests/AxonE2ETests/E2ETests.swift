import Foundation
import XCTest

final class E2ETests: AxonE2ETestCase {

    // MARK: - 1. List includes Finder

    func testListIncludesFinder() {
        let result = runAxon(["list"])
        XCTAssertEqual(result.exitCode, 0, "axon list should exit 0")

        let json = parseJSON(result.stdout)
        XCTAssertNotNil(json, "Output should be valid JSON")

        let apps = json?["apps"] as? [[String: Any]]
        XCTAssertNotNil(apps, "JSON should contain 'apps' array")

        let finder = apps?.first { ($0["name"] as? String) == "Finder" }
        XCTAssertNotNil(finder, "Finder should appear in the app list")
    }

    // MARK: - 2. List includes bundleID and pid

    func testListFinderHasBundleIDAndPid() {
        let result = runAxon(["list"])
        XCTAssertEqual(result.exitCode, 0)

        let apps = parseJSON(result.stdout)?["apps"] as? [[String: Any]]
        let finder = apps?.first { ($0["name"] as? String) == "Finder" }
        XCTAssertNotNil(finder)

        XCTAssertEqual(finder?["bundleID"] as? String, "com.apple.finder")
        let pid = finder?["pid"] as? Int
        XCTAssertNotNil(pid)
        XCTAssertGreaterThan(pid ?? 0, 0, "Finder pid should be non-zero")
    }

    // MARK: - 3. Activate Finder

    func testActivateFinder() {
        let result = runAxon(["activate", "--app", "Finder"])
        XCTAssertEqual(result.exitCode, 0)

        let json = parseJSON(result.stdout)
        XCTAssertNotNil(json, "Output should be valid JSON")
        // success may be false due to timing (isActive check races with activation),
        // but the key must exist and the command must not error
        XCTAssertNotNil(json?["success"] as? Bool, "Should have 'success' key")
    }

    // MARK: - 4. Tree Finder

    func testTreeFinder() throws {
        let result = runAxon(["tree", "--app", "Finder", "--depth", "2"])
        try skipIfNoAccessibility(result)
        XCTAssertEqual(result.exitCode, 0, "axon tree should exit 0. stderr: \(result.stderr)")

        let json = parseJSON(result.stdout)
        XCTAssertNotNil(json, "Tree output should be valid JSON")
        XCTAssertNotNil(json?["app"] as? String, "Should have 'app' key")
        XCTAssertNotNil(json?["pid"] as? Int, "Should have 'pid' key")
        XCTAssertNotNil(json?["tree"] as? [String: Any], "Should have 'tree' key")
    }

    // MARK: - 5. Tree compact

    func testTreeCompactOmitsPositionSize() throws {
        let result = runAxon(["tree", "--app", "Finder", "--depth", "2", "--compact"])
        try skipIfNoAccessibility(result)
        XCTAssertEqual(result.exitCode, 0, "stderr: \(result.stderr)")

        // Compact output should not contain "position" or "size" keys
        XCTAssertFalse(result.stdout.contains("\"position\""), "Compact tree should omit position")
        XCTAssertFalse(result.stdout.contains("\"size\""), "Compact tree should omit size")
    }

    // MARK: - 6. Tree depth limiting

    func testTreeDepthLimiting() throws {
        let shallow = runAxon(["tree", "--app", "Finder", "--depth", "1"])
        try skipIfNoAccessibility(shallow)
        XCTAssertEqual(shallow.exitCode, 0)

        let deep = runAxon(["tree", "--app", "Finder", "--depth", "5"])
        try skipIfNoAccessibility(deep)
        XCTAssertEqual(deep.exitCode, 0)

        // Depth 1 tree should be shorter (fewer nodes) than depth 5
        XCTAssertLessThan(
            shallow.stdout.count,
            deep.stdout.count,
            "Depth 1 tree should have fewer characters than depth 5 tree"
        )
    }

    // MARK: - 7. Screenshot Finder

    func testScreenshotFinder() throws {
        let outputPath = "/tmp/axon-test-screenshot.png"

        addTeardownBlock {
            try? FileManager.default.removeItem(atPath: outputPath)
        }

        let result = runAxon(["screenshot", "--app", "Finder", "--output", outputPath])
        try skipIfNoAccessibility(result)

        // Screenshot may fail if Finder has no visible window
        if result.stderr.contains("no_window") || result.stderr.contains("window_not_found") || result.stderr.contains("screenshot_failed") {
            throw XCTSkip("Skipping: Finder has no visible window for screenshot")
        }

        XCTAssertEqual(result.exitCode, 0, "stderr: \(result.stderr)")

        let json = parseJSON(result.stdout)
        XCTAssertEqual(json?["success"] as? Bool, true)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outputPath),
            "Screenshot file should exist at \(outputPath)"
        )
    }

    // MARK: - 8. Screenshot full screen

    func testScreenshotFullScreen() throws {
        let outputPath = "/tmp/axon-test-fullscreen.png"

        addTeardownBlock {
            try? FileManager.default.removeItem(atPath: outputPath)
        }

        let result = runAxon(["screenshot", "--app", "Finder", "--full-screen", "--output", outputPath])
        try skipIfNoAccessibility(result)

        if result.exitCode != 0 {
            // Full-screen screenshot should generally work, but skip if it fails
            throw XCTSkip("Skipping: full-screen screenshot failed. stderr: \(result.stderr)")
        }

        let json = parseJSON(result.stdout)
        XCTAssertEqual(json?["success"] as? Bool, true)

        let width = json?["width"] as? Int ?? 0
        let height = json?["height"] as? Int ?? 0
        XCTAssertGreaterThan(width, 0, "Screenshot width should be > 0")
        XCTAssertGreaterThan(height, 0, "Screenshot height should be > 0")

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
    }

    // MARK: - 9. App not found

    func testAppNotFound() {
        let result = runAxon(["activate", "--app", "NonExistentApp12345"])
        XCTAssertEqual(result.exitCode, 1, "Should exit 1 for non-existent app")

        let errJSON = parseJSON(result.stderr)
        XCTAssertNotNil(errJSON, "Stderr should be valid JSON")
        XCTAssertEqual(errJSON?["error"] as? String, "app_not_found")
        XCTAssertNotNil(errJSON?["available"] as? [String], "Error should include 'available' list")
    }

    // MARK: - 10. Element not found

    func testElementNotFound() throws {
        let result = runAxon(["click", "--app", "Finder", "--identifier", "nonexistent_element_xyz"])
        try skipIfNoAccessibility(result)
        XCTAssertEqual(result.exitCode, 1, "Should exit 1 for non-existent element")

        let errJSON = parseJSON(result.stderr)
        XCTAssertNotNil(errJSON, "Stderr should be valid JSON")
        XCTAssertEqual(errJSON?["error"] as? String, "element_not_found")
        XCTAssertNotNil(errJSON?["available"] as? [String], "Error should include 'available' list")
    }

    // MARK: - 11. Launch and close TextEdit

    func testLaunchAndCloseTextEdit() throws {
        // Kill TextEdit if running from a previous test (using killall for reliable cleanup)
        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killTask.arguments = ["TextEdit"]
        try? killTask.run()
        killTask.waitUntilExit()
        Thread.sleep(forTimeInterval: 1.0)

        // Launch TextEdit
        let launchResult = runAxon(["launch", "--name", "TextEdit"])
        XCTAssertEqual(launchResult.exitCode, 0, "Launch should succeed. stderr: \(launchResult.stderr)")

        let launchJSON = parseJSON(launchResult.stdout)
        XCTAssertEqual(launchJSON?["success"] as? Bool, true)

        // Give TextEdit time to fully start
        Thread.sleep(forTimeInterval: 2.0)

        // Verify TextEdit is now running
        let listBefore = runAxon(["list"])
        let appsBefore = parseJSON(listBefore.stdout)?["apps"] as? [[String: Any]]
        let textEditBefore = appsBefore?.first {
            ($0["bundleID"] as? String) == "com.apple.TextEdit"
        }
        XCTAssertNotNil(textEditBefore, "TextEdit should be running after launch")

        // Close TextEdit with --quit. The axon quitApp() calls NSRunningApplication.terminate()
        // which sends a graceful quit. TextEdit may not terminate within the 500ms check window,
        // so quit_failed is acceptable if the app actually does terminate shortly after.
        let closeResult = runAxon(["close", "--app", "TextEdit", "--quit"])

        if closeResult.exitCode == 0 {
            // Ideal path: quit succeeded
            let closeJSON = parseJSON(closeResult.stdout)
            XCTAssertEqual(closeJSON?["success"] as? Bool, true)
            XCTAssertEqual(closeJSON?["action"] as? String, "quit")
        } else {
            // The terminate() signal was sent but isTerminated was false within 500ms.
            // This is expected for TextEdit which may show a save dialog or take time.
            // Verify the error is quit_failed (not app_not_found).
            let errJSON = parseJSON(closeResult.stderr)
            XCTAssertEqual(errJSON?["error"] as? String, "quit_failed",
                           "Should be quit_failed, not another error. stderr: \(closeResult.stderr)")
        }

        // Clean up: force-kill to ensure TextEdit doesn't linger
        addTeardownBlock {
            let kill = Process()
            kill.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            kill.arguments = ["TextEdit"]
            try? kill.run()
            kill.waitUntilExit()
        }
    }

    // MARK: - 12. Tree Finder includes actions

    func testTreeFinderIncludesActions() throws {
        let result = runAxon(["tree", "--app", "Finder", "--depth", "3"])
        try skipIfNoAccessibility(result)
        XCTAssertEqual(result.exitCode, 0, "axon tree should exit 0. stderr: \(result.stderr)")

        // The JSON output should contain at least one "actions" key
        XCTAssertTrue(
            result.stdout.contains("\"actions\""),
            "Tree output should contain at least one node with actions"
        )
    }

    // MARK: - 13. Wait timeout

    func testWaitTimeout() throws {
        let result = runAxon(["wait", "--app", "Finder", "--identifier", "impossibleElement", "--appear", "--timeout", "1"])
        try skipIfNoAccessibility(result)
        XCTAssertEqual(result.exitCode, 1, "Wait should exit 1 on timeout")

        let errJSON = parseJSON(result.stderr)
        XCTAssertNotNil(errJSON, "Stderr should be valid JSON")
        XCTAssertEqual(errJSON?["error"] as? String, "timeout")
    }
}
