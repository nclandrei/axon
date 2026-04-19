import Foundation
import XCTest

final class AxonSampleE2ETests: AxonSampleE2ETestCase {

    override func tearDown() {
        quitSample()
        super.tearDown()
    }

    // MARK: - 1. Launch smoke test

    func testSampleAppLaunchesAndIsReady() throws {
        try skipIfSampleNotBuilt()
        try launchSample()

        let tree = runAxon(["tree", "--app", "AxonSample", "--depth", "2", "--compact"])
        XCTAssertEqual(tree.exitCode, 0, "tree should succeed on a ready AxonSample")
        let json = parseJSON(tree.stdout)
        XCTAssertNotNil(json, "tree should produce valid JSON")
        XCTAssertNotNil(json?["tree"], "tree JSON should have a 'tree' key")
    }
}
