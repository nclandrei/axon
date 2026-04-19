import Foundation
import ApplicationServices
import CoreGraphics

/// Pure, dependency-injected doctor runner.
public func runDoctor(
    axTrusted: Bool,
    screenCaptureGranted: Bool,
    isAppleSilicon: Bool,
    tartInstalled: Bool,
    binarySignatureInfo: String?
) -> DoctorOutput {
    let checks: [DoctorCheck] = [
        binaryCheck(
            name: "accessibility",
            ok: axTrusted,
            okMessage: "axon is trusted for accessibility",
            failMessage: "axon is not trusted for accessibility",
            failHint: "Open System Settings > Privacy & Security > Accessibility and enable your terminal (or axon)."
        ),
        binaryCheck(
            name: "screen_recording",
            ok: screenCaptureGranted,
            okMessage: "Screen recording permission granted",
            failMessage: "Screen recording permission not granted",
            failHint: "Open System Settings > Privacy & Security > Screen Recording and enable your terminal (or axon)."
        ),
        binaryCheck(
            name: "architecture",
            ok: isAppleSilicon,
            okMessage: "Apple Silicon (arm64)",
            warnMessage: "Intel (x86_64). Tart VMs require Apple Silicon.",
            informational: true
        ),
        binaryCheck(
            name: "tart",
            ok: tartInstalled,
            okMessage: "Tart CLI found",
            warnMessage: "Tart not installed (only needed for vm-* commands)",
            warnHint: "brew install cirruslabs/cli/tart",
            informational: true
        ),
        signatureCheck(info: binarySignatureInfo),
    ]

    let ready = !checks.contains(where: { $0.status == .fail })
    return DoctorOutput(ready: ready, checks: checks)
}

/// A two-state check that is either required (fail on false) or informational (warn on false).
private func binaryCheck(
    name: String,
    ok: Bool,
    okMessage: String,
    failMessage: String = "",
    failHint: String? = nil,
    warnMessage: String = "",
    warnHint: String? = nil,
    informational: Bool = false
) -> DoctorCheck {
    if ok {
        return DoctorCheck(name: name, status: .ok, message: okMessage, fix_hint: nil)
    }
    if informational {
        return DoctorCheck(name: name, status: .warn, message: warnMessage, fix_hint: warnHint)
    }
    return DoctorCheck(name: name, status: .fail, message: failMessage, fix_hint: failHint)
}

/// Signature check has its own shape because the message includes the authority string.
private func signatureCheck(info: String?) -> DoctorCheck {
    if let info = info, info.contains("Developer ID") {
        return DoctorCheck(
            name: "binary_signature",
            status: .ok,
            message: "axon binary signed with Developer ID (\(info))",
            fix_hint: nil
        )
    }
    return DoctorCheck(
        name: "binary_signature",
        status: .warn,
        message: "axon binary is unsigned or signature unreadable",
        fix_hint: nil
    )
}

/// Live entrypoint used by `axon doctor`. Probes actual system state and delegates to `runDoctor`.
public func runDoctorLive() -> DoctorOutput {
    return runDoctor(
        axTrusted: AXIsProcessTrusted(),
        screenCaptureGranted: CGPreflightScreenCaptureAccess(),
        isAppleSilicon: isAppleSiliconArchitecture(),
        tartInstalled: isTartOnPath(),
        binarySignatureInfo: binarySignatureOfRunningProcess()
    )
}

private func isAppleSiliconArchitecture() -> Bool {
    #if arch(arm64)
    return true
    #else
    return false
    #endif
}

private func isTartOnPath() -> Bool {
    let task = Process()
    task.launchPath = "/usr/bin/env"
    task.arguments = ["which", "tart"]
    task.standardOutput = Pipe()
    task.standardError = Pipe()
    do {
        try task.run()
    } catch {
        return false
    }
    task.waitUntilExit()
    return task.terminationStatus == 0
}

private func binarySignatureOfRunningProcess() -> String? {
    guard let path = Bundle.main.executablePath ?? CommandLine.arguments.first else { return nil }
    let task = Process()
    task.launchPath = "/usr/bin/codesign"
    task.arguments = ["-dvv", path]
    let err = Pipe()
    task.standardError = err
    task.standardOutput = Pipe()
    do {
        try task.run()
    } catch {
        return nil
    }
    task.waitUntilExit()
    guard task.terminationStatus == 0 else { return nil }
    let data = err.fileHandleForReading.readDataToEndOfFile()
    guard let text = String(data: data, encoding: .utf8) else { return nil }
    return text
        .split(separator: "\n")
        .first(where: { $0.hasPrefix("Authority=") })
        .map(String.init)
}
