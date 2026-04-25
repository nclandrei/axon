import Foundation

public let axonVersion = "0.1.0"

public enum OutputFormat: String {
    case json
    case text
}

public func printPlain(_ pairs: [(String, String)]) {
    for (key, value) in pairs {
        print("\(key): \(value)")
    }
}

// MARK: - Output Models

/// Represents a node in the accessibility tree
public struct AXNode: Codable {
    public let role: String?
    public let subrole: String?
    public let title: String?
    public let identifier: String?
    public let label: String?
    public let value: String?
    public let enabled: Bool?
    public let focused: Bool?
    public let selected: Bool?
    public let expanded: Bool?
    public let placeholder: String?
    public let minValue: Double?
    public let maxValue: Double?
    public let actions: [String]?
    public let position: AXPoint?
    public let size: AXSize?
    public let path: String
    public let children: [AXNode]?

    public init(role: String?, subrole: String?, title: String?, identifier: String?, label: String?, value: String?, enabled: Bool?, focused: Bool?, selected: Bool? = nil, expanded: Bool? = nil, placeholder: String? = nil, minValue: Double? = nil, maxValue: Double? = nil, actions: [String]? = nil, position: AXPoint?, size: AXSize?, path: String, children: [AXNode]?) {
        self.role = role
        self.subrole = subrole
        self.title = title
        self.identifier = identifier
        self.label = label
        self.value = value
        self.enabled = enabled
        self.focused = focused
        self.selected = selected
        self.expanded = expanded
        self.placeholder = placeholder
        self.minValue = minValue
        self.maxValue = maxValue
        self.actions = actions
        self.position = position
        self.size = size
        self.path = path
        self.children = children
    }

    /// Returns a compact version with null fields and position/size omitted
    public func compacted() -> CompactAXNode {
        CompactAXNode(
            role: role,
            subrole: subrole,
            title: title,
            identifier: identifier,
            label: label,
            value: value,
            enabled: enabled,
            focused: focused,
            selected: selected,
            expanded: expanded,
            placeholder: placeholder,
            minValue: minValue,
            maxValue: maxValue,
            actions: actions,
            path: path,
            children: children?.map { $0.compacted() }
        )
    }
}

public struct CompactAXNode: Codable {
    public let role: String?
    public let subrole: String?
    public let title: String?
    public let identifier: String?
    public let label: String?
    public let value: String?
    public let enabled: Bool?
    public let focused: Bool?
    public let selected: Bool?
    public let expanded: Bool?
    public let placeholder: String?
    public let minValue: Double?
    public let maxValue: Double?
    public let actions: [String]?
    public let path: String
    public let children: [CompactAXNode]?

    public init(role: String?, subrole: String?, title: String?, identifier: String?, label: String?, value: String?, enabled: Bool?, focused: Bool?, selected: Bool? = nil, expanded: Bool? = nil, placeholder: String? = nil, minValue: Double? = nil, maxValue: Double? = nil, actions: [String]? = nil, path: String, children: [CompactAXNode]?) {
        self.role = role
        self.subrole = subrole
        self.title = title
        self.identifier = identifier
        self.label = label
        self.value = value
        self.enabled = enabled
        self.focused = focused
        self.selected = selected
        self.expanded = expanded
        self.placeholder = placeholder
        self.minValue = minValue
        self.maxValue = maxValue
        self.actions = actions
        self.path = path
        self.children = children
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let role = role { try container.encode(role, forKey: .role) }
        if let subrole = subrole { try container.encode(subrole, forKey: .subrole) }
        if let title = title { try container.encode(title, forKey: .title) }
        if let identifier = identifier { try container.encode(identifier, forKey: .identifier) }
        if let label = label { try container.encode(label, forKey: .label) }
        if let value = value { try container.encode(value, forKey: .value) }
        if let enabled = enabled { try container.encode(enabled, forKey: .enabled) }
        if let focused = focused { try container.encode(focused, forKey: .focused) }
        if let selected = selected { try container.encode(selected, forKey: .selected) }
        if let expanded = expanded { try container.encode(expanded, forKey: .expanded) }
        if let placeholder = placeholder { try container.encode(placeholder, forKey: .placeholder) }
        if let minValue = minValue { try container.encode(minValue, forKey: .minValue) }
        if let maxValue = maxValue { try container.encode(maxValue, forKey: .maxValue) }
        if let actions = actions, !actions.isEmpty { try container.encode(actions, forKey: .actions) }
        try container.encode(path, forKey: .path)
        if let children = children, !children.isEmpty {
            try container.encode(children, forKey: .children)
        }
    }

    enum CodingKeys: String, CodingKey {
        case role, subrole, title, identifier, label, value, enabled, focused
        case selected, expanded, placeholder, minValue, maxValue, actions
        case path, children
    }
}

public struct AXPoint: Codable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct AXSize: Codable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

// MARK: - App Info

public struct AppInfo: Codable {
    public let name: String
    public let bundleID: String?
    public let pid: Int32

    public init(name: String, bundleID: String?, pid: Int32) {
        self.name = name
        self.bundleID = bundleID
        self.pid = pid
    }
}

// MARK: - Command Output Models

public struct ListOutput: Codable {
    public let apps: [AppInfo]

    public init(apps: [AppInfo]) {
        self.apps = apps
    }
}

public struct TreeOutput: Codable {
    public let app: String
    public let pid: Int32
    public let tree: AXNode

    public init(app: String, pid: Int32, tree: AXNode) {
        self.app = app
        self.pid = pid
        self.tree = tree
    }
}

public struct CompactTreeOutput: Codable {
    public let app: String
    public let pid: Int32
    public let tree: CompactAXNode

    public init(app: String, pid: Int32, tree: CompactAXNode) {
        self.app = app
        self.pid = pid
        self.tree = tree
    }
}

public struct ClickOutput: Codable {
    public let success: Bool
    public let element: ElementInfo
    public let modifiers: [String]?

    public init(success: Bool, element: ElementInfo, modifiers: [String]? = nil) {
        self.success = success
        self.element = element
        self.modifiers = modifiers
    }
}

public struct RightClickOutput: Codable {
    public let success: Bool
    public let element: ElementInfo
    public let modifiers: [String]?

    public init(success: Bool, element: ElementInfo, modifiers: [String]? = nil) {
        self.success = success
        self.element = element
        self.modifiers = modifiers
    }
}

public struct DoubleClickOutput: Codable {
    public let success: Bool
    public let element: ElementInfo
    public let modifiers: [String]?

    public init(success: Bool, element: ElementInfo, modifiers: [String]? = nil) {
        self.success = success
        self.element = element
        self.modifiers = modifiers
    }
}

public struct TypeOutput: Codable {
    public let success: Bool
    public let method: String

    public init(success: Bool, method: String) {
        self.success = success
        self.method = method
    }
}

public struct ScrollOutput: Codable {
    public let success: Bool

    public init(success: Bool) {
        self.success = success
    }
}

public struct KeyOutput: Codable {
    public let success: Bool
    public let key: String
    public let modifiers: [String]?

    public init(success: Bool, key: String, modifiers: [String]?) {
        self.success = success
        self.key = key
        self.modifiers = modifiers
    }
}

public struct HoverOutput: Codable {
    public let success: Bool
    public let element: ElementInfo
    public let position: AXPoint

    public init(success: Bool, element: ElementInfo, position: AXPoint) {
        self.success = success
        self.element = element
        self.position = position
    }
}

public struct ScreenshotOutput: Codable {
    public let success: Bool
    public let path: String
    public let width: Int
    public let height: Int

    public init(success: Bool, path: String, width: Int, height: Int) {
        self.success = success
        self.path = path
        self.width = width
        self.height = height
    }
}

public struct ActivateOutput: Codable {
    public let success: Bool

    public init(success: Bool) {
        self.success = success
    }
}

public struct LaunchOutput: Codable {
    public let success: Bool
    public let name: String
    public let bundleID: String?
    public let pid: Int32

    public init(success: Bool, name: String, bundleID: String?, pid: Int32) {
        self.success = success
        self.name = name
        self.bundleID = bundleID
        self.pid = pid
    }
}

public struct CloseOutput: Codable {
    public let success: Bool
    public let action: String // "quit" or "close_window"

    public init(success: Bool, action: String) {
        self.success = success
        self.action = action
    }
}

public struct WaitOutput: Codable {
    public let success: Bool
    public let elapsed_ms: Int

    public init(success: Bool, elapsed_ms: Int) {
        self.success = success
        self.elapsed_ms = elapsed_ms
    }
}

public struct ElementInfo: Codable {
    public let role: String?
    public let title: String?
    public let identifier: String?

    public init(role: String?, title: String?, identifier: String?) {
        self.role = role
        self.title = title
        self.identifier = identifier
    }
}

// MARK: - GetValue Output

public struct GetValueOutput: Codable {
    public let success: Bool
    public let role: String?
    public let value: String?
    public let title: String?
    public let selectedText: String?
    public let enabled: Bool?
    public let focused: Bool?
    public let selected: Bool?
    public let description: String?

    public init(success: Bool, role: String?, value: String?, title: String?, selectedText: String?, enabled: Bool?, focused: Bool?, selected: Bool?, description: String?) {
        self.success = success
        self.role = role
        self.value = value
        self.title = title
        self.selectedText = selectedText
        self.enabled = enabled
        self.focused = focused
        self.selected = selected
        self.description = description
    }
}

// MARK: - Focused Output

public struct FocusedOutput: Codable {
    public let success: Bool
    public let element: ElementInfo?
    public let value: String?
    public let path: String?

    public init(success: Bool, element: ElementInfo?, value: String?, path: String?) {
        self.success = success
        self.element = element
        self.value = value
        self.path = path
    }
}

// MARK: - WindowInfo Output

public struct WindowInfo: Codable {
    public let title: String?
    public let position: AXPoint?
    public let size: AXSize?
    public let main: Bool?
    public let minimized: Bool?
    public let fullScreen: Bool?

    public init(title: String?, position: AXPoint?, size: AXSize?, main: Bool?, minimized: Bool?, fullScreen: Bool?) {
        self.title = title
        self.position = position
        self.size = size
        self.main = main
        self.minimized = minimized
        self.fullScreen = fullScreen
    }
}

public struct WindowInfoOutput: Codable {
    public let success: Bool
    public let windows: [WindowInfo]

    public init(success: Bool, windows: [WindowInfo]) {
        self.success = success
        self.windows = windows
    }
}

// MARK: - Menu Output

public struct MenuOutput: Codable {
    public let success: Bool
    public let menuItem: ElementInfo?

    public init(success: Bool, menuItem: ElementInfo?) {
        self.success = success
        self.menuItem = menuItem
    }
}

public struct MenuListOutput: Codable {
    public let success: Bool
    public let items: [String]

    public init(success: Bool, items: [String]) {
        self.success = success
        self.items = items
    }
}

// MARK: - DragOutput

public struct DragOutput: Codable {
    public let success: Bool
    public let from: ElementInfo
    public let to: ElementInfo

    public init(success: Bool, from: ElementInfo, to: ElementInfo) {
        self.success = success
        self.from = from
        self.to = to
    }
}

// MARK: - MoveResizeOutput

public struct MoveResizeOutput: Codable {
    public let success: Bool
    public let action: String?
    public let position: AXPoint?
    public let size: AXSize?

    public init(success: Bool, action: String? = nil, position: AXPoint?, size: AXSize?) {
        self.success = success
        self.action = action
        self.position = position
        self.size = size
    }
}

// MARK: - ClipboardOutput

public struct ClipboardOutput: Codable {
    public let success: Bool
    public let text: String?

    public init(success: Bool, text: String?) {
        self.success = success
        self.text = text
    }
}

// MARK: - WaitForValueOutput

public struct WaitForValueOutput: Codable {
    public let success: Bool
    public let elapsed_ms: Int
    public let oldValue: String?
    public let newValue: String?

    public init(success: Bool, elapsed_ms: Int, oldValue: String?, newValue: String?) {
        self.success = success
        self.elapsed_ms = elapsed_ms
        self.oldValue = oldValue
        self.newValue = newValue
    }
}

// MARK: - VM Management Output

/// JSON-friendly representation of a registered VM. The `created` field is an
/// ISO8601 timestamp string so the global encoder doesn't need a date strategy.
public struct VMInfo: Codable {
    public let name: String
    public let base: String
    public let created: String
    public let ip: String?

    public init(name: String, base: String, created: String, ip: String?) {
        self.name = name
        self.base = base
        self.created = created
        self.ip = ip
    }
}

public struct VMAcquireOutput: Codable {
    public let success: Bool
    public let name: String
    public let base: String
    public let created: String
    public let ip: String?

    public init(success: Bool, name: String, base: String, created: String, ip: String?) {
        self.success = success
        self.name = name
        self.base = base
        self.created = created
        self.ip = ip
    }
}

public struct VMReleaseOutput: Codable {
    public let success: Bool
    public let name: String

    public init(success: Bool, name: String) {
        self.success = success
        self.name = name
    }
}

public struct VMBakeOutput: Codable {
    public let success: Bool
    public let name: String
    public let source: String

    public init(success: Bool, name: String, source: String) {
        self.success = success
        self.name = name
        self.source = source
    }
}

public struct VMReleaseAllOutput: Codable {
    public let success: Bool
    public let released: Int
    public let failed: Int

    public init(success: Bool, released: Int, failed: Int) {
        self.success = success
        self.released = released
        self.failed = failed
    }
}

public struct VMListOutput: Codable {
    public let success: Bool
    public let vms: [VMInfo]

    public init(success: Bool, vms: [VMInfo]) {
        self.success = success
        self.vms = vms
    }
}

// MARK: - SetValueOutput

public struct SetValueOutput: Codable {
    public let success: Bool
    public let previousValue: String?
    public let newValue: String?

    public init(success: Bool, previousValue: String?, newValue: String?) {
        self.success = success
        self.previousValue = previousValue
        self.newValue = newValue
    }
}

// MARK: - Doctor Output

public enum DoctorStatus: String, Codable {
    case ok
    case warn
    case fail
}

public struct DoctorCheck: Codable {
    public let name: String
    public let status: DoctorStatus
    public let message: String
    public let fix_hint: String?

    public init(name: String, status: DoctorStatus, message: String, fix_hint: String?) {
        self.name = name
        self.status = status
        self.message = message
        self.fix_hint = fix_hint
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(status, forKey: .status)
        try c.encode(message, forKey: .message)
        if let fix_hint = fix_hint { try c.encode(fix_hint, forKey: .fix_hint) }
    }

    enum CodingKeys: String, CodingKey {
        case name, status, message, fix_hint
    }
}

public struct DoctorOutput: Codable {
    public let ready: Bool
    public let checks: [DoctorCheck]

    public init(ready: Bool, checks: [DoctorCheck]) {
        self.ready = ready
        self.checks = checks
    }
}

// MARK: - Assert / Exists / WaitReady Output

public struct AssertFailure: Codable {
    public let assertion: String
    public let expected: String
    public let actual: String

    public init(assertion: String, expected: String, actual: String) {
        self.assertion = assertion
        self.expected = expected
        self.actual = actual
    }
}

public struct AssertOutput: Codable {
    public let success: Bool
    public let passed: Bool
    public let element: ElementInfo
    public let failures: [AssertFailure]

    public init(success: Bool, passed: Bool, element: ElementInfo, failures: [AssertFailure]) {
        self.success = success
        self.passed = passed
        self.element = element
        self.failures = failures
    }
}

public struct ExistsOutput: Codable {
    public let success: Bool
    public let exists: Bool
    public let count: Int

    public init(success: Bool, exists: Bool, count: Int) {
        self.success = success
        self.exists = exists
        self.count = count
    }
}

public struct WaitReadyOutput: Codable {
    public let success: Bool
    public let elapsed_ms: Int

    public init(success: Bool, elapsed_ms: Int) {
        self.success = success
        self.elapsed_ms = elapsed_ms
    }
}

// MARK: - Error Output

public struct ErrorOutput: Codable {
    public let error: String
    public let message: String
    public let available: [String]?

    public init(error: String, message: String, available: [String]?) {
        self.error = error
        self.message = message
        self.available = available
    }
}

// MARK: - JSON Helpers

public let jsonEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}()

public func printJSON<T: Encodable>(_ value: T) {
    guard let data = try? jsonEncoder.encode(value) else {
        printError(code: "encoding_error", message: "Failed to encode output as JSON")
        return
    }
    print(String(data: data, encoding: .utf8)!)
}

public func printError(code: String, message: String, available: [String]? = nil) {
    let err = ErrorOutput(error: code, message: message, available: available)
    if let data = try? jsonEncoder.encode(err) {
        FileHandle.standardError.write(data)
        FileHandle.standardError.write("\n".data(using: .utf8)!)
    }
}
