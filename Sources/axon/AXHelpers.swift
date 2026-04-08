import Cocoa
import ApplicationServices

// MARK: - Accessibility Permission Check

func checkAccessibilityPermission() {
    guard AXIsProcessTrusted() else {
        printError(
            code: "accessibility_not_trusted",
            message: "axon does not have accessibility permissions. Add your terminal app to System Settings > Privacy & Security > Accessibility."
        )
        exit(1)
    }
}

// MARK: - AXUIElement Attribute Helpers

func axAttribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard result == .success else { return nil }
    return value as? T
}

func axStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
    axAttribute(element, attribute)
}

func axBoolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard result == .success else { return nil }
    if let num = value as? NSNumber {
        return num.boolValue
    }
    return value as? Bool
}

func axPointAttribute(_ element: AXUIElement) -> AXPoint? {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as String as CFString, &value)
    guard result == .success, let val = value else { return nil }
    var point = CGPoint.zero
    if AXValueGetValue(val as! AXValue, .cgPoint, &point) {
        return AXPoint(x: Double(point.x), y: Double(point.y))
    }
    return nil
}

func axSizeAttribute(_ element: AXUIElement) -> AXSize? {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as String as CFString, &value)
    guard result == .success, let val = value else { return nil }
    var size = CGSize.zero
    if AXValueGetValue(val as! AXValue, .cgSize, &size) {
        return AXSize(width: Double(size.width), height: Double(size.height))
    }
    return nil
}

func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as String as CFString, &value)
    guard result == .success, let children = value as? [AXUIElement] else { return [] }
    return children
}

// MARK: - Tree Building

/// Build an AXNode tree from an AXUIElement
func buildTree(element: AXUIElement, depth: Int, maxDepth: Int, path: String) -> AXNode {
    let role: String? = axStringAttribute(element, kAXRoleAttribute as String)
    let subrole: String? = axStringAttribute(element, kAXSubroleAttribute as String)
    let title: String? = axStringAttribute(element, kAXTitleAttribute as String)
    let identifier: String? = axStringAttribute(element, kAXIdentifierAttribute as String)
    let label: String? = axStringAttribute(element, kAXDescriptionAttribute as String)
    let value: String? = {
        // Try to get a string representation of the value
        var raw: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as String as CFString, &raw)
        guard result == .success, let v = raw else { return nil }
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }()
    let enabled: Bool? = axBoolAttribute(element, kAXEnabledAttribute as String)
    let focused: Bool? = axBoolAttribute(element, kAXFocusedAttribute as String)
    let position = axPointAttribute(element)
    let size = axSizeAttribute(element)

    var children: [AXNode]? = nil
    if depth < maxDepth {
        let axKids = axChildren(element)
        if !axKids.isEmpty {
            // Track role counts for path generation
            var roleCounts: [String: Int] = [:]
            children = axKids.map { child in
                let childRole = axStringAttribute(child, kAXRoleAttribute as String) ?? "unknown"
                let index = roleCounts[childRole, default: 0]
                roleCounts[childRole] = index + 1
                let childPath = path.isEmpty ? "\(childRole)[\(index)]" : "\(path)/\(childRole)[\(index)]"
                return buildTree(element: child, depth: depth + 1, maxDepth: maxDepth, path: childPath)
            }
        }
    }

    return AXNode(
        role: role,
        subrole: subrole,
        title: title,
        identifier: identifier,
        label: label,
        value: value,
        enabled: enabled,
        focused: focused,
        position: position,
        size: size,
        path: path,
        children: children
    )
}

// MARK: - Element Finding

enum ElementSelector {
    case identifier(String)
    case label(String)
    case path(String)
}

struct FoundElement {
    let element: AXUIElement
    let role: String?
    let title: String?
    let identifier: String?
}

/// Find an element in the accessibility tree by selector
func findElement(root: AXUIElement, selector: ElementSelector) -> FoundElement? {
    switch selector {
    case .path(let path):
        return findByPath(root: root, path: path)
    case .identifier(let id):
        // Try exact identifier match first
        if let found = findByAttribute(root: root, attribute: kAXIdentifierAttribute as String, value: id, exact: true) {
            return found
        }
        return nil
    case .label(let text):
        // Try exact title match
        if let found = findByAttribute(root: root, attribute: kAXTitleAttribute as String, value: text, exact: true) {
            return found
        }
        // Try exact description match
        if let found = findByAttribute(root: root, attribute: kAXDescriptionAttribute as String, value: text, exact: true) {
            return found
        }
        // Try case-insensitive contains on title
        if let found = findByAttribute(root: root, attribute: kAXTitleAttribute as String, value: text, exact: false) {
            return found
        }
        // Try case-insensitive contains on description
        if let found = findByAttribute(root: root, attribute: kAXDescriptionAttribute as String, value: text, exact: false) {
            return found
        }
        return nil
    }
}

/// Find element by tree path like "AXWindow[0]/AXGroup[1]/AXButton[0]"
private func findByPath(root: AXUIElement, path: String) -> FoundElement? {
    let components = path.split(separator: "/").map(String.init)
    var current = root

    for component in components {
        // Parse "role[index]"
        guard let bracketStart = component.firstIndex(of: "["),
              let bracketEnd = component.firstIndex(of: "]") else {
            return nil
        }
        let role = String(component[component.startIndex..<bracketStart])
        guard let index = Int(component[component.index(after: bracketStart)..<bracketEnd]) else {
            return nil
        }

        let children = axChildren(current)
        var roleCount = 0
        var found = false
        for child in children {
            let childRole = axStringAttribute(child, kAXRoleAttribute as String) ?? "unknown"
            if childRole == role {
                if roleCount == index {
                    current = child
                    found = true
                    break
                }
                roleCount += 1
            }
        }
        if !found { return nil }
    }

    return FoundElement(
        element: current,
        role: axStringAttribute(current, kAXRoleAttribute as String),
        title: axStringAttribute(current, kAXTitleAttribute as String),
        identifier: axStringAttribute(current, kAXIdentifierAttribute as String)
    )
}

/// Recursive search by attribute value
private func findByAttribute(root: AXUIElement, attribute: String, value: String, exact: Bool, maxDepth: Int = 20) -> FoundElement? {
    // Collect all matches, then pick the best one
    var matches: [(element: AXUIElement, enabled: Bool)] = []
    collectMatches(element: root, attribute: attribute, value: value, exact: exact, depth: 0, maxDepth: maxDepth, matches: &matches)

    if matches.isEmpty { return nil }

    // Prefer enabled + visible elements
    let best = matches.first(where: { $0.enabled }) ?? matches.first!

    return FoundElement(
        element: best.element,
        role: axStringAttribute(best.element, kAXRoleAttribute as String),
        title: axStringAttribute(best.element, kAXTitleAttribute as String),
        identifier: axStringAttribute(best.element, kAXIdentifierAttribute as String)
    )
}

private func collectMatches(element: AXUIElement, attribute: String, value: String, exact: Bool, depth: Int, maxDepth: Int, matches: inout [(element: AXUIElement, enabled: Bool)]) {
    guard depth <= maxDepth else { return }

    if let attrValue: String = axStringAttribute(element, attribute) {
        let matched: Bool
        if exact {
            matched = attrValue == value
        } else {
            matched = attrValue.localizedCaseInsensitiveContains(value)
        }
        if matched {
            let enabled = axBoolAttribute(element, kAXEnabledAttribute as String) ?? true
            matches.append((element: element, enabled: enabled))
        }
    }

    for child in axChildren(element) {
        collectMatches(element: child, attribute: attribute, value: value, exact: exact, depth: depth + 1, maxDepth: maxDepth, matches: &matches)
    }
}

/// Collect identifiers and labels near the root (for error messages)
func collectAvailableIdentifiers(root: AXUIElement, maxDepth: Int = 5, limit: Int = 20) -> [String] {
    var result: [String] = []
    collectIdentifiersRecursive(element: root, depth: 0, maxDepth: maxDepth, limit: limit, result: &result)
    return result
}

private func collectIdentifiersRecursive(element: AXUIElement, depth: Int, maxDepth: Int, limit: Int, result: inout [String]) {
    guard depth <= maxDepth, result.count < limit else { return }

    if let id: String = axStringAttribute(element, kAXIdentifierAttribute as String), !id.isEmpty {
        result.append(id)
    } else if let title: String = axStringAttribute(element, kAXTitleAttribute as String), !title.isEmpty {
        let role = axStringAttribute(element, kAXRoleAttribute as String) ?? ""
        result.append("\(role):\(title)")
    }

    for child in axChildren(element) {
        guard result.count < limit else { return }
        collectIdentifiersRecursive(element: child, depth: depth + 1, maxDepth: maxDepth, limit: limit, result: &result)
    }
}
