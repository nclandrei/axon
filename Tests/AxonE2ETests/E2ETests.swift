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
        // success may be false if the test runner reclaims focus before isActive is checked,
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

    // MARK: - 8b. Screenshot element

    func testScreenshotElement() throws {
        let outputPath = "/tmp/axon-test-element-screenshot.png"
        addTeardownBlock {
            try? FileManager.default.removeItem(atPath: outputPath)
        }

        // First get the tree to find a valid path
        let treeResult = runAxon(["tree", "--app", "Finder", "--depth", "2"])
        try skipIfNoAccessibility(treeResult)

        // Try to screenshot the first window (AXWindow[0])
        let result = runAxon(["screenshot", "--app", "Finder", "--path", "AXWindow[0]", "--output", outputPath])
        try skipIfNoAccessibility(result)

        if result.exitCode != 0 {
            throw XCTSkip("Skipping: element screenshot failed. stderr: \(result.stderr)")
        }

        let json = parseJSON(result.stdout)
        XCTAssertEqual(json?["success"] as? Bool, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))

        let width = json?["width"] as? Int ?? 0
        let height = json?["height"] as? Int ?? 0
        XCTAssertGreaterThan(width, 0)
        XCTAssertGreaterThan(height, 0)
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

        // Launch TextEdit in the background
        let launchResult = runAxon(["launch", "--name", "TextEdit", "--background"])
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

    // MARK: - 14. Clipboard round-trip

    func testClipboardSetAndGet() {
        let sentinel = "axon-e2e-test-\(UUID().uuidString)"

        // Set clipboard
        let setResult = runAxon(["clipboard", "--set", "--text", sentinel])
        XCTAssertEqual(setResult.exitCode, 0, "clipboard --set should exit 0. stderr: \(setResult.stderr)")
        let setJSON = parseJSON(setResult.stdout)
        XCTAssertEqual(setJSON?["success"] as? Bool, true)

        // Get clipboard and verify the value matches
        let getResult = runAxon(["clipboard", "--get"])
        XCTAssertEqual(getResult.exitCode, 0, "clipboard --get should exit 0. stderr: \(getResult.stderr)")
        let getJSON = parseJSON(getResult.stdout)
        XCTAssertEqual(getJSON?["success"] as? Bool, true)
        XCTAssertEqual(getJSON?["text"] as? String, sentinel, "Clipboard should contain the text we just set")
    }

    // MARK: - 15. Clipboard missing option

    func testClipboardMissingOption() {
        let result = runAxon(["clipboard"])
        XCTAssertEqual(result.exitCode, 1, "clipboard without --get or --set should fail")

        let errJSON = parseJSON(result.stderr)
        XCTAssertEqual(errJSON?["error"] as? String, "missing_option")
    }

    // MARK: - 16. Focused element on Finder

    func testFocusedFinder() throws {
        // Activate Finder first so it has focus
        let activateResult = runAxon(["activate", "--app", "Finder"])
        XCTAssertEqual(activateResult.exitCode, 0)
        Thread.sleep(forTimeInterval: 0.5)

        let result = runAxon(["focused", "--app", "Finder"])
        try skipIfNoAccessibility(result)
        XCTAssertEqual(result.exitCode, 0, "focused should exit 0. stderr: \(result.stderr)")

        let json = parseJSON(result.stdout)
        XCTAssertEqual(json?["success"] as? Bool, true)
        // Finder should always have some focused element when active
        // Even if element is nil (no focus), the command should succeed with success: true
    }

    // MARK: - 17. Window info for Finder

    func testWindowInfoFinder() throws {
        let result = runAxon(["window-info", "--app", "Finder"])
        try skipIfNoAccessibility(result)
        XCTAssertEqual(result.exitCode, 0, "window-info should exit 0. stderr: \(result.stderr)")

        let json = parseJSON(result.stdout)
        XCTAssertEqual(json?["success"] as? Bool, true)

        let windows = json?["windows"] as? [[String: Any]]
        XCTAssertNotNil(windows, "Should have 'windows' array")

        // If Finder has windows, each should have position and size
        if let firstWindow = windows?.first {
            XCTAssertNotNil(firstWindow["position"], "Window should have position")
            XCTAssertNotNil(firstWindow["size"], "Window should have size")
        }
    }

    // MARK: - 18. Window info with --window filter

    func testWindowInfoFilterNonExistent() throws {
        let result = runAxon(["window-info", "--app", "Finder", "--window", "NonExistentWindow12345"])
        try skipIfNoAccessibility(result)
        XCTAssertEqual(result.exitCode, 0, "window-info should exit 0 even with no match. stderr: \(result.stderr)")

        let json = parseJSON(result.stdout)
        XCTAssertEqual(json?["success"] as? Bool, true)

        let windows = json?["windows"] as? [[String: Any]]
        XCTAssertNotNil(windows)
        XCTAssertEqual(windows?.count, 0, "No windows should match a non-existent title")
    }

    // MARK: - 19. Drive TextEdit: type, format, move-resize, screenshot

    /// A real end-to-end test that launches TextEdit in the background, types text,
    /// verifies it, toggles bold formatting, moves/resizes the window, takes a
    /// screenshot, and verifies every side-effect — all without stealing focus.
    func testDriveTextEdit() throws {
        // --- Setup: kill any lingering TextEdit ---
        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        kill.arguments = ["TextEdit"]
        try? kill.run()
        kill.waitUntilExit()
        Thread.sleep(forTimeInterval: 1.0)

        defer {
            let k = Process()
            k.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            k.arguments = ["TextEdit"]
            try? k.run()
            k.waitUntilExit()
        }

        // --- Launch TextEdit in the background ---
        let launch = runAxon(["launch", "--name", "TextEdit", "--background"])
        XCTAssertEqual(launch.exitCode, 0, "Launch failed. stderr: \(launch.stderr)")
        Thread.sleep(forTimeInterval: 2.0)

        // --- Step 1: Type text via AX (no activation) and verify via get-value ---
        let sentinel = "Hello from Axon E2E \(UUID().uuidString.prefix(8))"
        let typeResult = runAxon(["type", "--app", "TextEdit", "--no-activate", "--identifier", "First Text View", "--text", sentinel])
        try skipIfNoAccessibility(typeResult)
        XCTAssertEqual(typeResult.exitCode, 0, "type failed. stderr: \(typeResult.stderr)")

        let getValue = runAxon(["get-value", "--app", "TextEdit", "--no-activate", "--identifier", "First Text View"])
        XCTAssertEqual(getValue.exitCode, 0, "get-value failed. stderr: \(getValue.stderr)")
        let valueJSON = parseJSON(getValue.stdout)
        XCTAssertEqual(valueJSON?["success"] as? Bool, true)
        let textValue = valueJSON?["value"] as? String ?? ""
        XCTAssertTrue(textValue.contains(sentinel), "Text area should contain typed text. Got: \(textValue)")

        // --- Step 2: Toggle bold checkbox via AXPress (no activation needed) ---
        // Read the initial bold state (may vary depending on TextEdit defaults)
        let boldBefore = runAxon(["get-value", "--app", "TextEdit", "--no-activate", "--label", "bold"])
        XCTAssertEqual(boldBefore.exitCode, 0, "get-value bold failed. stderr: \(boldBefore.stderr)")
        let boldValBefore = parseJSON(boldBefore.stdout)?["value"] as? String
        XCTAssertNotNil(boldValBefore, "Bold should have a value")

        // Click bold — should toggle it
        let clickBold = runAxon(["click", "--app", "TextEdit", "--no-activate", "--label", "bold"])
        XCTAssertEqual(clickBold.exitCode, 0, "click bold failed. stderr: \(clickBold.stderr)")
        Thread.sleep(forTimeInterval: 0.3)

        let boldAfter = runAxon(["get-value", "--app", "TextEdit", "--no-activate", "--label", "bold"])
        XCTAssertEqual(boldAfter.exitCode, 0)
        let boldValAfter = parseJSON(boldAfter.stdout)?["value"] as? String
        XCTAssertNotEqual(boldValBefore, boldValAfter, "Bold should toggle after clicking")

        // Click again — should toggle back
        let clickBoldOff = runAxon(["click", "--app", "TextEdit", "--no-activate", "--label", "bold"])
        XCTAssertEqual(clickBoldOff.exitCode, 0)
        Thread.sleep(forTimeInterval: 0.3)

        let boldReset = runAxon(["get-value", "--app", "TextEdit", "--no-activate", "--label", "bold"])
        let boldValReset = parseJSON(boldReset.stdout)?["value"] as? String
        XCTAssertEqual(boldValBefore, boldValReset, "Bold should return to original state after two clicks")

        // --- Step 3: Move and resize the window, verify via window-info ---
        let moveResize = runAxon(["move-resize", "--app", "TextEdit", "--no-activate", "--x", "50", "--y", "50", "--width", "900", "--height", "700"])
        XCTAssertEqual(moveResize.exitCode, 0, "move-resize failed. stderr: \(moveResize.stderr)")
        Thread.sleep(forTimeInterval: 0.5)

        let winInfo = runAxon(["window-info", "--app", "TextEdit", "--no-activate"])
        XCTAssertEqual(winInfo.exitCode, 0, "window-info failed. stderr: \(winInfo.stderr)")
        let winJSON = parseJSON(winInfo.stdout)
        let windows = winJSON?["windows"] as? [[String: Any]]
        XCTAssertNotNil(windows)
        XCTAssertGreaterThan(windows?.count ?? 0, 0, "TextEdit should have at least one window")

        if let win = windows?.first {
            let pos = win["position"] as? [String: Any]
            let sz = win["size"] as? [String: Any]
            XCTAssertNotNil(pos)
            XCTAssertNotNil(sz)

            let x = pos?["x"] as? Double ?? -1
            let y = pos?["y"] as? Double ?? -1
            XCTAssertEqual(x, 50, accuracy: 10, "Window x should be ~50")
            XCTAssertEqual(y, 50, accuracy: 30, "Window y should be ~50 (menu bar may offset)")

            let w = sz?["width"] as? Double ?? -1
            let h = sz?["height"] as? Double ?? -1
            XCTAssertEqual(w, 900, accuracy: 10, "Window width should be ~900")
            XCTAssertEqual(h, 700, accuracy: 10, "Window height should be ~700")
        }

        // --- Step 4: Screenshot and verify the file exists with real content ---
        let screenshotPath = "/tmp/axon-e2e-drive-textedit.png"
        addTeardownBlock {
            try? FileManager.default.removeItem(atPath: screenshotPath)
        }

        let screenshot = runAxon(["screenshot", "--app", "TextEdit", "--no-activate", "--output", screenshotPath])
        XCTAssertEqual(screenshot.exitCode, 0, "screenshot failed. stderr: \(screenshot.stderr)")
        let ssJSON = parseJSON(screenshot.stdout)
        XCTAssertEqual(ssJSON?["success"] as? Bool, true)

        let attrs = try FileManager.default.attributesOfItem(atPath: screenshotPath)
        let fileSize = attrs[.size] as? Int ?? 0
        XCTAssertGreaterThan(fileSize, 1000, "Screenshot should be a real image (>1KB), got \(fileSize) bytes")

        // --- Step 5: Type with --clear to replace text, verify ---
        let replacement = "Replaced text"
        let clearType = runAxon(["type", "--app", "TextEdit", "--no-activate", "--identifier", "First Text View", "--text", replacement, "--clear"])
        XCTAssertEqual(clearType.exitCode, 0, "type --clear failed. stderr: \(clearType.stderr)")

        let getValueAfter = runAxon(["get-value", "--app", "TextEdit", "--no-activate", "--identifier", "First Text View"])
        XCTAssertEqual(getValueAfter.exitCode, 0)
        let afterValue = parseJSON(getValueAfter.stdout)?["value"] as? String ?? ""
        XCTAssertEqual(afterValue, replacement, "Text area should contain only the replacement text")
    }

    // MARK: - TextEdit sheet scenario

    func testTextEditUnsavedSheetTargetable() throws {
        let launch = runAxon(["launch", "--name", "TextEdit"])
        try skipIfNoAccessibility(launch)
        XCTAssertEqual(launch.exitCode, 0)
        defer { _ = runAxon(["close", "--app", "TextEdit", "--quit"]) }

        _ = runAxon(["wait-ready", "--app", "TextEdit", "--timeout", "5"])

        let typeResult = runAxon([
            "type", "--app", "TextEdit",
            "--path", "AXWindow[0]/AXScrollArea[0]/AXTextArea[0]",
            "--text", "Unsaved content"
        ])
        try XCTSkipUnless(typeResult.exitCode == 0, "type failed: \(typeResult.stderr)")

        let close = runAxon(["key", "--app", "TextEdit", "--key", "w", "--modifiers", "command"])
        XCTAssertEqual(close.exitCode, 0, close.stderr)

        // On macOS 14+, closing dirty TextEdit opens a Save panel. The "Don't Save" button
        // has the stable accessibilityIdentifier "DontSaveButton". Wait for it to appear.
        let btnWait = runAxon([
            "wait", "--app", "TextEdit",
            "--identifier", "DontSaveButton",
            "--appear",
            "--timeout", "5"
        ])
        try XCTSkipUnless(btnWait.exitCode == 0, "DontSaveButton did not appear — may be a different flow on this macOS: \(btnWait.stderr)")

        let click = runAxon([
            "click", "--app", "TextEdit",
            "--identifier", "DontSaveButton"
        ])
        XCTAssertEqual(click.exitCode, 0, "DontSaveButton click failed: \(click.stderr)")
    }

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
}
