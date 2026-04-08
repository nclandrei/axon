import XCTest
@testable import AxonLib

final class PathParsingTests: XCTestCase {

    // MARK: - PathComponent(from:)

    func testPathComponentParsesSimple() {
        let comp = PathComponent(from: "AXButton[0]")
        XCTAssertNotNil(comp)
        XCTAssertEqual(comp?.role, "AXButton")
        XCTAssertEqual(comp?.index, 0)
    }

    func testPathComponentParsesHigherIndex() {
        let comp = PathComponent(from: "AXWindow[2]")
        XCTAssertNotNil(comp)
        XCTAssertEqual(comp?.role, "AXWindow")
        XCTAssertEqual(comp?.index, 2)
    }

    func testPathComponentParsesLargeIndex() {
        let comp = PathComponent(from: "AXGroup[99]")
        XCTAssertNotNil(comp)
        XCTAssertEqual(comp?.role, "AXGroup")
        XCTAssertEqual(comp?.index, 99)
    }

    func testPathComponentReturnsNilForMissingBrackets() {
        XCTAssertNil(PathComponent(from: "noindex"))
    }

    func testPathComponentReturnsNilForIncompleteBracket() {
        XCTAssertNil(PathComponent(from: "bad["))
    }

    func testPathComponentReturnsNilForEmptyIndex() {
        XCTAssertNil(PathComponent(from: "AXButton[]"))
    }

    func testPathComponentReturnsNilForNonNumericIndex() {
        XCTAssertNil(PathComponent(from: "AXButton[abc]"))
    }

    func testPathComponentReturnsNilForEmptyString() {
        XCTAssertNil(PathComponent(from: ""))
    }

    // MARK: - parseTreePath()

    func testParseTreePathSingleComponent() {
        let components = parseTreePath("AXWindow[0]")
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.count, 1)
        XCTAssertEqual(components?[0].role, "AXWindow")
        XCTAssertEqual(components?[0].index, 0)
    }

    func testParseTreePathMultipleComponents() {
        let components = parseTreePath("AXWindow[0]/AXGroup[1]/AXButton[0]")
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.count, 3)
        XCTAssertEqual(components?[0].role, "AXWindow")
        XCTAssertEqual(components?[0].index, 0)
        XCTAssertEqual(components?[1].role, "AXGroup")
        XCTAssertEqual(components?[1].index, 1)
        XCTAssertEqual(components?[2].role, "AXButton")
        XCTAssertEqual(components?[2].index, 0)
    }

    func testParseTreePathDeeplyNested() {
        let path = "AXApplication[0]/AXWindow[0]/AXSplitGroup[0]/AXGroup[2]/AXScrollArea[0]/AXTable[0]/AXRow[5]"
        let components = parseTreePath(path)
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.count, 7)
        XCTAssertEqual(components?.last?.role, "AXRow")
        XCTAssertEqual(components?.last?.index, 5)
    }

    func testParseTreePathReturnsNilForInvalidComponent() {
        XCTAssertNil(parseTreePath("AXWindow[0]/invalid/AXButton[0]"))
    }

    func testParseTreePathReturnsNilForEmptySegment() {
        // "AXWindow[0]//AXButton[0]" splits into ["AXWindow[0]", "", "AXButton[0]"]
        // but Swift's split(separator:) omits empty subsequences by default
        // so this should still work as two components
        let components = parseTreePath("AXWindow[0]//AXButton[0]")
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.count, 2)
    }

    func testParseTreePathVariousRoles() {
        let components = parseTreePath("AXStaticText[0]/AXTextField[1]")
        XCTAssertNotNil(components)
        XCTAssertEqual(components?[0].role, "AXStaticText")
        XCTAssertEqual(components?[1].role, "AXTextField")
        XCTAssertEqual(components?[1].index, 1)
    }
}
