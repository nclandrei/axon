import Foundation
import ApplicationServices
import CoreGraphics

/// Pure, dependency-injected doctor runner. The real entrypoint
/// (`runDoctorLive()`, added in a later task) gathers machine state and calls this.
///
/// `axTrusted`, `screenCaptureGranted`, `isAppleSilicon`, `tartInstalled` are
/// the raw facts we observe. `binarySignatureInfo` is the one-line output of
/// `codesign -dv` or nil if unavailable — informational.
public func runDoctor(
    axTrusted: Bool,
    screenCaptureGranted: Bool,
    isAppleSilicon: Bool,
    tartInstalled: Bool,
    binarySignatureInfo: String?
) -> DoctorOutput {
    var checks: [DoctorCheck] = []

    // Required: AX trust
    if axTrusted {
        checks.append(DoctorCheck(
            name: "accessibility",
            status: .ok,
            message: "axon is trusted for accessibility",
            fix_hint: nil
        ))
    } else {
        checks.append(DoctorCheck(
            name: "accessibility",
            status: .fail,
            message: "axon is not trusted for accessibility",
            fix_hint: "Open System Settings > Privacy & Security > Accessibility and enable your terminal (or axon)."
        ))
    }

    // Required: screen recording (needed for `axon screenshot`)
    if screenCaptureGranted {
        checks.append(DoctorCheck(
            name: "screen_recording",
            status: .ok,
            message: "Screen recording permission granted",
            fix_hint: nil
        ))
    } else {
        checks.append(DoctorCheck(
            name: "screen_recording",
            status: .fail,
            message: "Screen recording permission not granted",
            fix_hint: "Open System Settings > Privacy & Security > Screen Recording and enable your terminal (or axon)."
        ))
    }

    // Informational: architecture
    if isAppleSilicon {
        checks.append(DoctorCheck(
            name: "architecture",
            status: .ok,
            message: "Apple Silicon (arm64)",
            fix_hint: nil
        ))
    } else {
        checks.append(DoctorCheck(
            name: "architecture",
            status: .warn,
            message: "Intel (x86_64). Tart VMs require Apple Silicon.",
            fix_hint: nil
        ))
    }

    // Informational: Tart presence (required only for vm-* commands)
    if tartInstalled {
        checks.append(DoctorCheck(
            name: "tart",
            status: .ok,
            message: "Tart CLI found",
            fix_hint: nil
        ))
    } else {
        checks.append(DoctorCheck(
            name: "tart",
            status: .warn,
            message: "Tart not installed (only needed for vm-* commands)",
            fix_hint: "brew install cirruslabs/cli/tart"
        ))
    }

    // Informational: binary signature
    if let info = binarySignatureInfo, info.contains("Developer ID") {
        checks.append(DoctorCheck(
            name: "binary_signature",
            status: .ok,
            message: "axon binary signed with Developer ID (\(info))",
            fix_hint: nil
        ))
    } else {
        checks.append(DoctorCheck(
            name: "binary_signature",
            status: .warn,
            message: "axon binary is unsigned or signature unreadable",
            fix_hint: nil
        ))
    }

    // Ready = no required checks failed. "warn" is informational and never affects ready.
    let ready = !checks.contains(where: { $0.status == .fail })
    return DoctorOutput(ready: ready, checks: checks)
}
