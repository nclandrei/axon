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

    let ready = checks.allSatisfy { $0.status != .fail }
    return DoctorOutput(ready: ready, checks: checks)
}
