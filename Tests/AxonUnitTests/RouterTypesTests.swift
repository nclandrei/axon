import XCTest
@testable import AxonLib

final class RouterTypesTests: XCTestCase {

    func testTargetLocalEqualsLocal() {
        XCTAssertEqual(Target.local, Target.local)
    }

    func testTargetRemoteCarriesVMEntry() {
        let entry = VMEntry(name: "axon-x", base: "b", created: Date(), ip: "10.0.0.1")
        let t = Target.remote(entry)
        if case let .remote(e) = t {
            XCTAssertEqual(e.name, "axon-x")
        } else {
            XCTFail("Expected .remote")
        }
    }

    func testRouterErrorMessages() {
        // We just check the cases compile and we can pattern-match them.
        let errors: [RouterError] = [
            .noBaseRegistered(bundleID: "com.x.A"),
            .missingTarget(command: "list"),
            .bundleIDNotResolvable(appName: "Foo"),
            .vmNotFound(name: "axon-zzz"),
            .vmNotReady(name: "axon-zzz"),
            .vmAcquireFailed(message: "boom"),
            .outputTransferFailed(message: "boom"),
        ]
        XCTAssertEqual(errors.count, 7)
    }
}
