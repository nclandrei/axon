import Cocoa
import ApplicationServices
import CoreGraphics

// MARK: - Launch

/// Launch an app by name, bundle ID, or path. Waits up to 5s for it to start.
public func launchApp(name: String?, bundleID: String?, path: String?) -> NSRunningApplication? {
    let workspace = NSWorkspace.shared

    if let path = path {
        let url = URL(fileURLWithPath: path)
        let sem = DispatchSemaphore(value: 0)
        var launched: NSRunningApplication?
        workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { app, _ in
            launched = app
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 5.0)
        if let app = launched { return app }
        // If completion gave us nil, try polling by path
        let bundleForPath = Bundle(url: url)?.bundleIdentifier
        if let bid = bundleForPath {
            return waitForApp(bundleID: bid, name: nil, timeout: 5.0)
        }
    }

    if let bundleID = bundleID {
        // Try to launch by bundle ID
        if workspace.launchApplication(withBundleIdentifier: bundleID, options: [], additionalEventParamDescriptor: nil, launchIdentifier: nil) {
            return waitForApp(bundleID: bundleID, name: nil, timeout: 5.0)
        }
    }

    if let name = name {
        // Try to launch by name (uses Spotlight/LaunchServices)
        if workspace.launchApplication(name) {
            return waitForApp(bundleID: nil, name: name, timeout: 5.0)
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

public func performClick(element: AXUIElement) -> Bool {
    let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
    return result == .success
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
