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
    case vmAcquireFailed(message: String)
    case outputTransferFailed(message: String)
}

// MARK: - Bundle ID Resolver (test seam)

public protocol BundleIDResolver {
    func bundleID(forAppName name: String) -> String?
}

public struct LiveBundleIDResolver: BundleIDResolver {
    public init() {}
    public func bundleID(forAppName name: String) -> String? {
        findApp(name: name)?.bundleIdentifier
    }
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
    acquirer: VMAcquirer,
    bundleIDResolver: BundleIDResolver = LiveBundleIDResolver()
) throws -> Target {
    if hasFlag(argv, "local") { return .local }
    if env["AXON_TARGET"] == "local" { return .local }

    if let vmName = optionValue(argv, "vm") {
        guard let entry = registry.vms.first(where: { $0.name == vmName }) else {
            throw RouterError.vmNotFound(name: vmName)
        }
        guard entry.ip != nil else { throw RouterError.vmNotReady(name: vmName) }
        return .remote(entry)
    }

    // Resolve bundle ID from --bundle-id (preferred) or --app via two-step lookup.
    let bundleID: String
    if let bid = optionValue(argv, "bundle-id") {
        bundleID = bid
    } else if let appName = optionValue(argv, "app") {
        if let registryHit = registry.bases.first(where: {
            $0.displayName?.localizedCaseInsensitiveCompare(appName) == .orderedSame
        }) {
            bundleID = registryHit.bundleID
        } else if let host = bundleIDResolver.bundleID(forAppName: appName) {
            bundleID = host
        } else {
            throw RouterError.bundleIDNotResolvable(appName: appName)
        }
    } else {
        throw RouterError.missingTarget(command: command)
    }

    guard let base = findBase(byBundleID: bundleID, in: registry) else {
        throw RouterError.noBaseRegistered(bundleID: bundleID)
    }

    if let running = registry.vms.first(where: { $0.base == base.name && $0.ip != nil }) {
        return .remote(running)
    }
    switch acquirer.acquire(base: base.name, headless: true, timeout: 60) {
    case .success(let entry):
        return .remote(entry)
    case .failure(let err):
        throw RouterError.vmAcquireFailed(message: err.description)
    }
}

// MARK: - File-output remap

public struct ScpBack: Equatable {
    public let vmPath: String
    public let hostPath: String
    public init(vmPath: String, hostPath: String) {
        self.vmPath = vmPath
        self.hostPath = hostPath
    }
}

public func remapFileOutputs(
    argv: [String],
    command: String,
    tempPathProvider: () -> String = { "/tmp/axon-out-\(UUID().uuidString).bin" }
) -> (rewritten: [String], scpBacks: [ScpBack]) {
    guard command == "screenshot" else { return (argv, []) }
    guard let outputIdx = argv.firstIndex(of: "--output"), outputIdx + 1 < argv.count else {
        return (argv, [])
    }
    let hostPath = argv[outputIdx + 1]
    let vmPath = tempPathProvider()
    var rewritten = argv
    rewritten[outputIdx + 1] = vmPath
    return (rewritten, [ScpBack(vmPath: vmPath, hostPath: hostPath)])
}

// MARK: - SSH / SCP Dispatch (test seams)

public protocol SSHDispatcher {
    func run(vmIP: String, argv: [String], env: [String: String])
        -> (stdout: Data, stderr: Data, exitCode: Int32)
}

public protocol ScpBackRunner {
    func transfer(_ scpBack: ScpBack, fromVMIP ip: String) -> Result<Void, VMError>
}

public func dispatchRemote(
    vm: VMEntry,
    argv: [String],
    scpBacks: [ScpBack],
    ssh: SSHDispatcher,
    scpRunner: ScpBackRunner
) throws -> (stdout: Data, stderr: Data, exitCode: Int32) {
    guard let ip = vm.ip else { throw RouterError.vmNotReady(name: vm.name) }
    let env = ["AXON_TARGET": "local"]
    let result = ssh.run(vmIP: ip, argv: argv, env: env)
    if result.exitCode == 0 {
        for back in scpBacks {
            switch scpRunner.transfer(back, fromVMIP: ip) {
            case .success: continue
            case .failure(let err):
                throw RouterError.outputTransferFailed(message: err.description)
            }
        }
    }
    return result
}
