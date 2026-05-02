import XCTest
@testable import AxonLib

final class RouterClassifyTests: XCTestCase {

    func testVMRoutableCommands() {
        let routable: [String] = [
            "list", "launch", "tree", "click", "double-click", "right-click",
            "hover", "drag", "type", "key", "scroll", "screenshot", "activate",
            "close", "wait", "get-value", "focused", "window-info", "menu",
            "set-value", "move-resize", "clipboard", "wait-ready", "wait-for-value",
            "assert", "exists",
        ]
        for cmd in routable {
            XCTAssertEqual(classifyCommand(cmd), CommandClass.vmRoutable, "Expected \(cmd) to be vmRoutable")
        }
    }

    func testAlwaysLocalCommands() {
        let local: [String] = ["vm-bake", "vm-acquire", "vm-release", "vm-list", "vm-sync", "doctor"]
        for cmd in local {
            XCTAssertEqual(classifyCommand(cmd), CommandClass.alwaysLocal, "Expected \(cmd) to be alwaysLocal")
        }
    }

    func testUnknownCommandIsAlwaysLocal() {
        // Unknown commands fall through to existing dispatch, which prints help/error locally.
        XCTAssertEqual(classifyCommand("nope-not-real"), CommandClass.alwaysLocal)
    }
}
