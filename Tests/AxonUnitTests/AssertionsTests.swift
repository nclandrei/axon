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
}
