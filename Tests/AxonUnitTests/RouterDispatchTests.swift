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

    func testDispatchRemoteRunsScpBacksOnSuccess() throws {
        let vm = VMEntry(name: "axon-x", base: "b", created: Date(), ip: "10.0.0.5")
        let ssh = RecordingSSH()
        let scp = NoopScp()
        let scpBack = ScpBack(vmPath: "/tmp/axon-out.png", hostPath: "/Users/me/shot.png")
        _ = try dispatchRemote(
            vm: vm, argv: ["screenshot"], scpBacks: [scpBack],
            ssh: ssh, scpRunner: scp
        )
        XCTAssertEqual(scp.calls.count, 1)
        XCTAssertEqual(scp.calls[0].vmPath, "/tmp/axon-out.png")
        XCTAssertEqual(scp.calls[0].hostPath, "/Users/me/shot.png")
    }

    func testDispatchRemoteSkipsScpOnNonZeroExit() throws {
        let vm = VMEntry(name: "axon-x", base: "b", created: Date(), ip: "10.0.0.5")
        let ssh = RecordingSSH()
        ssh.exitCode = 1
        let scp = NoopScp()
        let scpBack = ScpBack(vmPath: "/tmp/axon-out.png", hostPath: "/Users/me/shot.png")
        _ = try dispatchRemote(
            vm: vm, argv: ["screenshot"], scpBacks: [scpBack],
            ssh: ssh, scpRunner: scp
        )
        XCTAssertTrue(scp.calls.isEmpty, "Failed SSH must skip scp-back; the file probably wasn't written")
    }

    func testDispatchRemoteSurfacesScpFailure() {
        let vm = VMEntry(name: "axon-x", base: "b", created: Date(), ip: "10.0.0.5")
        let ssh = RecordingSSH()
        let scp = NoopScp()
        scp.failure = VMError("Permission denied")
        let scpBack = ScpBack(vmPath: "/tmp/axon-out.png", hostPath: "/Users/me/shot.png")
        XCTAssertThrowsError(try dispatchRemote(
            vm: vm, argv: ["screenshot"], scpBacks: [scpBack],
            ssh: ssh, scpRunner: scp
        )) { err in
            if case let .outputTransferFailed(message) = err as? RouterError {
                XCTAssertTrue(message.contains("Permission denied"))
            } else {
                XCTFail("Expected .outputTransferFailed, got \(err)")
            }
        }
    }
}
