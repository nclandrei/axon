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
}
