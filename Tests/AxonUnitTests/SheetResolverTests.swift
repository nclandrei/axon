import XCTest
@testable import AxonLib

final class SheetResolverTests: XCTestCase {

    func testElementSelectorHasSheetCase() {
        let selector: ElementSelector = .sheet(labelFilter: nil)
        switch selector {
        case .sheet: break
        default: XCTFail("Expected .sheet case")
        }
    }

    func testElementSelectorHasAlertCase() {
        let selector: ElementSelector = .alert(labelFilter: nil)
        switch selector {
        case .alert: break
        default: XCTFail("Expected .alert case")
        }
    }

    func testFindElementSheetOnSelfAppReturnsNil() {
        let selfApp = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let found = findElement(root: selfApp, selector: .sheet(labelFilter: nil))
        XCTAssertNil(found)
    }

    func testFindElementAlertOnSelfAppReturnsNil() {
        let selfApp = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let found = findElement(root: selfApp, selector: .alert(labelFilter: nil))
        XCTAssertNil(found)
    }

    // MARK: - resolveElement integration

    // Note: resolveElement exits the process on missing element, so we can't easily
    // unit test the error path. We do verify it accepts the new signature without crashing.

    func testResolveElementSignatureAcceptsSheetFlag() {
        // Compile-time check: the new signature exists.
        let _: (AXUIElement, String?, String?, String?, Bool, Bool, String) -> FoundElement = resolveElement(appElement:identifier:label:path:sheet:alert:appName:)
    }
}
