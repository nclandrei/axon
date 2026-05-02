import Foundation

/// Production SSHDispatcher. Uses `/usr/bin/ssh`. Caller is responsible for
/// having SSH keys configured for `admin@<vm-ip>`.
public struct LiveSSHDispatcher: SSHDispatcher {
    public init() {}

    public func run(vmIP: String, argv: [String], env: [String: String])
        -> (stdout: Data, stderr: Data, exitCode: Int32)
    {
        // Build remote command: `ENV1=v1 ENV2=v2 axon arg1 arg2 ...`
        // Single-quote escaping keeps things simple; admin@ip is the convention.
        let envParts = env.map { "\($0.key)=\(shellQuote($0.value))" }
        let cmdParts = ["axon"] + argv.map(shellQuote)
        let remote = (envParts + cmdParts).joined(separator: " ")
        return runProcess(
            executable: "/usr/bin/ssh",
            args: ["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=no", "admin@\(vmIP)", remote]
        )
    }
}

/// Production ScpBackRunner. Uses `/usr/bin/scp`.
public struct LiveScpBackRunner: ScpBackRunner {
    public init() {}

    public func transfer(_ scpBack: ScpBack, fromVMIP ip: String) -> Result<Void, VMError> {
        let result = runProcess(
            executable: "/usr/bin/scp",
            args: ["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=no",
                   "admin@\(ip):\(scpBack.vmPath)", scpBack.hostPath]
        )
        if result.exitCode != 0 {
            let msg = String(data: result.stderr, encoding: .utf8) ?? "scp failed"
            return .failure(VMError(msg))
        }
        // Best-effort cleanup of VM-side temp file.
        _ = runProcess(
            executable: "/usr/bin/ssh",
            args: ["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=no",
                   "admin@\(ip)", "rm -f \(shellQuote(scpBack.vmPath))"]
        )
        return .success(())
    }
}

private func runProcess(executable: String, args: [String])
    -> (stdout: Data, stderr: Data, exitCode: Int32)
{
    let p = Process()
    p.executableURL = URL(fileURLWithPath: executable)
    p.arguments = args
    let outPipe = Pipe()
    let errPipe = Pipe()
    p.standardOutput = outPipe
    p.standardError = errPipe
    do { try p.run() } catch {
        return (Data(), Data("\(error)".utf8), 127)
    }
    p.waitUntilExit()
    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
    return (outData, errData, p.terminationStatus)
}

/// Single-quote a string for safe inclusion in a remote shell command.
private func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
