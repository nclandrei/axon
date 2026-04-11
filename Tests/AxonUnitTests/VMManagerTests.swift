import XCTest
@testable import AxonLib

final class VMManagerTests: XCTestCase {

    // MARK: - Temp dir helpers

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("axon-vmmanager-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir = tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    private func registryURL(_ name: String = "vms.json") -> URL {
        tempDir.appendingPathComponent(name)
    }

    // MARK: - VMEntry Codable

    func testVMEntryRoundTripWithIP() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = VMEntry(name: "axon-aabbccdd", base: "sonoma-base", created: date, ip: "192.168.64.10")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(entry)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try! decoder.decode(VMEntry.self, from: data)

        XCTAssertEqual(decoded.name, "axon-aabbccdd")
        XCTAssertEqual(decoded.base, "sonoma-base")
        XCTAssertEqual(decoded.created.timeIntervalSince1970, 1_700_000_000, accuracy: 1.0)
        XCTAssertEqual(decoded.ip, "192.168.64.10")
    }

    func testVMEntryRoundTripWithNilIP() {
        let entry = VMEntry(name: "axon-pending", base: "sonoma", created: Date(), ip: nil)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(entry)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try! decoder.decode(VMEntry.self, from: data)

        XCTAssertEqual(decoded.name, "axon-pending")
        XCTAssertNil(decoded.ip)
    }

    // MARK: - VMRegistry Codable

    func testVMRegistryEmptyRoundTrip() {
        let registry = VMRegistry(vms: [])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(registry)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try! decoder.decode(VMRegistry.self, from: data)

        XCTAssertTrue(decoded.vms.isEmpty)
    }

    func testVMRegistryMultipleEntriesRoundTrip() {
        let now = Date()
        let registry = VMRegistry(vms: [
            VMEntry(name: "axon-aaaa", base: "sonoma", created: now, ip: "10.0.0.1"),
            VMEntry(name: "axon-bbbb", base: "sequoia", created: now, ip: "10.0.0.2"),
            VMEntry(name: "axon-cccc", base: "ventura", created: now, ip: nil),
        ])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(registry)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try! decoder.decode(VMRegistry.self, from: data)

        XCTAssertEqual(decoded.vms.count, 3)
        XCTAssertEqual(decoded.vms[0].name, "axon-aaaa")
        XCTAssertEqual(decoded.vms[1].base, "sequoia")
        XCTAssertNil(decoded.vms[2].ip)
    }

    // MARK: - loadVMRegistry / saveVMRegistry

    func testLoadVMRegistryReturnsEmptyWhenFileMissing() {
        let url = registryURL("does-not-exist.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        let registry = loadVMRegistry(at: url)
        XCTAssertTrue(registry.vms.isEmpty)
    }

    func testLoadVMRegistryReturnsEmptyWhenFileIsCorrupt() throws {
        let url = registryURL()
        try "this is not json".data(using: .utf8)!.write(to: url)

        let registry = loadVMRegistry(at: url)
        XCTAssertTrue(registry.vms.isEmpty, "Corrupt registry should fall back to empty")
    }

    func testSaveAndLoadVMRegistryRoundTrip() throws {
        let url = registryURL()
        let entry = VMEntry(
            name: "axon-deadbeef",
            base: "sonoma-base",
            created: Date(timeIntervalSince1970: 1_700_000_000),
            ip: "192.168.64.42"
        )
        let registry = VMRegistry(vms: [entry])

        try saveVMRegistry(registry, to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let loaded = loadVMRegistry(at: url)
        XCTAssertEqual(loaded.vms.count, 1)
        XCTAssertEqual(loaded.vms[0].name, "axon-deadbeef")
        XCTAssertEqual(loaded.vms[0].base, "sonoma-base")
        XCTAssertEqual(loaded.vms[0].ip, "192.168.64.42")
        XCTAssertEqual(
            loaded.vms[0].created.timeIntervalSince1970,
            1_700_000_000,
            accuracy: 1.0
        )
    }

    func testSaveVMRegistryCreatesParentDirectory() throws {
        let nested = tempDir
            .appendingPathComponent("nested")
            .appendingPathComponent("dirs")
            .appendingPathComponent("vms.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: nested.deletingLastPathComponent().path))

        try saveVMRegistry(VMRegistry(vms: []), to: nested)
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
    }

    func testSaveVMRegistryOverwritesExisting() throws {
        let url = registryURL()
        try saveVMRegistry(VMRegistry(vms: [
            VMEntry(name: "old-vm", base: "sonoma", created: Date(), ip: nil),
        ]), to: url)

        try saveVMRegistry(VMRegistry(vms: [
            VMEntry(name: "new-vm", base: "sequoia", created: Date(), ip: "10.0.0.5"),
        ]), to: url)

        let loaded = loadVMRegistry(at: url)
        XCTAssertEqual(loaded.vms.count, 1)
        XCTAssertEqual(loaded.vms[0].name, "new-vm")
        XCTAssertEqual(loaded.vms[0].ip, "10.0.0.5")
    }

    func testSaveVMRegistryEmptyThenLoad() throws {
        let url = registryURL()
        try saveVMRegistry(VMRegistry(vms: []), to: url)

        let loaded = loadVMRegistry(at: url)
        XCTAssertTrue(loaded.vms.isEmpty)
    }

    func testSavedRegistryFileIsValidJSON() throws {
        let url = registryURL()
        let registry = VMRegistry(vms: [
            VMEntry(name: "axon-1", base: "sonoma", created: Date(), ip: "10.0.0.1"),
            VMEntry(name: "axon-2", base: "sonoma", created: Date(), ip: nil),
        ])
        try saveVMRegistry(registry, to: url)

        let data = try Data(contentsOf: url)
        let parsed = try JSONSerialization.jsonObject(with: data)
        XCTAssertNotNil(parsed as? [String: Any], "File should be a JSON object")
    }

    // MARK: - vmListEntries(at:)

    func testVMListEntriesAtURLReturnsEmptyWhenMissing() {
        let url = registryURL("missing.json")
        XCTAssertTrue(vmListEntries(at: url).isEmpty)
    }

    func testVMListEntriesAtURLReturnsSavedEntries() throws {
        let url = registryURL()
        try saveVMRegistry(VMRegistry(vms: [
            VMEntry(name: "axon-x", base: "sonoma", created: Date(), ip: "10.0.0.7"),
            VMEntry(name: "axon-y", base: "sequoia", created: Date(), ip: "10.0.0.8"),
        ]), to: url)

        let entries = vmListEntries(at: url)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map { $0.name }, ["axon-x", "axon-y"])
    }

    // MARK: - defaultVMRegistryURL

    func testDefaultVMRegistryURLPointsToHomeAxonDir() {
        let url = defaultVMRegistryURL
        XCTAssertEqual(url.lastPathComponent, "vms.json")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, ".axon")
    }
}
