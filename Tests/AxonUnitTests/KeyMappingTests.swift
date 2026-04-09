import XCTest
@testable import AxonLib

final class KeyMappingTests: XCTestCase {

    // MARK: - keyNameToCode

    func testCommonKeysExist() {
        XCTAssertNotNil(keyNameToCode["return"])
        XCTAssertNotNil(keyNameToCode["enter"])
        XCTAssertNotNil(keyNameToCode["tab"])
        XCTAssertNotNil(keyNameToCode["space"])
        XCTAssertNotNil(keyNameToCode["escape"])
        XCTAssertNotNil(keyNameToCode["esc"])
        XCTAssertNotNil(keyNameToCode["delete"])
        XCTAssertNotNil(keyNameToCode["backspace"])
    }

    func testArrowKeysExist() {
        XCTAssertNotNil(keyNameToCode["up"])
        XCTAssertNotNil(keyNameToCode["down"])
        XCTAssertNotNil(keyNameToCode["left"])
        XCTAssertNotNil(keyNameToCode["right"])
    }

    func testFunctionKeysExist() {
        for i in 1...12 {
            XCTAssertNotNil(keyNameToCode["f\(i)"], "f\(i) should exist")
        }
    }

    func testLetterKeysExist() {
        for char in "abcdefghijklmnopqrstuvwxyz" {
            XCTAssertNotNil(keyNameToCode[String(char)], "\(char) should exist")
        }
    }

    func testNumberKeysExist() {
        for char in "0123456789" {
            XCTAssertNotNil(keyNameToCode[String(char)], "\(char) should exist")
        }
    }

    func testNavigationKeysExist() {
        XCTAssertNotNil(keyNameToCode["home"])
        XCTAssertNotNil(keyNameToCode["end"])
        XCTAssertNotNil(keyNameToCode["pageup"])
        XCTAssertNotNil(keyNameToCode["pagedown"])
    }

    func testReturnAndEnterAreSameKeyCode() {
        XCTAssertEqual(keyNameToCode["return"], keyNameToCode["enter"])
    }

    func testEscapeAndEscAreSameKeyCode() {
        XCTAssertEqual(keyNameToCode["escape"], keyNameToCode["esc"])
    }

    func testDeleteAndBackspaceAreSameKeyCode() {
        XCTAssertEqual(keyNameToCode["delete"], keyNameToCode["backspace"])
    }

    func testInvalidKeyReturnsNil() {
        XCTAssertNil(keyNameToCode["nonexistent"])
        XCTAssertNil(keyNameToCode[""])
        XCTAssertNil(keyNameToCode["RETURN"]) // case-sensitive lookup
    }

    // MARK: - parseModifiers

    func testParseModifiersCmd() {
        let flags = parseModifiers("cmd")
        XCTAssertTrue(flags.contains(.maskCommand))
        XCTAssertFalse(flags.contains(.maskShift))
    }

    func testParseModifiersCommand() {
        let flags = parseModifiers("command")
        XCTAssertTrue(flags.contains(.maskCommand))
    }

    func testParseModifiersShift() {
        let flags = parseModifiers("shift")
        XCTAssertTrue(flags.contains(.maskShift))
    }

    func testParseModifiersAlt() {
        let flags = parseModifiers("alt")
        XCTAssertTrue(flags.contains(.maskAlternate))
    }

    func testParseModifiersOption() {
        let flags = parseModifiers("option")
        XCTAssertTrue(flags.contains(.maskAlternate))
    }

    func testParseModifiersCtrl() {
        let flags = parseModifiers("ctrl")
        XCTAssertTrue(flags.contains(.maskControl))
    }

    func testParseModifiersControl() {
        let flags = parseModifiers("control")
        XCTAssertTrue(flags.contains(.maskControl))
    }

    func testParseModifiersCombination() {
        let flags = parseModifiers("cmd+shift")
        XCTAssertTrue(flags.contains(.maskCommand))
        XCTAssertTrue(flags.contains(.maskShift))
        XCTAssertFalse(flags.contains(.maskAlternate))
    }

    func testParseModifiersTriple() {
        let flags = parseModifiers("cmd+shift+alt")
        XCTAssertTrue(flags.contains(.maskCommand))
        XCTAssertTrue(flags.contains(.maskShift))
        XCTAssertTrue(flags.contains(.maskAlternate))
    }

    func testParseModifiersCaseInsensitive() {
        let flags = parseModifiers("CMD+SHIFT")
        XCTAssertTrue(flags.contains(.maskCommand))
        XCTAssertTrue(flags.contains(.maskShift))
    }

    func testParseModifiersEmpty() {
        let flags = parseModifiers("")
        XCTAssertTrue(flags.isEmpty)
    }

    func testParseModifiersUnknown() {
        let flags = parseModifiers("meta")
        XCTAssertTrue(flags.isEmpty)
    }
}
