import Foundation

// MARK: - Command Classification

public enum CommandClass: Equatable {
    case vmRoutable
    case alwaysLocal
}

// Must mirror every UI-driving case handled by main.swift's command switch.
// When you add a new UI command there, add its name here too — and a test in
// RouterClassifyTests.testVMRoutableCommands.
private let vmRoutableCommands: Set<String> = [
    "list", "launch", "tree", "click", "double-click", "right-click",
    "hover", "drag", "type", "key", "scroll", "screenshot", "activate",
    "close", "wait", "get-value", "focused", "window-info", "menu",
    "set-value", "move-resize", "clipboard", "wait-ready", "wait-for-value",
    "assert", "exists",
]

public func classifyCommand(_ command: String) -> CommandClass {
    vmRoutableCommands.contains(command) ? .vmRoutable : .alwaysLocal
}

// MARK: - Routing Target

public enum Target: Equatable {
    case local
    case remote(VMEntry)

    public static func == (lhs: Target, rhs: Target) -> Bool {
        switch (lhs, rhs) {
        case (.local, .local): return true
        case let (.remote(a), .remote(b)): return a.name == b.name
        default: return false
        }
    }
}

// MARK: - Router Errors

public enum RouterError: Error, Equatable {
    case noBaseRegistered(bundleID: String)
    case missingTarget(command: String)
    case bundleIDNotResolvable(appName: String)
    case vmNotFound(name: String)
    case vmNotReady(name: String)
    case sshFailed(stderr: String, exitCode: Int32)
}

// MARK: - VM Acquirer (test seam)

public protocol VMAcquirer {
    func acquire(base: String, headless: Bool, timeout: Int) -> Result<VMEntry, VMError>
}

public struct LiveVMAcquirer: VMAcquirer {
    public init() {}
    public func acquire(base: String, headless: Bool, timeout: Int) -> Result<VMEntry, VMError> {
        vmAcquire(base: base, headless: headless, timeout: timeout)
    }
}

// MARK: - Argv option helper (router-internal)

private func optionValue(_ argv: [String], _ name: String) -> String? {
    guard let i = argv.firstIndex(of: "--\(name)"), i + 1 < argv.count else { return nil }
    return argv[i + 1]
}

private func hasFlag(_ argv: [String], _ name: String) -> Bool {
    argv.contains("--\(name)")
}

// MARK: - resolveTarget

public func resolveTarget(
    argv: [String],
    command: String,
    registry: VMRegistry,
    env: [String: String],
    acquirer: VMAcquirer
) throws -> Target {
    // 1. Explicit --local always wins.
    if hasFlag(argv, "local") {
        return .local
    }
    // 2. AXON_TARGET=local env.
    if env["AXON_TARGET"] == "local" {
        return .local
    }
    // 3. --vm <name> targets a specific registered VM.
    if let vmName = optionValue(argv, "vm") {
        guard let entry = registry.vms.first(where: { $0.name == vmName }) else {
            throw RouterError.vmNotFound(name: vmName)
        }
        guard entry.ip != nil else {
            throw RouterError.vmNotReady(name: vmName)
        }
        return .remote(entry)
    }
    // (later tasks add --app and --bundle-id resolution + acquire path)
    throw RouterError.missingTarget(command: command)
}
