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
}
