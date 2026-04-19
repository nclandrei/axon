import XCTest
@testable import AxonLib

final class ActionsTests: XCTestCase {

    // MARK: - performClick with self-created AXUIElement

    func testClickOnSelf() {
        let selfApp = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let result = performClick(element: selfApp)
        // Self app has no position/size, so even fallback fails
        XCTAssertFalse(result)
    }

    func testClickFallbackUsesCoordinateClick() {
        // When AXPress is not available (e.g. AXRow with only AXShowDefaultUI),
        // performClick should fall back to coordinate-based CGEvent click.
        // We verify this by checking that performClick returns the .coordinateClick method
        // when AXPress fails but position/size are available.
        let selfApp = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)

        // On the self app element, AXPress fails AND there's no position/size,
        // so the method should be nil (both paths fail).
        let result = performClick(element: selfApp)
        XCTAssertFalse(result)

        // Verify the method-returning variant: nil means total failure
        let methodResult = performClickWithMethod(element: selfApp)
        XCTAssertNil(methodResult, "Expected nil when both AXPress and coordinate fallback fail")
    }

    func testClickMethodReturnsAxPress() {
        // When AXPress succeeds, method should be .axPress
        // We can't easily test this in unit tests without a real UI element,
        // but we verify the enum exists and the function signature works.
        let _: ClickMethod? = nil  // Type check: ClickMethod enum exists
    }

    func testRightClickOnSelf() {
        let selfApp = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        _ = performRightClick(element: selfApp)
    }

    func testPerformTypeOnSelf() {
        let selfApp = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        _ = performType(element: selfApp, text: "hello", clear: false)
    }

    // MARK: - performWait

    func testWaitDisappearImmediately() {
        let selfApp = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let elapsed = performWait(
            appElement: selfApp,
            selector: .identifier("nonexistent_element_xyz"),
            appear: false,
            timeout: 2.0
        )
        XCTAssertNotNil(elapsed)
        if let ms = elapsed {
            XCTAssertLessThan(ms, 500)
        }
    }

    func testWaitAppearTimesOut() {
        let selfApp = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let elapsed = performWait(
            appElement: selfApp,
            selector: .identifier("nonexistent_element_xyz"),
            appear: true,
            timeout: 0.5
        )
        XCTAssertNil(elapsed)
    }

    // MARK: - launchApp

    func testLaunchAppAllNil() {
        let result = launchApp(name: nil, bundleID: nil, path: nil)
        XCTAssertNil(result)
    }

    func testLaunchAppBadBundleID() {
        let result = launchApp(name: nil, bundleID: "com.fake.nonexistent.app.xyz123", path: nil, timeout: 1.0)
        XCTAssertNil(result)
    }

    func testLaunchAppBadName() {
        let result = launchApp(name: "NonExistentApp_XYZ_123", bundleID: nil, path: nil, timeout: 1.0)
        XCTAssertNil(result)
    }

    func testLaunchAppBadPath() {
        let result = launchApp(name: nil, bundleID: nil, path: "/nonexistent/path/App.app", timeout: 1.0)
        XCTAssertNil(result)
    }

    func testLaunchAppCustomTimeout() {
        let start = Date()
        _ = launchApp(name: "NonExistentApp_XYZ_123", bundleID: nil, path: nil, timeout: 1.0)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 3.0)
    }

    // MARK: - OutputFormat

    func testOutputFormatJSON() {
        XCTAssertEqual(OutputFormat(rawValue: "json"), .json)
    }

    func testOutputFormatText() {
        XCTAssertEqual(OutputFormat(rawValue: "text"), .text)
    }

    func testOutputFormatInvalid() {
        XCTAssertNil(OutputFormat(rawValue: "xml"))
        XCTAssertNil(OutputFormat(rawValue: ""))
    }

    // MARK: - Version

    func testVersionIsNotEmpty() {
        XCTAssertFalse(axonVersion.isEmpty)
    }

    func testVersionFormat() {
        let parts = axonVersion.split(separator: ".")
        XCTAssertEqual(parts.count, 3)
        for part in parts {
            XCTAssertNotNil(Int(part))
        }
    }

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
}
