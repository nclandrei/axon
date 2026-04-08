import XCTest
@testable import AxonLib

final class ScrollDirectionTests: XCTestCase {

    // MARK: - ScrollDirection

    func testScrollDirectionUp() {
        XCTAssertNotNil(ScrollDirection(rawValue: "up"))
        XCTAssertEqual(ScrollDirection(rawValue: "up"), .up)
    }

    func testScrollDirectionDown() {
        XCTAssertNotNil(ScrollDirection(rawValue: "down"))
        XCTAssertEqual(ScrollDirection(rawValue: "down"), .down)
    }

    func testScrollDirectionLeft() {
        XCTAssertNotNil(ScrollDirection(rawValue: "left"))
        XCTAssertEqual(ScrollDirection(rawValue: "left"), .left)
    }

    func testScrollDirectionRight() {
        XCTAssertNotNil(ScrollDirection(rawValue: "right"))
        XCTAssertEqual(ScrollDirection(rawValue: "right"), .right)
    }

    func testScrollDirectionInvalidReturnsNil() {
        XCTAssertNil(ScrollDirection(rawValue: "diagonal"))
        XCTAssertNil(ScrollDirection(rawValue: ""))
        XCTAssertNil(ScrollDirection(rawValue: "UP"))
    }

    func testScrollDirectionRawValues() {
        XCTAssertEqual(ScrollDirection.up.rawValue, "up")
        XCTAssertEqual(ScrollDirection.down.rawValue, "down")
        XCTAssertEqual(ScrollDirection.left.rawValue, "left")
        XCTAssertEqual(ScrollDirection.right.rawValue, "right")
    }

    // MARK: - TypeMethod

    func testTypeMethodDirect() {
        XCTAssertNotNil(TypeMethod(rawValue: "direct"))
        XCTAssertEqual(TypeMethod(rawValue: "direct"), .direct)
    }

    func testTypeMethodKeyboard() {
        XCTAssertNotNil(TypeMethod(rawValue: "keyboard"))
        XCTAssertEqual(TypeMethod(rawValue: "keyboard"), .keyboard)
    }

    func testTypeMethodInvalidReturnsNil() {
        XCTAssertNil(TypeMethod(rawValue: "clipboard"))
        XCTAssertNil(TypeMethod(rawValue: ""))
        XCTAssertNil(TypeMethod(rawValue: "DIRECT"))
    }

    func testTypeMethodRawValues() {
        XCTAssertEqual(TypeMethod.direct.rawValue, "direct")
        XCTAssertEqual(TypeMethod.keyboard.rawValue, "keyboard")
    }
}
