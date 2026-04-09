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
}
