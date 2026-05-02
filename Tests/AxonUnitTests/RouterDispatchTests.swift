import XCTest
@testable import AxonLib

final class RouterDispatchTests: XCTestCase {

    final class RecordingSSH: SSHDispatcher {
        var calls: [(vmIP: String, argv: [String], env: [String: String])] = []
        var stdout: Data = Data("ok\n".utf8)
        var stderr: Data = Data()
        var exitCode: Int32 = 0
        func run(vmIP: String, argv: [String], env: [String: String]) -> (stdout: Data, stderr: Data, exitCode: Int32) {
            calls.append((vmIP, argv, env))
            return (stdout, stderr, exitCode)
        }
    }

    final class NoopScp: ScpBackRunner {
        var calls: [ScpBack] = []
        var failure: VMError?
        func transfer(_ scpBack: ScpBack, fromVMIP ip: String) -> Result<Void, VMError> {
            calls.append(scpBack)
            if let f = failure { return .failure(f) }
            return .success(())
        }
    }

    func testDispatchRemoteRunsSSHWithArgvAndAxonTargetLocalEnv() throws {
        let vm = VMEntry(name: "axon-x", base: "b", created: Date(), ip: "10.0.0.5")
        let ssh = RecordingSSH()
        let scp = NoopScp()
        let result = try dispatchRemote(
            vm: vm,
            argv: ["click", "--app", "Cicero", "--label", "Save"],
            scpBacks: [],
            ssh: ssh,
            scpRunner: scp
        )
        XCTAssertEqual(ssh.calls.count, 1)
        XCTAssertEqual(ssh.calls[0].vmIP, "10.0.0.5")
        XCTAssertEqual(ssh.calls[0].argv, ["click", "--app", "Cicero", "--label", "Save"])
        XCTAssertEqual(ssh.calls[0].env["AXON_TARGET"], "local")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(String(data: result.stdout, encoding: .utf8), "ok\n")
    }

    func testDispatchRemoteSurfacesNonZeroExit() throws {
        let vm = VMEntry(name: "axon-x", base: "b", created: Date(), ip: "10.0.0.5")
        let ssh = RecordingSSH()
        ssh.exitCode = 17
        ssh.stderr = Data("boom\n".utf8)
        let result = try dispatchRemote(
            vm: vm, argv: ["click"], scpBacks: [],
            ssh: ssh, scpRunner: NoopScp()
        )
        XCTAssertEqual(result.exitCode, 17)
        XCTAssertEqual(String(data: result.stderr, encoding: .utf8), "boom\n")
    }
}
