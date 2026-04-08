import Foundation

// MARK: - CLI Argument Parsing

/// Simple argument parser — no external dependencies
public struct CLI {
    public let args: [String]
    public let command: String?

    public init() {
        let all = CommandLine.arguments
        self.args = Array(all.dropFirst()) // drop executable path
        self.command = self.args.first
    }

    public init(args: [String]) {
        self.args = args
        self.command = self.args.first
    }

    public func flag(_ name: String) -> Bool {
        args.contains("--\(name)")
    }

    public func hasHelp() -> Bool {
        args.contains("--help") || args.contains("-h")
    }

    public func option(_ name: String) -> String? {
        guard let idx = args.firstIndex(of: "--\(name)"), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    public func intOption(_ name: String, default defaultValue: Int) -> Int {
        guard let val = option(name), let num = Int(val) else { return defaultValue }
        return num
    }

    public func requireOption(_ name: String) -> String {
        guard let val = option(name) else {
            printError(code: "missing_option", message: "--\(name) is required")
            exit(1)
        }
        return val
    }
}
