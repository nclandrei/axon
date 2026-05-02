import XCTest
@testable import AxonLib

final class SSHClientCompileTests: XCTestCase {
    func testLiveSSHDispatcherTypeExists() {
        let _: SSHDispatcher = LiveSSHDispatcher()
    }
    func testLiveScpBackRunnerTypeExists() {
        let _: ScpBackRunner = LiveScpBackRunner()
    }
}
