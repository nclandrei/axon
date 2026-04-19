import XCTest
@testable import AxonLib

final class DiagnosticsTests: XCTestCase {

    // MARK: - AX trust check

    func testRunDoctorIncludesAccessibilityCheck() {
        let output = runDoctor(axTrusted: false, screenCaptureGranted: false, isAppleSilicon: true, tartInstalled: false, binarySignatureInfo: nil)
        XCTAssertTrue(output.checks.contains { $0.name == "accessibility" })
    }

    func testAccessibilityCheckFailsWhenUntrusted() {
        let output = runDoctor(axTrusted: false, screenCaptureGranted: true, isAppleSilicon: true, tartInstalled: true, binarySignatureInfo: nil)
        let ax = output.checks.first(where: { $0.name == "accessibility" })
        XCTAssertEqual(ax?.status, .fail)
        XCTAssertNotNil(ax?.fix_hint)
        XCTAssertTrue(ax?.fix_hint?.contains("Privacy & Security") ?? false)
    }

    func testAccessibilityCheckPassesWhenTrusted() {
        let output = runDoctor(axTrusted: true, screenCaptureGranted: true, isAppleSilicon: true, tartInstalled: true, binarySignatureInfo: nil)
        let ax = output.checks.first(where: { $0.name == "accessibility" })
        XCTAssertEqual(ax?.status, .ok)
        XCTAssertNil(ax?.fix_hint)
    }

    func testReadyIsFalseWhenAnyRequiredCheckFails() {
        let output = runDoctor(axTrusted: false, screenCaptureGranted: true, isAppleSilicon: true, tartInstalled: true, binarySignatureInfo: nil)
        XCTAssertFalse(output.ready)
    }

    func testReadyIsTrueWhenAllRequiredPass() {
        let output = runDoctor(axTrusted: true, screenCaptureGranted: true, isAppleSilicon: true, tartInstalled: true, binarySignatureInfo: nil)
        XCTAssertTrue(output.ready)
    }

    // MARK: - Screen recording check

    func testScreenRecordingCheckIncluded() {
        let output = runDoctor(axTrusted: true, screenCaptureGranted: true, isAppleSilicon: true, tartInstalled: true, binarySignatureInfo: nil)
        XCTAssertTrue(output.checks.contains { $0.name == "screen_recording" })
    }

    func testScreenRecordingCheckFailsWhenNotGranted() {
        let output = runDoctor(axTrusted: true, screenCaptureGranted: false, isAppleSilicon: true, tartInstalled: true, binarySignatureInfo: nil)
        let sr = output.checks.first(where: { $0.name == "screen_recording" })
        XCTAssertEqual(sr?.status, .fail)
        XCTAssertTrue(sr?.fix_hint?.contains("Screen") ?? false)
    }

    func testScreenRecordingCheckPassesWhenGranted() {
        let output = runDoctor(axTrusted: true, screenCaptureGranted: true, isAppleSilicon: true, tartInstalled: true, binarySignatureInfo: nil)
        let sr = output.checks.first(where: { $0.name == "screen_recording" })
        XCTAssertEqual(sr?.status, .ok)
    }

    func testReadyFalseWhenScreenRecordingMissing() {
        let output = runDoctor(axTrusted: true, screenCaptureGranted: false, isAppleSilicon: true, tartInstalled: true, binarySignatureInfo: nil)
        XCTAssertFalse(output.ready)
    }

    // MARK: - Informational checks

    func testArchitectureCheckIncluded() {
        let output = runDoctor(axTrusted: true, screenCaptureGranted: true, isAppleSilicon: true, tartInstalled: true, binarySignatureInfo: nil)
        let arch = output.checks.first(where: { $0.name == "architecture" })
        XCTAssertNotNil(arch)
        XCTAssertEqual(arch?.status, .ok)
        XCTAssertTrue(arch?.message.contains("Apple Silicon") ?? false)
    }

    func testArchitectureCheckOnIntel() {
        let output = runDoctor(axTrusted: true, screenCaptureGranted: true, isAppleSilicon: false, tartInstalled: true, binarySignatureInfo: nil)
        let arch = output.checks.first(where: { $0.name == "architecture" })
        XCTAssertEqual(arch?.status, .warn)
        XCTAssertTrue(arch?.message.contains("Intel") ?? false)
    }

    func testTartCheckWhenPresent() {
        let output = runDoctor(axTrusted: true, screenCaptureGranted: true, isAppleSilicon: true, tartInstalled: true, binarySignatureInfo: nil)
        let tart = output.checks.first(where: { $0.name == "tart" })
        XCTAssertEqual(tart?.status, .ok)
    }

    func testTartCheckWhenAbsent() {
        let output = runDoctor(axTrusted: true, screenCaptureGranted: true, isAppleSilicon: true, tartInstalled: false, binarySignatureInfo: nil)
        let tart = output.checks.first(where: { $0.name == "tart" })
        XCTAssertEqual(tart?.status, .warn)
        XCTAssertTrue(tart?.fix_hint?.contains("tart") ?? false)
    }

    func testBinarySignatureCheckWhenPresent() {
        let output = runDoctor(axTrusted: true, screenCaptureGranted: true, isAppleSilicon: true, tartInstalled: true, binarySignatureInfo: "Authority=Developer ID Application: X")
        let sig = output.checks.first(where: { $0.name == "binary_signature" })
        XCTAssertEqual(sig?.status, .ok)
        XCTAssertTrue(sig?.message.contains("Developer ID") ?? false)
    }

    func testBinarySignatureCheckWhenAbsent() {
        let output = runDoctor(axTrusted: true, screenCaptureGranted: true, isAppleSilicon: true, tartInstalled: true, binarySignatureInfo: nil)
        let sig = output.checks.first(where: { $0.name == "binary_signature" })
        XCTAssertEqual(sig?.status, .warn)
    }

    func testInformationalWarnDoesNotAffectReady() {
        let output = runDoctor(axTrusted: true, screenCaptureGranted: true, isAppleSilicon: false, tartInstalled: false, binarySignatureInfo: nil)
        XCTAssertTrue(output.ready, "ready should be true when only informational checks warn")
    }

    // MARK: - Live probe

    func testRunDoctorLiveReturnsWellFormedOutput() {
        let output = runDoctorLive()
        XCTAssertFalse(output.checks.isEmpty)
        let names = Set(output.checks.map(\.name))
        XCTAssertTrue(names.contains("accessibility"))
        XCTAssertTrue(names.contains("screen_recording"))
        XCTAssertTrue(names.contains("architecture"))
        XCTAssertTrue(names.contains("tart"))
        XCTAssertTrue(names.contains("binary_signature"))
    }
}
