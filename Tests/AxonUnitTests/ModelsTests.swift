import XCTest
@testable import AxonLib

final class ModelsTests: XCTestCase {

    // MARK: - jsonEncoder configuration

    func testJsonEncoderUsesPrettyPrintedAndSortedKeys() {
        let output = ScrollOutput(success: true)
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!

        // prettyPrinted => contains newlines
        XCTAssertTrue(json.contains("\n"))
        // sortedKeys => keys appear in alphabetical order (only one key here, so test with multi-key struct)
        let typeOutput = TypeOutput(success: true, method: "direct")
        let typeData = try! jsonEncoder.encode(typeOutput)
        let typeJson = String(data: typeData, encoding: .utf8)!
        let methodIdx = typeJson.range(of: "\"method\"")!.lowerBound
        let successIdx = typeJson.range(of: "\"success\"")!.lowerBound
        XCTAssertTrue(methodIdx < successIdx, "Keys should be sorted: method before success")
    }

    // MARK: - AXPoint

    func testAXPointEncoding() {
        let point = AXPoint(x: 100.5, y: 200.0)
        let data = try! jsonEncoder.encode(point)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"x\""))
        XCTAssertTrue(json.contains("100.5"))
        XCTAssertTrue(json.contains("\"y\""))
        XCTAssertTrue(json.contains("200"))
    }

    func testAXPointRoundTrip() {
        let point = AXPoint(x: 42.5, y: 99.0)
        let data = try! jsonEncoder.encode(point)
        let decoded = try! JSONDecoder().decode(AXPoint.self, from: data)
        XCTAssertEqual(decoded.x, 42.5)
        XCTAssertEqual(decoded.y, 99.0)
    }

    // MARK: - AXSize

    func testAXSizeEncoding() {
        let size = AXSize(width: 800.0, height: 600.0)
        let data = try! jsonEncoder.encode(size)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"width\""))
        XCTAssertTrue(json.contains("800"))
        XCTAssertTrue(json.contains("\"height\""))
        XCTAssertTrue(json.contains("600"))
    }

    func testAXSizeRoundTrip() {
        let size = AXSize(width: 1920.0, height: 1080.0)
        let data = try! jsonEncoder.encode(size)
        let decoded = try! JSONDecoder().decode(AXSize.self, from: data)
        XCTAssertEqual(decoded.width, 1920.0)
        XCTAssertEqual(decoded.height, 1080.0)
    }

    // MARK: - AXNode

    func testAXNodeEncodingFull() {
        let node = AXNode(
            role: "AXButton",
            subrole: "AXCloseButton",
            title: "Close",
            identifier: "closeBtn",
            label: "Close Window",
            value: "1",
            enabled: true,
            focused: false,
            position: AXPoint(x: 10, y: 20),
            size: AXSize(width: 30, height: 40),
            path: "AXWindow[0]/AXButton[0]",
            children: nil
        )
        let data = try! jsonEncoder.encode(node)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("\"role\" : \"AXButton\""))
        XCTAssertTrue(json.contains("\"subrole\" : \"AXCloseButton\""))
        XCTAssertTrue(json.contains("\"title\" : \"Close\""))
        XCTAssertTrue(json.contains("\"identifier\" : \"closeBtn\""))
        XCTAssertTrue(json.contains("\"label\" : \"Close Window\""))
        XCTAssertTrue(json.contains("\"value\" : \"1\""))
        XCTAssertTrue(json.contains("\"enabled\" : true"))
        XCTAssertTrue(json.contains("\"focused\" : false"))
        XCTAssertTrue(json.contains("\"path\" : \"AXWindow[0]\\/AXButton[0]\""))
    }

    func testAXNodeRoundTrip() {
        let node = AXNode(
            role: "AXButton",
            subrole: nil,
            title: "OK",
            identifier: nil,
            label: nil,
            value: nil,
            enabled: true,
            focused: false,
            position: AXPoint(x: 10, y: 20),
            size: AXSize(width: 100, height: 50),
            path: "AXButton[0]",
            children: nil
        )
        let data = try! jsonEncoder.encode(node)
        let decoded = try! JSONDecoder().decode(AXNode.self, from: data)
        XCTAssertEqual(decoded.role, "AXButton")
        XCTAssertNil(decoded.subrole)
        XCTAssertEqual(decoded.title, "OK")
        XCTAssertEqual(decoded.path, "AXButton[0]")
        XCTAssertNil(decoded.children)
    }

    func testAXNodeWithChildren() {
        let child = AXNode(
            role: "AXStaticText", subrole: nil, title: "Hello", identifier: nil,
            label: nil, value: nil, enabled: true, focused: false,
            position: nil, size: nil, path: "AXWindow[0]/AXStaticText[0]", children: nil
        )
        let parent = AXNode(
            role: "AXWindow", subrole: nil, title: "Main", identifier: nil,
            label: nil, value: nil, enabled: true, focused: true,
            position: AXPoint(x: 0, y: 0), size: AXSize(width: 800, height: 600),
            path: "AXWindow[0]", children: [child]
        )
        let data = try! jsonEncoder.encode(parent)
        let decoded = try! JSONDecoder().decode(AXNode.self, from: data)
        XCTAssertEqual(decoded.children?.count, 1)
        XCTAssertEqual(decoded.children?.first?.role, "AXStaticText")
    }

    // MARK: - CompactAXNode

    func testCompactAXNodeOmitsNilFields() {
        let node = CompactAXNode(
            role: "AXButton",
            subrole: nil,
            title: "OK",
            identifier: nil,
            label: nil,
            value: nil,
            enabled: true,
            focused: nil,
            path: "AXButton[0]",
            children: nil
        )
        let data = try! jsonEncoder.encode(node)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("\"role\""))
        XCTAssertTrue(json.contains("\"title\""))
        XCTAssertTrue(json.contains("\"enabled\""))
        XCTAssertTrue(json.contains("\"path\""))
        // nil fields should be absent
        XCTAssertFalse(json.contains("\"subrole\""))
        XCTAssertFalse(json.contains("\"identifier\""))
        XCTAssertFalse(json.contains("\"label\""))
        XCTAssertFalse(json.contains("\"value\""))
        XCTAssertFalse(json.contains("\"focused\""))
        // nil children should be absent
        XCTAssertFalse(json.contains("\"children\""))
    }

    func testCompactAXNodeOmitsEmptyChildren() {
        let node = CompactAXNode(
            role: "AXGroup",
            subrole: nil,
            title: nil,
            identifier: nil,
            label: nil,
            value: nil,
            enabled: nil,
            focused: nil,
            path: "AXGroup[0]",
            children: []
        )
        let data = try! jsonEncoder.encode(node)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertFalse(json.contains("\"children\""))
    }

    func testCompactAXNodeIncludesNonEmptyChildren() {
        let child = CompactAXNode(
            role: "AXButton", subrole: nil, title: "Click", identifier: nil,
            label: nil, value: nil, enabled: nil, focused: nil,
            path: "AXGroup[0]/AXButton[0]", children: nil
        )
        let node = CompactAXNode(
            role: "AXGroup", subrole: nil, title: nil, identifier: nil,
            label: nil, value: nil, enabled: nil, focused: nil,
            path: "AXGroup[0]", children: [child]
        )
        let data = try! jsonEncoder.encode(node)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"children\""))
    }

    func testAXNodeCompactedMethod() {
        let node = AXNode(
            role: "AXButton", subrole: nil, title: "OK", identifier: nil,
            label: nil, value: nil, enabled: true, focused: false,
            position: AXPoint(x: 10, y: 20), size: AXSize(width: 100, height: 50),
            path: "AXButton[0]", children: nil
        )
        let compact = node.compacted()
        XCTAssertEqual(compact.role, "AXButton")
        XCTAssertEqual(compact.title, "OK")
        XCTAssertEqual(compact.path, "AXButton[0]")
        XCTAssertNil(compact.subrole)
    }

    // MARK: - ListOutput

    func testListOutputEncoding() {
        let output = ListOutput(apps: [
            AppInfo(name: "Finder", bundleID: "com.apple.finder", pid: 123),
            AppInfo(name: "Safari", bundleID: "com.apple.Safari", pid: 456),
        ])
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"Finder\""))
        XCTAssertTrue(json.contains("\"Safari\""))
        XCTAssertTrue(json.contains("\"com.apple.finder\""))
    }

    func testListOutputRoundTrip() {
        let output = ListOutput(apps: [
            AppInfo(name: "Finder", bundleID: "com.apple.finder", pid: 123),
        ])
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(ListOutput.self, from: data)
        XCTAssertEqual(decoded.apps.count, 1)
        XCTAssertEqual(decoded.apps[0].name, "Finder")
        XCTAssertEqual(decoded.apps[0].bundleID, "com.apple.finder")
        XCTAssertEqual(decoded.apps[0].pid, 123)
    }

    // MARK: - TreeOutput

    func testTreeOutputEncoding() {
        let tree = AXNode(
            role: "AXApplication", subrole: nil, title: "Finder", identifier: nil,
            label: nil, value: nil, enabled: nil, focused: nil,
            position: nil, size: nil, path: "", children: nil
        )
        let output = TreeOutput(app: "Finder", pid: 123, tree: tree)
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"app\" : \"Finder\""))
        XCTAssertTrue(json.contains("\"pid\" : 123"))
    }

    // MARK: - CompactTreeOutput

    func testCompactTreeOutputEncoding() {
        let tree = CompactAXNode(
            role: "AXApplication", subrole: nil, title: "Finder", identifier: nil,
            label: nil, value: nil, enabled: nil, focused: nil,
            path: "", children: nil
        )
        let output = CompactTreeOutput(app: "Finder", pid: 123, tree: tree)
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"app\" : \"Finder\""))
        XCTAssertTrue(json.contains("\"pid\" : 123"))
    }

    // MARK: - ClickOutput

    func testClickOutputEncoding() {
        let output = ClickOutput(
            success: true,
            element: ElementInfo(role: "AXButton", title: "OK", identifier: "okBtn")
        )
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"success\" : true"))
        XCTAssertTrue(json.contains("\"role\" : \"AXButton\""))
    }

    func testClickOutputRoundTrip() {
        let output = ClickOutput(
            success: false,
            element: ElementInfo(role: "AXLink", title: nil, identifier: "link1")
        )
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(ClickOutput.self, from: data)
        XCTAssertFalse(decoded.success)
        XCTAssertEqual(decoded.element.role, "AXLink")
        XCTAssertNil(decoded.element.title)
        XCTAssertEqual(decoded.element.identifier, "link1")
    }

    // MARK: - DoubleClickOutput

    func testDoubleClickOutputEncoding() {
        let output = DoubleClickOutput(
            success: true,
            element: ElementInfo(role: "AXStaticText", title: "Documents", identifier: nil)
        )
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"success\" : true"))
        XCTAssertTrue(json.contains("\"role\" : \"AXStaticText\""))
    }

    func testDoubleClickOutputRoundTrip() {
        let output = DoubleClickOutput(
            success: true,
            element: ElementInfo(role: "AXCell", title: "file.txt", identifier: nil)
        )
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(DoubleClickOutput.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.element.role, "AXCell")
        XCTAssertEqual(decoded.element.title, "file.txt")
    }

    // MARK: - RightClickOutput

    func testRightClickOutputEncoding() {
        let output = RightClickOutput(
            success: true,
            element: ElementInfo(role: "AXRow", title: "Documents", identifier: nil)
        )
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"success\" : true"))
        XCTAssertTrue(json.contains("\"role\" : \"AXRow\""))
        XCTAssertTrue(json.contains("\"title\" : \"Documents\""))
    }

    func testRightClickOutputRoundTrip() {
        let output = RightClickOutput(
            success: true,
            element: ElementInfo(role: "AXCell", title: nil, identifier: "cell1")
        )
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(RightClickOutput.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.element.role, "AXCell")
        XCTAssertNil(decoded.element.title)
        XCTAssertEqual(decoded.element.identifier, "cell1")
    }

    // MARK: - ClickOutput with modifiers

    func testClickOutputWithModifiersEncoding() {
        let output = ClickOutput(
            success: true,
            element: ElementInfo(role: "AXButton", title: "OK", identifier: "okBtn"),
            modifiers: ["shift", "cmd"]
        )
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"modifiers\""))
        XCTAssertTrue(json.contains("shift"))
        XCTAssertTrue(json.contains("cmd"))
    }

    func testClickOutputWithoutModifiersEncoding() {
        let output = ClickOutput(
            success: true,
            element: ElementInfo(role: "AXButton", title: "OK", identifier: "okBtn")
        )
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(ClickOutput.self, from: data)
        XCTAssertNil(decoded.modifiers)
    }

    // MARK: - DoubleClickOutput with modifiers

    func testDoubleClickOutputWithModifiersEncoding() {
        let output = DoubleClickOutput(
            success: true,
            element: ElementInfo(role: "AXStaticText", title: "Documents", identifier: nil),
            modifiers: ["alt"]
        )
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"modifiers\""))
        XCTAssertTrue(json.contains("alt"))
    }

    func testDoubleClickOutputWithoutModifiersEncoding() {
        let output = DoubleClickOutput(
            success: true,
            element: ElementInfo(role: "AXStaticText", title: "Documents", identifier: nil)
        )
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(DoubleClickOutput.self, from: data)
        XCTAssertNil(decoded.modifiers)
    }

    // MARK: - RightClickOutput with modifiers

    func testRightClickOutputWithModifiersEncoding() {
        let output = RightClickOutput(
            success: true,
            element: ElementInfo(role: "AXRow", title: "Documents", identifier: nil),
            modifiers: ["ctrl", "shift"]
        )
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"modifiers\""))
        XCTAssertTrue(json.contains("ctrl"))
        XCTAssertTrue(json.contains("shift"))
    }

    func testRightClickOutputWithoutModifiersEncoding() {
        let output = RightClickOutput(
            success: true,
            element: ElementInfo(role: "AXRow", title: "Documents", identifier: nil)
        )
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(RightClickOutput.self, from: data)
        XCTAssertNil(decoded.modifiers)
    }

    // MARK: - TypeOutput

    func testTypeOutputEncoding() {
        let output = TypeOutput(success: true, method: "direct")
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"method\" : \"direct\""))
        XCTAssertTrue(json.contains("\"success\" : true"))
    }

    func testTypeOutputRoundTrip() {
        let output = TypeOutput(success: true, method: "keyboard")
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(TypeOutput.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.method, "keyboard")
    }

    // MARK: - ScrollOutput

    func testScrollOutputEncoding() {
        let output = ScrollOutput(success: true)
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(ScrollOutput.self, from: data)
        XCTAssertTrue(decoded.success)
    }

    // MARK: - KeyOutput

    func testKeyOutputEncoding() {
        let output = KeyOutput(success: true, key: "c", modifiers: ["cmd"])
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"success\" : true"))
        XCTAssertTrue(json.contains("\"key\" : \"c\""))
        XCTAssertTrue(json.contains("\"cmd\""))
    }

    func testKeyOutputRoundTrip() {
        let output = KeyOutput(success: true, key: "return", modifiers: nil)
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(KeyOutput.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.key, "return")
        XCTAssertNil(decoded.modifiers)
    }

    func testKeyOutputWithMultipleModifiers() {
        let output = KeyOutput(success: true, key: "z", modifiers: ["cmd", "shift"])
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(KeyOutput.self, from: data)
        XCTAssertEqual(decoded.key, "z")
        XCTAssertEqual(decoded.modifiers, ["cmd", "shift"])
    }

    // MARK: - HoverOutput

    func testHoverOutputEncoding() {
        let output = HoverOutput(
            success: true,
            element: ElementInfo(role: "AXButton", title: "Submit", identifier: "btn1"),
            position: AXPoint(x: 500.0, y: 300.0)
        )
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"success\" : true"))
        XCTAssertTrue(json.contains("\"Submit\""))
        XCTAssertTrue(json.contains("500"))
        XCTAssertTrue(json.contains("300"))
    }

    func testHoverOutputRoundTrip() {
        let output = HoverOutput(
            success: true,
            element: ElementInfo(role: "AXLink", title: "Click me", identifier: nil),
            position: AXPoint(x: 123.5, y: 456.0)
        )
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(HoverOutput.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.element.role, "AXLink")
        XCTAssertEqual(decoded.element.title, "Click me")
        XCTAssertEqual(decoded.position.x, 123.5)
        XCTAssertEqual(decoded.position.y, 456.0)
    }

    // MARK: - ScreenshotOutput

    func testScreenshotOutputEncoding() {
        let output = ScreenshotOutput(success: true, path: "/tmp/screenshot.png", width: 1920, height: 1080)
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        // JSON encodes forward slashes with escaping: /tmp becomes \/tmp
        XCTAssertTrue(json.contains("screenshot.png"))
        XCTAssertTrue(json.contains("1920"))
        XCTAssertTrue(json.contains("1080"))
    }

    func testScreenshotOutputRoundTrip() {
        let output = ScreenshotOutput(success: true, path: "/tmp/shot.png", width: 800, height: 600)
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(ScreenshotOutput.self, from: data)
        XCTAssertEqual(decoded.path, "/tmp/shot.png")
        XCTAssertEqual(decoded.width, 800)
        XCTAssertEqual(decoded.height, 600)
    }

    // MARK: - ActivateOutput

    func testActivateOutputEncoding() {
        let output = ActivateOutput(success: true)
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(ActivateOutput.self, from: data)
        XCTAssertTrue(decoded.success)
    }

    // MARK: - LaunchOutput

    func testLaunchOutputEncoding() {
        let output = LaunchOutput(success: true, name: "Safari", bundleID: "com.apple.Safari", pid: 789)
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"Safari\""))
        XCTAssertTrue(json.contains("\"com.apple.Safari\""))
        XCTAssertTrue(json.contains("789"))
    }

    func testLaunchOutputRoundTrip() {
        let output = LaunchOutput(success: true, name: "Notes", bundleID: nil, pid: 100)
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(LaunchOutput.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.name, "Notes")
        XCTAssertNil(decoded.bundleID)
        XCTAssertEqual(decoded.pid, 100)
    }

    // MARK: - CloseOutput

    func testCloseOutputEncoding() {
        let output = CloseOutput(success: true, action: "quit")
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"action\" : \"quit\""))
    }

    func testCloseOutputRoundTrip() {
        let output = CloseOutput(success: false, action: "close_window")
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(CloseOutput.self, from: data)
        XCTAssertFalse(decoded.success)
        XCTAssertEqual(decoded.action, "close_window")
    }

    // MARK: - WaitOutput

    func testWaitOutputEncoding() {
        let output = WaitOutput(success: true, elapsed_ms: 1500)
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("1500"))
    }

    func testWaitOutputRoundTrip() {
        let output = WaitOutput(success: false, elapsed_ms: 5000)
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(WaitOutput.self, from: data)
        XCTAssertFalse(decoded.success)
        XCTAssertEqual(decoded.elapsed_ms, 5000)
    }

    // MARK: - ElementInfo

    func testElementInfoEncoding() {
        let info = ElementInfo(role: "AXButton", title: "Submit", identifier: "submitBtn")
        let data = try! jsonEncoder.encode(info)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"AXButton\""))
        XCTAssertTrue(json.contains("\"Submit\""))
        XCTAssertTrue(json.contains("\"submitBtn\""))
    }

    func testElementInfoWithNils() {
        let info = ElementInfo(role: nil, title: nil, identifier: nil)
        let data = try! jsonEncoder.encode(info)
        let decoded = try! JSONDecoder().decode(ElementInfo.self, from: data)
        XCTAssertNil(decoded.role)
        XCTAssertNil(decoded.title)
        XCTAssertNil(decoded.identifier)
    }

    // MARK: - ErrorOutput

    func testErrorOutputEncoding() {
        let err = ErrorOutput(error: "not_found", message: "Element not found", available: nil)
        let data = try! jsonEncoder.encode(err)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"not_found\""))
        XCTAssertTrue(json.contains("\"Element not found\""))
    }

    func testErrorOutputWithAvailable() {
        let err = ErrorOutput(error: "not_found", message: "Not found", available: ["btn1", "btn2"])
        let data = try! jsonEncoder.encode(err)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"btn1\""))
        XCTAssertTrue(json.contains("\"btn2\""))
        XCTAssertTrue(json.contains("\"available\""))
    }

    func testErrorOutputWithoutAvailable() {
        let err = ErrorOutput(error: "timeout", message: "Timed out", available: nil)
        let data = try! jsonEncoder.encode(err)
        let decoded = try! JSONDecoder().decode(ErrorOutput.self, from: data)
        XCTAssertEqual(decoded.error, "timeout")
        XCTAssertEqual(decoded.message, "Timed out")
        XCTAssertNil(decoded.available)
    }

    func testErrorOutputRoundTrip() {
        let err = ErrorOutput(error: "perm", message: "No permission", available: ["a", "b"])
        let data = try! jsonEncoder.encode(err)
        let decoded = try! JSONDecoder().decode(ErrorOutput.self, from: data)
        XCTAssertEqual(decoded.error, "perm")
        XCTAssertEqual(decoded.message, "No permission")
        XCTAssertEqual(decoded.available, ["a", "b"])
    }

    // MARK: - AppInfo

    func testAppInfoEncodingWithBundleID() {
        let info = AppInfo(name: "Finder", bundleID: "com.apple.finder", pid: 1)
        let data = try! jsonEncoder.encode(info)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"Finder\""))
        XCTAssertTrue(json.contains("\"com.apple.finder\""))
    }

    // MARK: - GetValueOutput

    func testGetValueOutputEncoding() {
        let output = GetValueOutput(
            success: true, role: "AXTextField", value: "hello", title: "Name",
            selectedText: "hel", enabled: true, focused: true, selected: nil, description: "Name field"
        )
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"success\" : true"))
        XCTAssertTrue(json.contains("\"role\" : \"AXTextField\""))
        XCTAssertTrue(json.contains("\"value\" : \"hello\""))
        XCTAssertTrue(json.contains("\"selectedText\" : \"hel\""))
    }

    func testGetValueOutputRoundTrip() {
        let output = GetValueOutput(
            success: true, role: "AXCheckBox", value: "1", title: "Accept",
            selectedText: nil, enabled: true, focused: false, selected: true, description: nil
        )
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(GetValueOutput.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.role, "AXCheckBox")
        XCTAssertEqual(decoded.value, "1")
        XCTAssertEqual(decoded.title, "Accept")
        XCTAssertNil(decoded.selectedText)
        XCTAssertEqual(decoded.selected, true)
        XCTAssertNil(decoded.description)
    }

    func testGetValueOutputWithNils() {
        let output = GetValueOutput(
            success: true, role: nil, value: nil, title: nil,
            selectedText: nil, enabled: nil, focused: nil, selected: nil, description: nil
        )
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(GetValueOutput.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertNil(decoded.role)
        XCTAssertNil(decoded.value)
        XCTAssertNil(decoded.title)
        XCTAssertNil(decoded.selectedText)
        XCTAssertNil(decoded.enabled)
        XCTAssertNil(decoded.focused)
        XCTAssertNil(decoded.selected)
        XCTAssertNil(decoded.description)
    }

    // MARK: - FocusedOutput

    func testFocusedOutputEncoding() {
        let output = FocusedOutput(
            success: true,
            element: ElementInfo(role: "AXTextArea", title: nil, identifier: "editor"),
            value: "some text",
            path: "AXWindow[0]/AXScrollArea[0]/AXTextArea[0]"
        )
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"success\" : true"))
        XCTAssertTrue(json.contains("\"editor\""))
        XCTAssertTrue(json.contains("\"some text\""))
    }

    func testFocusedOutputRoundTrip() {
        let output = FocusedOutput(
            success: true,
            element: ElementInfo(role: "AXTextField", title: "Search", identifier: nil),
            value: "query",
            path: "AXWindow[0]/AXTextField[0]"
        )
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(FocusedOutput.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.element?.role, "AXTextField")
        XCTAssertEqual(decoded.element?.title, "Search")
        XCTAssertEqual(decoded.value, "query")
        XCTAssertEqual(decoded.path, "AXWindow[0]/AXTextField[0]")
    }

    func testFocusedOutputNoFocusedElement() {
        let output = FocusedOutput(success: true, element: nil, value: nil, path: nil)
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(FocusedOutput.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertNil(decoded.element)
        XCTAssertNil(decoded.value)
        XCTAssertNil(decoded.path)
    }

    // MARK: - WindowInfo

    func testWindowInfoEncodingAllFields() {
        let info = WindowInfo(
            title: "Main Window",
            position: AXPoint(x: 100, y: 200),
            size: AXSize(width: 800, height: 600),
            main: true,
            minimized: false,
            fullScreen: false
        )
        let data = try! jsonEncoder.encode(info)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"Main Window\""))
        XCTAssertTrue(json.contains("\"main\" : true"))
        XCTAssertTrue(json.contains("\"minimized\" : false"))
        XCTAssertTrue(json.contains("\"fullScreen\" : false"))
    }

    func testWindowInfoWithNils() {
        let info = WindowInfo(
            title: nil, position: nil, size: nil,
            main: nil, minimized: nil, fullScreen: nil
        )
        let data = try! jsonEncoder.encode(info)
        let decoded = try! JSONDecoder().decode(WindowInfo.self, from: data)
        XCTAssertNil(decoded.title)
        XCTAssertNil(decoded.position)
        XCTAssertNil(decoded.size)
        XCTAssertNil(decoded.main)
        XCTAssertNil(decoded.minimized)
        XCTAssertNil(decoded.fullScreen)
    }

    // MARK: - WindowInfoOutput

    func testWindowInfoOutputEncoding() {
        let output = WindowInfoOutput(success: true, windows: [
            WindowInfo(title: "Win1", position: AXPoint(x: 0, y: 0), size: AXSize(width: 800, height: 600), main: true, minimized: false, fullScreen: false),
            WindowInfo(title: "Win2", position: AXPoint(x: 100, y: 100), size: AXSize(width: 400, height: 300), main: false, minimized: true, fullScreen: false),
        ])
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"Win1\""))
        XCTAssertTrue(json.contains("\"Win2\""))
    }

    func testWindowInfoOutputRoundTrip() {
        let output = WindowInfoOutput(success: true, windows: [
            WindowInfo(title: "Test", position: AXPoint(x: 50, y: 50), size: AXSize(width: 640, height: 480), main: true, minimized: false, fullScreen: false),
        ])
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(WindowInfoOutput.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.windows.count, 1)
        XCTAssertEqual(decoded.windows[0].title, "Test")
        XCTAssertEqual(decoded.windows[0].position?.x, 50)
        XCTAssertEqual(decoded.windows[0].size?.width, 640)
        XCTAssertEqual(decoded.windows[0].main, true)
    }

    func testWindowInfoOutputEmptyWindows() {
        let output = WindowInfoOutput(success: true, windows: [])
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(WindowInfoOutput.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertTrue(decoded.windows.isEmpty)
    }

    // MARK: - MenuOutput

    func testMenuOutputEncoding() {
        let output = MenuOutput(
            success: true,
            menuItem: ElementInfo(role: "AXMenuItem", title: "Save", identifier: nil)
        )
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"success\" : true"))
        XCTAssertTrue(json.contains("\"Save\""))
    }

    func testMenuOutputRoundTrip() {
        let output = MenuOutput(
            success: true,
            menuItem: ElementInfo(role: "AXMenuItem", title: "Quit", identifier: "quitItem")
        )
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(MenuOutput.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.menuItem?.role, "AXMenuItem")
        XCTAssertEqual(decoded.menuItem?.title, "Quit")
        XCTAssertEqual(decoded.menuItem?.identifier, "quitItem")
    }

    func testMenuOutputWithNilItem() {
        let output = MenuOutput(success: false, menuItem: nil)
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(MenuOutput.self, from: data)
        XCTAssertFalse(decoded.success)
        XCTAssertNil(decoded.menuItem)
    }

    // MARK: - MenuListOutput

    func testMenuListOutputEncoding() {
        let output = MenuListOutput(success: true, items: ["Apple", "File", "Edit", "View"])
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"File\""))
        XCTAssertTrue(json.contains("\"Edit\""))
    }

    func testMenuListOutputRoundTrip() {
        let output = MenuListOutput(success: true, items: ["File", "Edit"])
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(MenuListOutput.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.items, ["File", "Edit"])
    }

    func testMenuListOutputEmpty() {
        let output = MenuListOutput(success: true, items: [])
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(MenuListOutput.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertTrue(decoded.items.isEmpty)
    }

    // MARK: - AppInfo (continued)

    func testAppInfoEncodingWithNilBundleID() {
        let info = AppInfo(name: "MyApp", bundleID: nil, pid: 99)
        let data = try! jsonEncoder.encode(info)
        let decoded = try! JSONDecoder().decode(AppInfo.self, from: data)
        XCTAssertEqual(decoded.name, "MyApp")
        XCTAssertNil(decoded.bundleID)
        XCTAssertEqual(decoded.pid, 99)
    }

    // MARK: - MoveResizeOutput

    func testMoveResizeOutputEncoding() {
        let output = MoveResizeOutput(success: true, position: AXPoint(x: 100, y: 200), size: AXSize(width: 800, height: 600))
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"success\" : true"))
        XCTAssertTrue(json.contains("\"x\" : 100"))
        XCTAssertTrue(json.contains("\"y\" : 200"))
        XCTAssertTrue(json.contains("\"width\" : 800"))
        XCTAssertTrue(json.contains("\"height\" : 600"))
    }

    func testMoveResizeOutputRoundTrip() {
        let output = MoveResizeOutput(success: true, position: AXPoint(x: 50, y: 75), size: AXSize(width: 1024, height: 768))
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(MoveResizeOutput.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.position?.x, 50)
        XCTAssertEqual(decoded.size?.width, 1024)
    }

    func testMoveResizeOutputWithNils() {
        let output = MoveResizeOutput(success: false, position: nil, size: nil)
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(MoveResizeOutput.self, from: data)
        XCTAssertFalse(decoded.success)
        XCTAssertNil(decoded.position)
        XCTAssertNil(decoded.size)
    }

    func testMoveResizeOutputPositionOnly() {
        let output = MoveResizeOutput(success: true, position: AXPoint(x: 300, y: 400), size: nil)
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(MoveResizeOutput.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.position?.x, 300)
        XCTAssertNil(decoded.size)
    }

    func testMoveResizeOutputSizeOnly() {
        let output = MoveResizeOutput(success: true, position: nil, size: AXSize(width: 640, height: 480))
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(MoveResizeOutput.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertNil(decoded.position)
        XCTAssertEqual(decoded.size?.width, 640)
    }

    func testMoveResizeOutputWithAction() {
        let output = MoveResizeOutput(success: true, action: "minimize", position: nil, size: nil)
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"success\" : true"))
        XCTAssertTrue(json.contains("\"action\" : \"minimize\""))
        let decoded = try! JSONDecoder().decode(MoveResizeOutput.self, from: data)
        XCTAssertNil(decoded.position)
        XCTAssertNil(decoded.size)
    }

    func testMoveResizeOutputWithNilAction() {
        let output = MoveResizeOutput(success: true, position: AXPoint(x: 100, y: 200), size: AXSize(width: 800, height: 600))
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(MoveResizeOutput.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertNil(decoded.action)
        XCTAssertEqual(decoded.position?.x, 100)
        XCTAssertEqual(decoded.size?.width, 800)
    }

    // MARK: - ClipboardOutput

    func testClipboardOutputEncodingGet() {
        let output = ClipboardOutput(success: true, text: "Hello clipboard")
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"success\" : true"))
        XCTAssertTrue(json.contains("\"Hello clipboard\""))
    }

    func testClipboardOutputEncodingSet() {
        let output = ClipboardOutput(success: true, text: nil)
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"success\" : true"))
    }

    func testClipboardOutputRoundTrip() {
        let output = ClipboardOutput(success: true, text: "test data")
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(ClipboardOutput.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.text, "test data")
    }

    func testClipboardOutputRoundTripNilText() {
        let output = ClipboardOutput(success: false, text: nil)
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(ClipboardOutput.self, from: data)
        XCTAssertFalse(decoded.success)
        XCTAssertNil(decoded.text)
    }

    func testClipboardOutputWithSpecialCharacters() {
        let output = ClipboardOutput(success: true, text: "line1\nline2\ttab \"quotes\" and 日本語")
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(ClipboardOutput.self, from: data)
        XCTAssertEqual(decoded.text, "line1\nline2\ttab \"quotes\" and 日本語")
    }

    func testClipboardOutputWithEmptyString() {
        let output = ClipboardOutput(success: true, text: "")
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(ClipboardOutput.self, from: data)
        XCTAssertEqual(decoded.text, "")
    }

    // MARK: - WaitForValueOutput

    func testWaitForValueOutputEncoding() {
        let output = WaitForValueOutput(success: true, elapsed_ms: 1500, oldValue: "loading", newValue: "done")
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("1500"))
        XCTAssertTrue(json.contains("\"loading\""))
        XCTAssertTrue(json.contains("\"done\""))
    }

    func testWaitForValueOutputRoundTrip() {
        let output = WaitForValueOutput(success: true, elapsed_ms: 200, oldValue: "0", newValue: "100")
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(WaitForValueOutput.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.elapsed_ms, 200)
        XCTAssertEqual(decoded.oldValue, "0")
        XCTAssertEqual(decoded.newValue, "100")
    }

    func testWaitForValueOutputWithNilValues() {
        let output = WaitForValueOutput(success: true, elapsed_ms: 500, oldValue: nil, newValue: "new")
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(WaitForValueOutput.self, from: data)
        XCTAssertNil(decoded.oldValue)
        XCTAssertEqual(decoded.newValue, "new")
    }

    func testWaitForValueOutputBothNilValues() {
        let output = WaitForValueOutput(success: false, elapsed_ms: 10000, oldValue: nil, newValue: nil)
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(WaitForValueOutput.self, from: data)
        XCTAssertFalse(decoded.success)
        XCTAssertEqual(decoded.elapsed_ms, 10000)
        XCTAssertNil(decoded.oldValue)
        XCTAssertNil(decoded.newValue)
    }

    // MARK: - VMInfo

    func testVMInfoEncoding() {
        let info = VMInfo(name: "axon-abc12345", base: "ghcr.io/cirruslabs/macos-sonoma-base:latest", created: "2026-04-11T10:30:00Z", ip: "192.168.64.5")
        let data = try! jsonEncoder.encode(info)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"name\" : \"axon-abc12345\""))
        XCTAssertTrue(json.contains("\"base\""))
        XCTAssertTrue(json.contains("\"created\" : \"2026-04-11T10:30:00Z\""))
        XCTAssertTrue(json.contains("\"ip\" : \"192.168.64.5\""))
    }

    func testVMInfoRoundTrip() {
        let info = VMInfo(name: "axon-deadbeef", base: "sonoma", created: "2026-01-01T00:00:00Z", ip: "10.0.0.5")
        let data = try! jsonEncoder.encode(info)
        let decoded = try! JSONDecoder().decode(VMInfo.self, from: data)
        XCTAssertEqual(decoded.name, "axon-deadbeef")
        XCTAssertEqual(decoded.base, "sonoma")
        XCTAssertEqual(decoded.created, "2026-01-01T00:00:00Z")
        XCTAssertEqual(decoded.ip, "10.0.0.5")
    }

    func testVMInfoNilIP() {
        let info = VMInfo(name: "axon-pending", base: "sonoma", created: "2026-01-01T00:00:00Z", ip: nil)
        let data = try! jsonEncoder.encode(info)
        let decoded = try! JSONDecoder().decode(VMInfo.self, from: data)
        XCTAssertNil(decoded.ip)
        XCTAssertEqual(decoded.name, "axon-pending")
    }

    // MARK: - VMAcquireOutput

    func testVMAcquireOutputEncoding() {
        let output = VMAcquireOutput(success: true, name: "axon-12ab34cd", base: "sonoma-base", created: "2026-04-11T10:30:00Z", ip: "192.168.64.10")
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"success\" : true"))
        XCTAssertTrue(json.contains("\"name\" : \"axon-12ab34cd\""))
        XCTAssertTrue(json.contains("\"base\" : \"sonoma-base\""))
        XCTAssertTrue(json.contains("\"created\" : \"2026-04-11T10:30:00Z\""))
        XCTAssertTrue(json.contains("\"ip\" : \"192.168.64.10\""))
    }

    func testVMAcquireOutputRoundTrip() {
        let output = VMAcquireOutput(success: true, name: "axon-feedface", base: "sequoia", created: "2026-02-15T12:00:00Z", ip: "192.168.64.20")
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(VMAcquireOutput.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.name, "axon-feedface")
        XCTAssertEqual(decoded.base, "sequoia")
        XCTAssertEqual(decoded.created, "2026-02-15T12:00:00Z")
        XCTAssertEqual(decoded.ip, "192.168.64.20")
    }

    func testVMAcquireOutputNilIP() {
        let output = VMAcquireOutput(success: true, name: "axon-noip", base: "sonoma", created: "2026-01-01T00:00:00Z", ip: nil)
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(VMAcquireOutput.self, from: data)
        XCTAssertNil(decoded.ip)
    }

    // MARK: - VMReleaseOutput

    func testVMReleaseOutputEncoding() {
        let output = VMReleaseOutput(success: true, name: "axon-cafebabe")
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"success\" : true"))
        XCTAssertTrue(json.contains("\"name\" : \"axon-cafebabe\""))
    }

    func testVMReleaseOutputRoundTrip() {
        let output = VMReleaseOutput(success: true, name: "axon-12345678")
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(VMReleaseOutput.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.name, "axon-12345678")
    }

    // MARK: - VMReleaseAllOutput

    func testVMReleaseAllOutputEncoding() {
        let output = VMReleaseAllOutput(success: true, released: 3, failed: 0)
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"success\" : true"))
        XCTAssertTrue(json.contains("\"released\" : 3"))
        XCTAssertTrue(json.contains("\"failed\" : 0"))
    }

    func testVMReleaseAllOutputRoundTrip() {
        let output = VMReleaseAllOutput(success: false, released: 2, failed: 1)
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(VMReleaseAllOutput.self, from: data)
        XCTAssertFalse(decoded.success)
        XCTAssertEqual(decoded.released, 2)
        XCTAssertEqual(decoded.failed, 1)
    }

    func testVMReleaseAllOutputZeroCounts() {
        let output = VMReleaseAllOutput(success: true, released: 0, failed: 0)
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(VMReleaseAllOutput.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.released, 0)
        XCTAssertEqual(decoded.failed, 0)
    }

    // MARK: - VMListOutput

    func testVMListOutputEncodingEmpty() {
        let output = VMListOutput(success: true, vms: [])
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"success\" : true"))
        XCTAssertTrue(json.contains("\"vms\""))
    }

    func testVMListOutputRoundTripEmpty() {
        let output = VMListOutput(success: true, vms: [])
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(VMListOutput.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertTrue(decoded.vms.isEmpty)
    }

    func testVMListOutputRoundTripMultiple() {
        let vms = [
            VMInfo(name: "axon-aaaa", base: "sonoma", created: "2026-01-01T00:00:00Z", ip: "10.0.0.1"),
            VMInfo(name: "axon-bbbb", base: "sequoia", created: "2026-01-02T00:00:00Z", ip: "10.0.0.2"),
            VMInfo(name: "axon-cccc", base: "ventura", created: "2026-01-03T00:00:00Z", ip: nil),
        ]
        let output = VMListOutput(success: true, vms: vms)
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(VMListOutput.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.vms.count, 3)
        XCTAssertEqual(decoded.vms[0].name, "axon-aaaa")
        XCTAssertEqual(decoded.vms[1].base, "sequoia")
        XCTAssertNil(decoded.vms[2].ip)
    }

    // MARK: - AXNode new attributes

    func testAXNodeEncodingWithNewAttributes() {
        let node = AXNode(
            role: "AXSlider",
            subrole: nil,
            title: "Volume",
            identifier: "volumeSlider",
            label: nil,
            value: "50",
            enabled: true,
            focused: false,
            selected: true,
            expanded: false,
            placeholder: "Search...",
            minValue: 0,
            maxValue: 100,
            actions: ["AXPress", "AXShowMenu"],
            position: AXPoint(x: 10, y: 20),
            size: AXSize(width: 200, height: 30),
            path: "AXWindow[0]/AXSlider[0]",
            children: nil
        )
        let data = try! jsonEncoder.encode(node)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("\"selected\" : true"))
        XCTAssertTrue(json.contains("\"expanded\" : false"))
        XCTAssertTrue(json.contains("\"placeholder\" : \"Search...\""))
        XCTAssertTrue(json.contains("\"minValue\" : 0"))
        XCTAssertTrue(json.contains("\"maxValue\" : 100"))
        XCTAssertTrue(json.contains("\"actions\""))
        XCTAssertTrue(json.contains("\"AXPress\""))
        XCTAssertTrue(json.contains("\"AXShowMenu\""))
    }

    func testAXNodeCompactEncodingSkipsNilNewAttributes() {
        let node = AXNode(
            role: "AXButton",
            subrole: nil,
            title: "OK",
            identifier: nil,
            label: nil,
            value: nil,
            enabled: true,
            focused: false,
            position: nil,
            size: nil,
            path: "AXButton[0]",
            children: nil
        )
        let compact = node.compacted()
        let data = try! jsonEncoder.encode(compact)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertFalse(json.contains("\"selected\""))
        XCTAssertFalse(json.contains("\"expanded\""))
        XCTAssertFalse(json.contains("\"placeholder\""))
        XCTAssertFalse(json.contains("\"minValue\""))
        XCTAssertFalse(json.contains("\"maxValue\""))
        XCTAssertFalse(json.contains("\"actions\""))
    }

    func testAXNodeCompactEncodingIncludesNewAttributes() {
        let node = AXNode(
            role: "AXSlider",
            subrole: nil,
            title: "Volume",
            identifier: nil,
            label: nil,
            value: "50",
            enabled: true,
            focused: false,
            selected: true,
            expanded: false,
            placeholder: "Search...",
            minValue: 0,
            maxValue: 100,
            actions: ["AXPress"],
            position: nil,
            size: nil,
            path: "AXSlider[0]",
            children: nil
        )
        let compact = node.compacted()
        let data = try! jsonEncoder.encode(compact)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("\"selected\" : true"))
        XCTAssertTrue(json.contains("\"expanded\" : false"))
        XCTAssertTrue(json.contains("\"placeholder\" : \"Search...\""))
        XCTAssertTrue(json.contains("\"minValue\" : 0"))
        XCTAssertTrue(json.contains("\"maxValue\" : 100"))
        XCTAssertTrue(json.contains("\"actions\""))
        XCTAssertTrue(json.contains("\"AXPress\""))
    }

    // MARK: - SetValueOutput

    func testSetValueOutputEncoding() {
        let output = SetValueOutput(success: true, previousValue: "50", newValue: "75")
        let data = try! jsonEncoder.encode(output)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"success\" : true"))
        XCTAssertTrue(json.contains("\"previousValue\" : \"50\""))
        XCTAssertTrue(json.contains("\"newValue\" : \"75\""))
    }

    func testSetValueOutputEncodingNilValues() {
        let output = SetValueOutput(success: false, previousValue: nil, newValue: nil)
        let data = try! jsonEncoder.encode(output)
        let decoded = try! JSONDecoder().decode(SetValueOutput.self, from: data)
        XCTAssertFalse(decoded.success)
        XCTAssertNil(decoded.previousValue)
        XCTAssertNil(decoded.newValue)
    }

    // MARK: - DoctorOutput tests

    func testDoctorCheckEncoding() throws {
        let check = DoctorCheck(
            name: "accessibility",
            status: .ok,
            message: "AX trust granted",
            fix_hint: nil
        )
        let data = try jsonEncoder.encode(check)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["name"] as? String, "accessibility")
        XCTAssertEqual(json["status"] as? String, "ok")
        XCTAssertEqual(json["message"] as? String, "AX trust granted")
        XCTAssertNil(json["fix_hint"])
    }

    func testDoctorCheckEncodingWithFixHint() throws {
        let check = DoctorCheck(
            name: "accessibility",
            status: .fail,
            message: "Not granted",
            fix_hint: "Enable in System Settings"
        )
        let data = try jsonEncoder.encode(check)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["status"] as? String, "fail")
        XCTAssertEqual(json["fix_hint"] as? String, "Enable in System Settings")
    }

    func testDoctorOutputEncoding() throws {
        let output = DoctorOutput(
            ready: false,
            checks: [
                DoctorCheck(name: "a", status: .ok, message: "ok", fix_hint: nil),
                DoctorCheck(name: "b", status: .fail, message: "no", fix_hint: "fix it"),
            ]
        )
        let data = try jsonEncoder.encode(output)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["ready"] as? Bool, false)
        let checks = json["checks"] as! [[String: Any]]
        XCTAssertEqual(checks.count, 2)
    }

    func testDoctorStatusRawValues() {
        XCTAssertEqual(DoctorStatus.ok.rawValue, "ok")
        XCTAssertEqual(DoctorStatus.warn.rawValue, "warn")
        XCTAssertEqual(DoctorStatus.fail.rawValue, "fail")
    }
}
