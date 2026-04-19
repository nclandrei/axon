import Foundation
import XCTest

/// Shared setup/teardown for E2E tests that drive AxonSample.app.
class AxonSampleE2ETestCase: AxonE2ETestCase {
    /// Absolute path to the built sample app bundle.
    static var samplePath: String {
        Self.projectRoot
            .appendingPathComponent("Samples/AxonSample/.build/AxonSample.app")
            .path
    }

    /// Skip the current test if the sample hasn't been built.
    func skipIfSampleNotBuilt() throws {
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: Self.samplePath),
            "AxonSample.app not built — run `make -C Samples/AxonSample build`"
        )
    }

    /// Launch the sample app and wait for its UI to be ready.
    @discardableResult
    func launchSample() throws -> (stdout: String, stderr: String, exitCode: Int32) {
        let launch = runAxon(["launch", "--path", Self.samplePath])
        try skipIfNoAccessibility(launch)
        XCTAssertEqual(launch.exitCode, 0, "launch failed: \(launch.stderr)")

        let ready = runAxon(["wait-ready", "--app", "AxonSample", "--timeout", "5"])
        XCTAssertEqual(ready.exitCode, 0, "wait-ready failed: \(ready.stderr)")

        return launch
    }

    /// Quit the sample app unconditionally. Safe to call in teardown even if never launched.
    func quitSample() {
        _ = runAxon(["close", "--app", "AxonSample", "--quit"])
    }
}
