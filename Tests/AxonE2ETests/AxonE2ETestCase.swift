import Foundation
import XCTest

class AxonE2ETestCase: XCTestCase {
    static let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let axonBinary = projectRoot.appendingPathComponent(".build/release/axon")

    func runAxon(_ args: [String]) -> (stdout: String, stderr: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = Self.axonBinary
        process.arguments = args
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Read pipe data asynchronously to avoid deadlock when pipe buffer fills
        var stdoutData = Data()
        var stderrData = Data()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global().async {
            stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        try! process.run()
        process.waitUntilExit()
        group.wait()

        return (
            String(data: stdoutData, encoding: .utf8) ?? "",
            String(data: stderrData, encoding: .utf8) ?? "",
            process.terminationStatus
        )
    }

    func parseJSON(_ string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Check if the result indicates missing accessibility permissions.
    func skipIfNoAccessibility(_ result: (stdout: String, stderr: String, exitCode: Int32)) throws {
        try XCTSkipIf(
            result.stderr.contains("accessibility_not_trusted"),
            "Skipping: accessibility permissions not granted"
        )
    }
}
