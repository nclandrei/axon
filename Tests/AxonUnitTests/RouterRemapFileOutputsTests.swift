import XCTest
@testable import AxonLib

final class RouterRemapFileOutputsTests: XCTestCase {

    func testNoOutputFlagLeavesArgvUnchanged() {
        let argv = ["screenshot", "--app", "Finder"]
        let (rewritten, scps) = remapFileOutputs(argv: argv, command: "screenshot", tempPathProvider: { "/tmp/X" })
        XCTAssertEqual(rewritten, argv)
        XCTAssertTrue(scps.isEmpty)
    }

    func testScreenshotOutputIsRewrittenAndRecorded() {
        let argv = ["screenshot", "--app", "Finder", "--output", "/Users/me/shot.png"]
        let (rewritten, scps) = remapFileOutputs(
            argv: argv,
            command: "screenshot",
            tempPathProvider: { "/tmp/axon-out-fixed.png" }
        )
        XCTAssertEqual(rewritten, ["screenshot", "--app", "Finder", "--output", "/tmp/axon-out-fixed.png"])
        XCTAssertEqual(scps.count, 1)
        XCTAssertEqual(scps[0].vmPath, "/tmp/axon-out-fixed.png")
        XCTAssertEqual(scps[0].hostPath, "/Users/me/shot.png")
    }

    func testNonScreenshotCommandsIgnoreOutputFlag() {
        // Only `screenshot` opts in to the remap today.
        let argv = ["tree", "--app", "Finder", "--output", "/tmp/x.json"]
        let (rewritten, scps) = remapFileOutputs(argv: argv, command: "tree", tempPathProvider: { "/tmp/X" })
        XCTAssertEqual(rewritten, argv)
        XCTAssertTrue(scps.isEmpty)
    }

    func testOutputFlagWithoutValueIsLeftAlone() {
        let argv = ["screenshot", "--app", "Finder", "--output"]
        let (rewritten, scps) = remapFileOutputs(argv: argv, command: "screenshot", tempPathProvider: { "/tmp/X" })
        XCTAssertEqual(rewritten, argv)
        XCTAssertTrue(scps.isEmpty)
    }
}
