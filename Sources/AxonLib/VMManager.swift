import Foundation

// MARK: - VM Error

public struct VMError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) {
        self.description = description
    }
}

// MARK: - VM Configuration

private let registryDirURL: URL = {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".axon")
}()

private let registryFileURL: URL = {
    registryDirURL.appendingPathComponent("vms.json")
}()

/// Default location of the VM registry file (`~/.axon/vms.json`).
public var defaultVMRegistryURL: URL { registryFileURL }

// MARK: - VM Registry Model

public struct VMEntry: Codable {
    public let name: String
    public let base: String
    public let created: Date
    public var ip: String?

    public init(name: String, base: String, created: Date, ip: String?) {
        self.name = name
        self.base = base
        self.created = created
        self.ip = ip
    }
}

public struct VMRegistry: Codable {
    public var vms: [VMEntry]

    public init(vms: [VMEntry]) {
        self.vms = vms
    }
}

// MARK: - Shell Execution

private func findTart() -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["which", "tart"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return nil
    }
    guard process.terminationStatus == 0 else { return nil }
    let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return (path?.isEmpty == false) ? path : nil
}

private func runTart(_ args: [String]) -> (stdout: String, stderr: String, exitCode: Int32) {
    guard let tartPath = findTart() else {
        return ("", "tart not found. Install with: brew install cirruslabs/cli/tart", 1)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: tartPath)
    process.arguments = args

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return ("", "Failed to run tart: \(error.localizedDescription)", 1)
    }

    let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    return (stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            stderr.trimmingCharacters(in: .whitespacesAndNewlines),
            process.terminationStatus)
}

// MARK: - Registry Operations

/// Loads a VM registry from the given URL. Returns an empty registry when the
/// file is missing or unreadable, mirroring the original behavior.
public func loadVMRegistry(at url: URL) -> VMRegistry {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let data = try? Data(contentsOf: url),
          let reg = try? decoder.decode(VMRegistry.self, from: data) else {
        return VMRegistry(vms: [])
    }
    return reg
}

/// Persists a VM registry to the given URL, creating any missing parent
/// directories. Throws on write/encode failure.
public func saveVMRegistry(_ registry: VMRegistry, to url: URL) throws {
    let parent = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(registry)
    try data.write(to: url, options: .atomic)
}

private func loadRegistry() -> VMRegistry {
    loadVMRegistry(at: registryFileURL)
}

private func saveRegistry(_ registry: VMRegistry) throws {
    try saveVMRegistry(registry, to: registryFileURL)
}

private func withRegistryLock<T>(_ body: (inout VMRegistry) throws -> T) throws -> T {
    try FileManager.default.createDirectory(at: registryDirURL, withIntermediateDirectories: true)
    let lockPath = registryDirURL.appendingPathComponent("vms.lock").path
    FileManager.default.createFile(atPath: lockPath, contents: nil)
    let fd = open(lockPath, O_RDWR)
    guard fd >= 0 else {
        throw VMError("Failed to open lock file")
    }
    defer { close(fd) }

    guard flock(fd, LOCK_EX) == 0 else {
        throw VMError("Failed to acquire registry lock")
    }
    defer { flock(fd, LOCK_UN) }

    var registry = loadRegistry()
    let result = try body(&registry)
    try saveRegistry(registry)
    return result
}

// MARK: - Public VM Operations

/// Clone a fresh VM from a base image, boot it, wait for an IP, and return connection info.
public func vmAcquire(base: String, headless: Bool, timeout: Int) -> Result<VMEntry, VMError> {
    // 1. Verify tart is available
    guard findTart() != nil else {
        return .failure(VMError("tart not found. Install with: brew install cirruslabs/cli/tart"))
    }

    // 2. Generate unique name
    let suffix = String(UUID().uuidString.prefix(8)).lowercased()
    let vmName = "axon-\(suffix)"

    // 3. Clone from base (instant via APFS COW)
    let cloneResult = runTart(["clone", base, vmName])
    if cloneResult.exitCode != 0 {
        return .failure(VMError("Failed to clone '\(base)' -> '\(vmName)': \(cloneResult.stderr)"))
    }

    // 4. Start VM in background
    guard let tartPath = findTart() else {
        _ = runTart(["delete", vmName])
        return .failure(VMError("tart disappeared after clone"))
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: tartPath)
    var runArgs = ["run", vmName]
    if headless {
        runArgs += ["--no-graphics"]
    }
    process.arguments = runArgs
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
    } catch {
        _ = runTart(["delete", vmName])
        return .failure(VMError("Failed to start VM '\(vmName)': \(error.localizedDescription)"))
    }

    // 5. Wait for IP (poll `tart ip`)
    var ip: String?
    let startTime = Date()
    let timeoutInterval = TimeInterval(timeout)

    while Date().timeIntervalSince(startTime) < timeoutInterval {
        let ipResult = runTart(["ip", vmName])
        if ipResult.exitCode == 0, !ipResult.stdout.isEmpty {
            ip = ipResult.stdout
            break
        }
        usleep(1_000_000) // 1s between polls
    }

    guard let vmIP = ip else {
        _ = runTart(["stop", vmName])
        _ = runTart(["delete", vmName])
        return .failure(VMError(
            "Timed out waiting for VM '\(vmName)' IP address (\(timeout)s). "
            + "The base image may need a full boot -- try a longer --timeout."
        ))
    }

    // 6. Register in registry
    let entry = VMEntry(name: vmName, base: base, created: Date(), ip: vmIP)
    do {
        try withRegistryLock { registry in
            registry.vms.append(entry)
        }
    } catch {
        // Non-fatal: VM is running, just failed to register
    }

    return .success(entry)
}

/// Clone a stock Tart image into a persistent named base. The resulting VM is
/// stopped and not registered in `~/.axon/vms.json` -- the user is expected to
/// `tart run` it once to install their app and grant permissions, then
/// `tart stop` it. Subsequent `vmAcquire(base: name, ...)` calls clone from
/// this sealed base instantly via APFS COW.
public func vmBake(source: String, name: String) -> Result<(name: String, source: String), VMError> {
    guard findTart() != nil else {
        return .failure(VMError("tart not found. Install with: brew install cirruslabs/cli/tart"))
    }

    let cloneResult = runTart(["clone", source, name])
    if cloneResult.exitCode != 0 {
        return .failure(VMError("Failed to clone '\(source)' -> '\(name)': \(cloneResult.stderr)"))
    }

    return .success((name: name, source: source))
}

/// Stop and delete an ephemeral VM.
public func vmRelease(name: String) -> Result<Bool, VMError> {
    // Stop (ignore failure -- VM may already be stopped)
    _ = runTart(["stop", name])

    // Delete
    let deleteResult = runTart(["delete", name])
    if deleteResult.exitCode != 0 {
        return .failure(VMError("Failed to delete VM '\(name)': \(deleteResult.stderr)"))
    }

    // Remove from registry
    do {
        try withRegistryLock { registry in
            registry.vms.removeAll { $0.name == name }
        }
    } catch {
        // Non-fatal
    }

    return .success(true)
}

/// List all axon-managed VMs from the registry.
public func vmListEntries() -> [VMEntry] {
    loadRegistry().vms
}

/// List all VMs in a registry stored at the given URL. Used by tests to point
/// at a temp file instead of the real `~/.axon/vms.json`.
public func vmListEntries(at url: URL) -> [VMEntry] {
    loadVMRegistry(at: url).vms
}

/// Release all axon-managed VMs. Returns (released, failed) counts.
public func vmReleaseAll() -> (released: Int, failed: Int) {
    let registry = loadRegistry()
    var released = 0
    var failed = 0

    for vm in registry.vms {
        switch vmRelease(name: vm.name) {
        case .success: released += 1
        case .failure: failed += 1
        }
    }

    return (released, failed)
}
