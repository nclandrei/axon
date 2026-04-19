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
}
