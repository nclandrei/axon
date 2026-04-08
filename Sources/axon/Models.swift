import Foundation

// MARK: - Output Models

/// Represents a node in the accessibility tree
struct AXNode: Codable {
    let role: String?
    let subrole: String?
    let title: String?
    let identifier: String?
    let label: String?
    let value: String?
    let enabled: Bool?
    let focused: Bool?
    let position: AXPoint?
    let size: AXSize?
    let path: String
    let children: [AXNode]?

    /// Returns a compact version with null fields and position/size omitted
    func compacted() -> CompactAXNode {
        CompactAXNode(
            role: role,
            subrole: subrole,
            title: title,
            identifier: identifier,
            label: label,
            value: value,
            enabled: enabled,
            focused: focused,
            path: path,
            children: children?.map { $0.compacted() }
        )
    }
}

struct CompactAXNode: Codable {
    let role: String?
    let subrole: String?
    let title: String?
    let identifier: String?
    let label: String?
    let value: String?
    let enabled: Bool?
    let focused: Bool?
    let path: String
    let children: [CompactAXNode]?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let role = role { try container.encode(role, forKey: .role) }
        if let subrole = subrole { try container.encode(subrole, forKey: .subrole) }
        if let title = title { try container.encode(title, forKey: .title) }
        if let identifier = identifier { try container.encode(identifier, forKey: .identifier) }
        if let label = label { try container.encode(label, forKey: .label) }
        if let value = value { try container.encode(value, forKey: .value) }
        if let enabled = enabled { try container.encode(enabled, forKey: .enabled) }
        if let focused = focused { try container.encode(focused, forKey: .focused) }
        try container.encode(path, forKey: .path)
        if let children = children, !children.isEmpty {
            try container.encode(children, forKey: .children)
        }
    }

    enum CodingKeys: String, CodingKey {
        case role, subrole, title, identifier, label, value, enabled, focused, path, children
    }
}

struct AXPoint: Codable {
    let x: Double
    let y: Double
}

struct AXSize: Codable {
    let width: Double
    let height: Double
}

// MARK: - App Info

struct AppInfo: Codable {
    let name: String
    let bundleID: String?
    let pid: Int32
}

// MARK: - Command Output Models

struct ListOutput: Codable {
    let apps: [AppInfo]
}

struct TreeOutput: Codable {
    let app: String
    let pid: Int32
    let tree: AXNode
}

struct CompactTreeOutput: Codable {
    let app: String
    let pid: Int32
    let tree: CompactAXNode
}

struct ClickOutput: Codable {
    let success: Bool
    let element: ElementInfo
}

struct TypeOutput: Codable {
    let success: Bool
    let method: String
}

struct ScrollOutput: Codable {
    let success: Bool
}

struct ScreenshotOutput: Codable {
    let success: Bool
    let path: String
    let width: Int
    let height: Int
}

struct ActivateOutput: Codable {
    let success: Bool
}

struct LaunchOutput: Codable {
    let success: Bool
    let name: String
    let bundleID: String?
    let pid: Int32
}

struct CloseOutput: Codable {
    let success: Bool
    let action: String // "quit" or "close_window"
}

struct WaitOutput: Codable {
    let success: Bool
    let elapsed_ms: Int
}

struct ElementInfo: Codable {
    let role: String?
    let title: String?
    let identifier: String?
}

// MARK: - Error Output

struct ErrorOutput: Codable {
    let error: String
    let message: String
    let available: [String]?
}

// MARK: - JSON Helpers

let jsonEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}()

func printJSON<T: Encodable>(_ value: T) {
    guard let data = try? jsonEncoder.encode(value) else {
        printError(code: "encoding_error", message: "Failed to encode output as JSON")
        return
    }
    print(String(data: data, encoding: .utf8)!)
}

func printError(code: String, message: String, available: [String]? = nil) {
    let err = ErrorOutput(error: code, message: message, available: available)
    if let data = try? jsonEncoder.encode(err) {
        FileHandle.standardError.write(data)
        FileHandle.standardError.write("\n".data(using: .utf8)!)
    }
}
