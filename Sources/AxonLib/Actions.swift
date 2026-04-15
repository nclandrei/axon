import Cocoa
import ApplicationServices
import CoreGraphics

// MARK: - Launch

/// Launch an app by name, bundle ID, or path. Waits up to 5s for it to start.
public func launchApp(name: String?, bundleID: String?, path: String?, background: Bool = false, timeout: TimeInterval = 5.0) -> NSRunningApplication? {
    let workspace = NSWorkspace.shared

    if let path = path {
        let url = URL(fileURLWithPath: path)
        let sem = DispatchSemaphore(value: 0)
        var launched: NSRunningApplication?
        let config = NSWorkspace.OpenConfiguration()
        if background { config.activates = false }
        workspace.openApplication(at: url, configuration: config) { app, _ in
            launched = app
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + timeout)
        if let app = launched { return app }
        let bundleForPath = Bundle(url: url)?.bundleIdentifier
        if let bid = bundleForPath {
            return waitForApp(bundleID: bid, name: nil, timeout: timeout)
        }
    }

    if let bundleID = bundleID {
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            let sem = DispatchSemaphore(value: 0)
            var launched: NSRunningApplication?
            let config = NSWorkspace.OpenConfiguration()
            if background { config.activates = false }
            workspace.openApplication(at: appURL, configuration: config) { app, _ in
                launched = app
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + timeout)
            if let app = launched { return app }
            return waitForApp(bundleID: bundleID, name: nil, timeout: timeout)
        }
    }

    if let name = name {
        // Resolve app name to URL via Spotlight-style lookup
        if let appURL = NSWorkspace.shared.fullPath(forApplication: name).flatMap({ URL(fileURLWithPath: $0) }) {
            let sem = DispatchSemaphore(value: 0)
            var launched: NSRunningApplication?
            let config = NSWorkspace.OpenConfiguration()
            if background { config.activates = false }
            workspace.openApplication(at: appURL, configuration: config) { app, _ in
                launched = app
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + timeout)
            if let app = launched { return app }
            return waitForApp(bundleID: nil, name: name, timeout: timeout)
        }
    }

    return nil
}

private func waitForApp(bundleID: String?, name: String?, timeout: TimeInterval) -> NSRunningApplication? {
    let start = Date()
    while Date().timeIntervalSince(start) < timeout {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        if let bid = bundleID, let app = apps.first(where: { $0.bundleIdentifier == bid }) {
            return app
        }
        if let n = name, let app = apps.first(where: { $0.localizedName == n }) {
            return app
        }
        usleep(200_000) // 200ms
    }
    return nil
}

// MARK: - Activate

@discardableResult
public func activateApp(_ app: NSRunningApplication) -> Bool {
    app.activate(options: [.activateIgnoringOtherApps])
    // Give the system a moment to bring it forward
    usleep(100_000) // 100ms
    return app.isActive
}

// MARK: - Close / Quit

/// Quit an app entirely
public func quitApp(_ app: NSRunningApplication) -> Bool {
    app.terminate()
    // Wait briefly to confirm
    usleep(500_000) // 500ms
    return app.isTerminated
}

/// Close a specific window (or the frontmost window) via AX
public func closeWindow(axApp: AXUIElement, windowTitle: String?) -> Bool {
    let windows: [AXUIElement] = axAttribute(axApp, kAXWindowsAttribute as String) ?? []

    let target: AXUIElement?
    if let title = windowTitle {
        target = windows.first { win in
            let t: String? = axStringAttribute(win, kAXTitleAttribute as String)
            return t?.localizedCaseInsensitiveContains(title) == true
        }
    } else {
        // Close the frontmost/first window
        target = windows.first
    }

    guard let window = target else { return false }

    // Try the close button
    if let closeButton: AXUIElement = axAttribute(window, kAXCloseButtonAttribute as String) {
        let result = AXUIElementPerformAction(closeButton, kAXPressAction as CFString)
        if result == .success { return true }
    }

    // Fall back to AXCloseAction on the window itself (some apps support this)
    let result = AXUIElementPerformAction(window, "AXClose" as CFString)
    return result == .success
}

// MARK: - Click

public enum ClickMethod: String {
    case axPress
    case coordinateClick
}

public func performClick(element: AXUIElement, modifiers: CGEventFlags = []) -> Bool {
    return performClickWithMethod(element: element, modifiers: modifiers) != nil
}

public func performClickWithMethod(element: AXUIElement, modifiers: CGEventFlags = []) -> ClickMethod? {
    // Try AXPress first when no modifiers
    if modifiers.isEmpty {
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        if result == .success {
            return .axPress
        }
    }

    // Fall back to coordinate-based CGEvent click at element center
    guard let pos = axPointAttribute(element), let sz = axSizeAttribute(element) else {
        return nil
    }
    let x = pos.x + sz.width / 2
    let y = pos.y + sz.height / 2
    let point = CGPoint(x: x, y: y)

    guard let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
          let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
        return nil
    }

    mouseDown.flags = modifiers
    mouseUp.flags = modifiers
    mouseDown.post(tap: .cghidEventTap)
    usleep(50_000)
    mouseUp.post(tap: .cghidEventTap)
    return .coordinateClick
}

// MARK: - Right-Click

public func performRightClick(element: AXUIElement, modifiers: CGEventFlags = []) -> Bool {
    // If no modifiers, try AXShowMenu first (works for most elements with context menus)
    if modifiers.isEmpty {
        let showMenuResult = AXUIElementPerformAction(element, kAXShowMenuAction as CFString)
        if showMenuResult == .success {
            return true
        }
    }

    // Fall back to (or directly use) CGEvent right-click at element center
    guard let pos = axPointAttribute(element), let sz = axSizeAttribute(element) else {
        return false
    }

    let x = pos.x + sz.width / 2
    let y = pos.y + sz.height / 2
    let point = CGPoint(x: x, y: y)

    guard let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right),
          let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right) else {
        return false
    }

    mouseDown.flags = modifiers
    mouseUp.flags = modifiers
    mouseDown.post(tap: .cghidEventTap)
    usleep(50_000) // 50ms
    mouseUp.post(tap: .cghidEventTap)

    return true
}

// MARK: - Double-Click

public func performDoubleClick(element: AXUIElement, modifiers: CGEventFlags = []) -> Bool {
    guard let pos = axPointAttribute(element), let sz = axSizeAttribute(element) else {
        return false
    }

    let x = pos.x + sz.width / 2
    let y = pos.y + sz.height / 2
    let point = CGPoint(x: x, y: y)

    // First click
    guard let mouseDown1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
          let mouseUp1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left),
          let mouseDown2 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
          let mouseUp2 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
        return false
    }

    mouseDown1.setIntegerValueField(.mouseEventClickState, value: 1)
    mouseUp1.setIntegerValueField(.mouseEventClickState, value: 1)
    mouseDown2.setIntegerValueField(.mouseEventClickState, value: 2)
    mouseUp2.setIntegerValueField(.mouseEventClickState, value: 2)

    mouseDown1.flags = modifiers
    mouseUp1.flags = modifiers
    mouseDown2.flags = modifiers
    mouseUp2.flags = modifiers

    mouseDown1.post(tap: .cghidEventTap)
    mouseUp1.post(tap: .cghidEventTap)
    usleep(50_000) // 50ms between clicks
    mouseDown2.post(tap: .cghidEventTap)
    mouseUp2.post(tap: .cghidEventTap)

    return true
}

// MARK: - Type / Set Value

public enum TypeMethod: String {
    case direct
    case keyboard
}

public func performType(element: AXUIElement, text: String, clear: Bool) -> TypeMethod? {
    // Focus the element first
    AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)
    usleep(50_000) // 50ms for focus to take

    if clear {
        // Clear existing value by setting empty string first
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, "" as CFTypeRef)
        usleep(50_000)
    }

    // Try direct value setting first
    let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
    if result == .success {
        return .direct
    }

    // Fall back to keyboard event injection
    if typeViaKeyboard(text: text) {
        return .keyboard
    }

    return nil
}

private func typeViaKeyboard(text: String) -> Bool {
    guard let source = CGEventSource(stateID: .hidSystemState) else { return false }

    for char in text {
        let str = String(char)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)

        guard let keyDown = keyDown, let keyUp = keyUp else { continue }

        var unicodeChars = Array(str.utf16)
        keyDown.keyboardSetUnicodeString(stringLength: unicodeChars.count, unicodeString: &unicodeChars)
        keyUp.keyboardSetUnicodeString(stringLength: unicodeChars.count, unicodeString: &unicodeChars)

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        usleep(10_000) // 10ms between keystrokes
    }

    return true
}

// MARK: - Set Value

/// Set the value of a UI element (slider, stepper, checkbox, etc.)
public func performSetValue(element: AXUIElement, value: String) -> (success: Bool, previousValue: String?, newValue: String?) {
    // Read current value for reporting
    let previousValue: String? = {
        var raw: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as String as CFString, &raw)
        guard result == .success, let v = raw else { return nil }
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }()

    // Try setting as number first (for sliders, steppers)
    if let numValue = Double(value) {
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, numValue as CFTypeRef)
        if result == .success {
            let newValue = readCurrentValue(element)
            return (true, previousValue, newValue)
        }

        // Try as NSNumber
        let nsNum = NSNumber(value: numValue)
        let result2 = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, nsNum as CFTypeRef)
        if result2 == .success {
            let newValue = readCurrentValue(element)
            return (true, previousValue, newValue)
        }
    }

    // Try as boolean (for checkboxes: "true"/"false", "1"/"0")
    if let boolValue = parseBoolValue(value) {
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, (boolValue ? 1 : 0) as CFTypeRef)
        if result == .success {
            let newValue = readCurrentValue(element)
            return (true, previousValue, newValue)
        }
    }

    // Try as string (fallback)
    let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFTypeRef)
    if result == .success {
        let newValue = readCurrentValue(element)
        return (true, previousValue, newValue)
    }

    return (false, previousValue, nil)
}

private func readCurrentValue(_ element: AXUIElement) -> String? {
    var raw: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as String as CFString, &raw)
    guard result == .success, let v = raw else { return nil }
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    return nil
}

private func parseBoolValue(_ value: String) -> Bool? {
    switch value.lowercased() {
    case "true", "1", "yes", "on": return true
    case "false", "0", "no", "off": return false
    default: return nil
    }
}

// MARK: - Drag

public func performDrag(fromElement: AXUIElement, toElement: AXUIElement, duration: Double = 0.5) -> Bool {
    guard let fromPos = axPointAttribute(fromElement), let fromSz = axSizeAttribute(fromElement),
          let toPos = axPointAttribute(toElement), let toSz = axSizeAttribute(toElement) else {
        return false
    }

    let fromPoint = CGPoint(x: fromPos.x + fromSz.width / 2, y: fromPos.y + fromSz.height / 2)
    let toPoint = CGPoint(x: toPos.x + toSz.width / 2, y: toPos.y + toSz.height / 2)

    return performDragBetweenPoints(from: fromPoint, to: toPoint, duration: duration)
}

private func performDragBetweenPoints(from: CGPoint, to: CGPoint, duration: Double) -> Bool {
    guard let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: from, mouseButton: .left) else {
        return false
    }
    moveEvent.post(tap: .cghidEventTap)
    usleep(100_000)

    guard let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: from, mouseButton: .left) else {
        return false
    }
    mouseDown.post(tap: .cghidEventTap)
    usleep(100_000)

    let steps = 20
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        let x = from.x + (to.x - from.x) * t
        let y = from.y + (to.y - from.y) * t
        let point = CGPoint(x: x, y: y)

        guard let dragEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left) else {
            continue
        }
        dragEvent.post(tap: .cghidEventTap)
        usleep(UInt32(duration / Double(steps) * 1_000_000))
    }

    guard let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: to, mouseButton: .left) else {
        return false
    }
    mouseUp.post(tap: .cghidEventTap)

    return true
}

// MARK: - Key Press

/// Map of key names to virtual key codes
public let keyNameToCode: [String: CGKeyCode] = [
    "return": 0x24, "enter": 0x24,
    "tab": 0x30,
    "space": 0x31,
    "escape": 0x35, "esc": 0x35,
    "delete": 0x33, "backspace": 0x33,
    "forwarddelete": 0x75,
    "up": 0x7E, "down": 0x7D, "left": 0x7B, "right": 0x7C,
    "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76,
    "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64,
    "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
    "home": 0x73, "end": 0x77,
    "pageup": 0x74, "pagedown": 0x79,
    "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02, "e": 0x0E,
    "f": 0x03, "g": 0x05, "h": 0x04, "i": 0x22, "j": 0x26,
    "k": 0x28, "l": 0x25, "m": 0x2E, "n": 0x2D, "o": 0x1F,
    "p": 0x23, "q": 0x0C, "r": 0x0F, "s": 0x01, "t": 0x11,
    "u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07, "y": 0x10,
    "z": 0x06,
    "0": 0x1D, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15,
    "5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19,
    "minus": 0x1B, "-": 0x1B,
    "equal": 0x18, "=": 0x18,
    "leftbracket": 0x21, "[": 0x21,
    "rightbracket": 0x1E, "]": 0x1E,
    "backslash": 0x2A, "\\": 0x2A,
    "semicolon": 0x29, ";": 0x29,
    "quote": 0x27, "'": 0x27,
    "comma": 0x2B, ",": 0x2B,
    "period": 0x2F, ".": 0x2F,
    "slash": 0x2C, "/": 0x2C,
    "grave": 0x32, "`": 0x32,
]

/// Parse modifier string like "cmd+shift" into CGEventFlags
public func parseModifiers(_ modifierString: String) -> CGEventFlags {
    var flags: CGEventFlags = []
    let parts = modifierString.lowercased().split(separator: "+").map(String.init)
    for part in parts {
        switch part.trimmingCharacters(in: .whitespaces) {
        case "cmd", "command":    flags.insert(.maskCommand)
        case "shift":             flags.insert(.maskShift)
        case "alt", "option":     flags.insert(.maskAlternate)
        case "ctrl", "control":   flags.insert(.maskControl)
        case "fn", "function":    flags.insert(.maskSecondaryFn)
        default: break
        }
    }
    return flags
}

/// Perform a key press with optional modifiers
public func performKeyPress(keyName: String, modifiers: CGEventFlags) -> Bool {
    let lowerKey = keyName.lowercased()
    guard let keyCode = keyNameToCode[lowerKey] else {
        return false
    }

    guard let source = CGEventSource(stateID: .hidSystemState) else { return false }

    guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
        return false
    }

    keyDown.flags = modifiers
    keyUp.flags = modifiers

    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)

    return true
}

// MARK: - Hover

public func performHover(element: AXUIElement) -> AXPoint? {
    guard let pos = axPointAttribute(element), let sz = axSizeAttribute(element) else {
        return nil
    }

    let x = pos.x + sz.width / 2
    let y = pos.y + sz.height / 2
    let point = CGPoint(x: x, y: y)

    guard let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else {
        return nil
    }
    moveEvent.post(tap: .cghidEventTap)

    return AXPoint(x: x, y: y)
}

// MARK: - Scroll

public func performScroll(element: AXUIElement, direction: ScrollDirection, amount: Int32) {
    // Get the element's position to target the scroll
    guard let pos = axPointAttribute(element), let sz = axSizeAttribute(element) else {
        // Fall back to center of screen
        performScrollAt(x: 500, y: 500, direction: direction, amount: amount)
        return
    }

    // Target center of the element
    let x = pos.x + sz.width / 2
    let y = pos.y + sz.height / 2
    performScrollAt(x: x, y: y, direction: direction, amount: amount)
}

public enum ScrollDirection: String {
    case up, down, left, right
}

private func performScrollAt(x: Double, y: Double, direction: ScrollDirection, amount: Int32) {
    let scrollX: Int32
    let scrollY: Int32

    switch direction {
    case .up:    scrollX = 0; scrollY = amount
    case .down:  scrollX = 0; scrollY = -amount
    case .left:  scrollX = amount; scrollY = 0
    case .right: scrollX = -amount; scrollY = 0
    }

    guard let event = CGEvent(
        scrollWheelEvent2Source: nil,
        units: .line,
        wheelCount: 2,
        wheel1: scrollY,
        wheel2: scrollX,
        wheel3: 0
    ) else { return }

    // Move mouse to element position first
    if let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left) {
        moveEvent.post(tap: .cghidEventTap)
        usleep(50_000) // 50ms
    }

    event.post(tap: .cghidEventTap)
}

// MARK: - Menu

/// Navigate and activate a menu item by path (e.g. "File > Save")
public func performMenuAction(axApp: AXUIElement, menuPath: String) -> FoundElement? {
    guard let menuBar: AXUIElement = axAttribute(axApp, kAXMenuBarAttribute as String) else {
        return nil
    }

    let components = menuPath.split(separator: ">").map { $0.trimmingCharacters(in: .whitespaces) }
    guard !components.isEmpty else { return nil }

    var current: AXUIElement = menuBar

    for (index, component) in components.enumerated() {
        let children = axChildren(current)
        var found: AXUIElement?

        for child in children {
            let title: String? = axStringAttribute(child, kAXTitleAttribute as String)
            if let title = title, title.localizedCaseInsensitiveCompare(component) == .orderedSame {
                found = child
                break
            }
        }

        guard let menuItem = found else { return nil }

        let isLeaf = index == components.count - 1

        if isLeaf {
            // Activate the menu item
            AXUIElementPerformAction(menuItem, kAXPressAction as CFString)
            return FoundElement(
                element: menuItem,
                role: axStringAttribute(menuItem, kAXRoleAttribute as String),
                title: axStringAttribute(menuItem, kAXTitleAttribute as String),
                identifier: axStringAttribute(menuItem, kAXIdentifierAttribute as String)
            )
        } else {
            // Open the submenu and descend
            AXUIElementPerformAction(menuItem, kAXPressAction as CFString)
            usleep(100_000) // 100ms for submenu to open

            // Try to get children directly (some menus expose children after press)
            let subChildren = axChildren(menuItem)
            if !subChildren.isEmpty {
                // Menu items with submenus often have a single submenu child
                // Check if any child is a menu (AXMenu) role
                for subChild in subChildren {
                    let role: String? = axStringAttribute(subChild, kAXRoleAttribute as String)
                    if role == "AXMenu" {
                        current = subChild
                        break
                    }
                }
                // If no AXMenu child found, use the menuItem itself as parent
                if current === menuBar || axChildren(current).isEmpty {
                    current = menuItem
                }
            } else {
                current = menuItem
            }
        }
    }

    return nil
}

/// List top-level menu bar items
public func listMenuBarItems(axApp: AXUIElement) -> [String] {
    guard let menuBar: AXUIElement = axAttribute(axApp, kAXMenuBarAttribute as String) else {
        return []
    }

    var items: [String] = []
    for child in axChildren(menuBar) {
        if let title: String = axStringAttribute(child, kAXTitleAttribute as String), !title.isEmpty {
            items.append(title)
        }
    }
    return items
}

// MARK: - Wait

public func performWait(appElement: AXUIElement, selector: ElementSelector, appear: Bool, timeout: TimeInterval) -> Int? {
    let startTime = Date()
    let pollInterval: useconds_t = 200_000 // 200ms

    while Date().timeIntervalSince(startTime) < timeout {
        let found = findElement(root: appElement, selector: selector)
        if appear && found != nil {
            let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
            return elapsed
        }
        if !appear && found == nil {
            let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
            return elapsed
        }
        usleep(pollInterval)
    }

    return nil // timeout
}

// MARK: - Window Actions

/// Minimize a window
public func performMinimize(window: AXUIElement) -> Bool {
    let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, true as CFTypeRef)
    return result == .success
}

/// Restore (un-minimize) a window
public func performRestore(window: AXUIElement) -> Bool {
    let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
    return result == .success
}

/// Zoom (maximize) a window — equivalent to clicking the green zoom button
public func performZoom(window: AXUIElement) -> Bool {
    // Try pressing the zoom button
    if let zoomButton: AXUIElement = axAttribute(window, kAXZoomButtonAttribute as String) {
        let result = AXUIElementPerformAction(zoomButton, kAXPressAction as CFString)
        return result == .success
    }
    return false
}

/// Toggle fullscreen on a window
public func performFullscreen(window: AXUIElement) -> Bool {
    // Read current fullscreen state
    let isFullScreen = axBoolAttribute(window, "AXFullScreen") ?? false
    // Toggle it
    let result = AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, (!isFullScreen) as CFTypeRef)
    return result == .success
}

// MARK: - Move / Resize Window

public struct MoveResizeResult {
    public let positionSet: Bool
    public let sizeSet: Bool
    public let newPosition: AXPoint?
    public let newSize: AXSize?
}

public func performMoveResize(window: AXUIElement, x: Double?, y: Double?, width: Double?, height: Double?) -> MoveResizeResult {
    var positionSet = false
    var sizeSet = false

    // Set position if x or y provided
    if let x = x, let y = y {
        var point = CGPoint(x: x, y: y)
        if let axValue = AXValueCreate(.cgPoint, &point) {
            let result = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, axValue)
            positionSet = (result == .success)
        }
    } else if let x = x {
        if let currentPos = axPointAttribute(window) {
            var point = CGPoint(x: x, y: currentPos.y)
            if let axValue = AXValueCreate(.cgPoint, &point) {
                let result = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, axValue)
                positionSet = (result == .success)
            }
        }
    } else if let y = y {
        if let currentPos = axPointAttribute(window) {
            var point = CGPoint(x: currentPos.x, y: y)
            if let axValue = AXValueCreate(.cgPoint, &point) {
                let result = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, axValue)
                positionSet = (result == .success)
            }
        }
    }

    // Set size if width or height provided
    if let width = width, let height = height {
        var size = CGSize(width: width, height: height)
        if let axValue = AXValueCreate(.cgSize, &size) {
            let result = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, axValue)
            sizeSet = (result == .success)
        }
    } else if let width = width {
        if let currentSize = axSizeAttribute(window) {
            var size = CGSize(width: width, height: currentSize.height)
            if let axValue = AXValueCreate(.cgSize, &size) {
                let result = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, axValue)
                sizeSet = (result == .success)
            }
        }
    } else if let height = height {
        if let currentSize = axSizeAttribute(window) {
            var size = CGSize(width: currentSize.width, height: height)
            if let axValue = AXValueCreate(.cgSize, &size) {
                let result = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, axValue)
                sizeSet = (result == .success)
            }
        }
    }

    let newPosition = axPointAttribute(window)
    let newSize = axSizeAttribute(window)

    return MoveResizeResult(positionSet: positionSet, sizeSet: sizeSet, newPosition: newPosition, newSize: newSize)
}

// MARK: - Clipboard

public func getClipboard() -> String? {
    let pasteboard = NSPasteboard.general
    return pasteboard.string(forType: .string)
}

public func setClipboard(text: String) -> Bool {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    return pasteboard.setString(text, forType: .string)
}

// MARK: - Wait for Value

public struct WaitForValueResult {
    public let elapsed_ms: Int
    public let oldValue: String?
    public let newValue: String?
}

public func performWaitForValue(appElement: AXUIElement, selector: ElementSelector, pattern: String?, timeout: TimeInterval) -> WaitForValueResult? {
    let startTime = Date()
    let pollInterval: useconds_t = 200_000 // 200ms

    guard let initialFound = findElement(root: appElement, selector: selector) else {
        return nil
    }

    let initialValue = axStringAttribute(initialFound.element, kAXValueAttribute as String)

    while Date().timeIntervalSince(startTime) < timeout {
        if let found = findElement(root: appElement, selector: selector) {
            let currentValue = axStringAttribute(found.element, kAXValueAttribute as String)

            if let pattern = pattern {
                if let cv = currentValue, cv.range(of: pattern, options: .regularExpression) != nil {
                    let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
                    return WaitForValueResult(elapsed_ms: elapsed, oldValue: initialValue, newValue: currentValue)
                }
            } else {
                if currentValue != initialValue {
                    let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
                    return WaitForValueResult(elapsed_ms: elapsed, oldValue: initialValue, newValue: currentValue)
                }
            }
        }
        usleep(pollInterval)
    }

    return nil // timeout
}
