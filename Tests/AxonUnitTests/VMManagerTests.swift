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

    // MARK: - BaseEntry / bases field

    func testBaseEntryRoundTrip() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let base = BaseEntry(
            name: "axon-cicero-base",
            source: "ghcr.io/cirruslabs/macos-sequoia-base:latest",
            bundleID: "com.andreinicolas.Cicero",
            displayName: "Cicero",
            baked: date
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(base)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try! decoder.decode(BaseEntry.self, from: data)
        XCTAssertEqual(decoded.name, "axon-cicero-base")
        XCTAssertEqual(decoded.bundleID, "com.andreinicolas.Cicero")
        XCTAssertEqual(decoded.displayName, "Cicero")
        XCTAssertEqual(decoded.baked.timeIntervalSince1970, 1_700_000_000, accuracy: 1.0)
    }

    func testBaseEntryRoundTripWithoutDisplayName() {
        let base = BaseEntry(
            name: "axon-x-base",
            source: "src",
            bundleID: "com.example.X",
            displayName: nil,
            baked: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(base)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try! decoder.decode(BaseEntry.self, from: data)
        XCTAssertNil(decoded.displayName)
    }

    func testVMRegistryWithBasesRoundTrip() throws {
        let url = registryURL()
        let reg = VMRegistry(
            vms: [VMEntry(name: "axon-1", base: "sonoma", created: Date(), ip: "10.0.0.1")],
            bases: [BaseEntry(
                name: "axon-cicero-base",
                source: "src",
                bundleID: "com.andreinicolas.Cicero",
                displayName: "Cicero",
                baked: Date()
            )]
        )
        try saveVMRegistry(reg, to: url)
        let loaded = loadVMRegistry(at: url)
        XCTAssertEqual(loaded.vms.count, 1)
        XCTAssertEqual(loaded.bases.count, 1)
        XCTAssertEqual(loaded.bases[0].bundleID, "com.andreinicolas.Cicero")
    }

    func testLoadOldRegistryWithoutBasesField() throws {
        // A registry written before this feature has no `bases` key.
        let url = registryURL()
        let json = """
        {
          "vms": [
            {"name":"axon-old","base":"sonoma","created":"2026-01-01T00:00:00Z","ip":"10.0.0.1"}
          ]
        }
        """
        try json.data(using: .utf8)!.write(to: url)
        let loaded = loadVMRegistry(at: url)
        XCTAssertEqual(loaded.vms.count, 1)
        XCTAssertEqual(loaded.bases.count, 0, "Missing bases field must decode as []")
    }

    // MARK: - recordBase / findBase

    func testRecordBaseWritesBaseEntry() throws {
        let url = registryURL()
        try recordBase(
            name: "axon-cicero-base",
            source: "src",
            bundleID: "com.andreinicolas.Cicero",
            displayName: "Cicero",
            at: url
        )
        let loaded = loadVMRegistry(at: url)
        XCTAssertEqual(loaded.bases.count, 1)
        XCTAssertEqual(loaded.bases[0].name, "axon-cicero-base")
        XCTAssertEqual(loaded.bases[0].bundleID, "com.andreinicolas.Cicero")
        XCTAssertEqual(loaded.bases[0].displayName, "Cicero")
    }

    func testRecordBaseReplacesExistingMappingForSameBundleID() throws {
        let url = registryURL()
        try recordBase(name: "old-base", source: "old-src", bundleID: "com.x.A", displayName: "A", at: url)
        try recordBase(name: "new-base", source: "new-src", bundleID: "com.x.A", displayName: "A", at: url)
        let loaded = loadVMRegistry(at: url)
        XCTAssertEqual(loaded.bases.count, 1, "Re-baking same bundle ID should replace, not append")
        XCTAssertEqual(loaded.bases[0].name, "new-base")
        XCTAssertEqual(loaded.bases[0].source, "new-src")
    }

    func testFindBaseByBundleIDReturnsMatch() throws {
        let url = registryURL()
        try recordBase(name: "axon-x", source: "s", bundleID: "com.x.X", displayName: "X", at: url)
        try recordBase(name: "axon-y", source: "s", bundleID: "com.y.Y", displayName: "Y", at: url)
        let registry = loadVMRegistry(at: url)
        let found = findBase(byBundleID: "com.y.Y", in: registry)
        XCTAssertEqual(found?.name, "axon-y")
    }

    func testFindBaseByBundleIDReturnsNilWhenMissing() {
        let registry = VMRegistry(vms: [], bases: [])
        XCTAssertNil(findBase(byBundleID: "com.absent.X", in: registry))
    }

    // MARK: - AXON_REGISTRY_PATH env

    func testActiveVMRegistryURLHonorsEnvOverride() {
        let custom = registryURL("env-override.json")
        let resolved = activeVMRegistryURL(env: ["AXON_REGISTRY_PATH": custom.path])
        XCTAssertEqual(resolved.path, custom.path)
    }

    func testActiveVMRegistryURLFallsBackToDefaultWhenEnvUnset() {
        let resolved = activeVMRegistryURL(env: [:])
        XCTAssertEqual(resolved.path, defaultVMRegistryURL.path)
    }

    func testActiveVMRegistryURLIgnoresEmptyEnv() {
        let resolved = activeVMRegistryURL(env: ["AXON_REGISTRY_PATH": ""])
        XCTAssertEqual(resolved.path, defaultVMRegistryURL.path)
    }

    func testActiveVMRegistryURLExpandsTilde() {
        let resolved = activeVMRegistryURL(env: ["AXON_REGISTRY_PATH": "~/axon-test-tilde-expansion.json"])
        let home = NSHomeDirectory()
        XCTAssertEqual(resolved.path, "\(home)/axon-test-tilde-expansion.json")
    }

    // MARK: - vm-sync

    func testVMSyncCallsRunnerForEachMatchingVM() throws {
        let url = registryURL()
        try recordBase(name: "axon-cicero-base", source: "s",
                       bundleID: "com.x.Cicero", displayName: "Cicero", at: url)
        var registry = loadVMRegistry(at: url)
        registry.vms.append(VMEntry(name: "axon-r1", base: "axon-cicero-base", created: Date(), ip: "10.0.0.1"))
        registry.vms.append(VMEntry(name: "axon-r2", base: "axon-cicero-base", created: Date(), ip: "10.0.0.2"))
        registry.vms.append(VMEntry(name: "axon-other", base: "axon-other-base", created: Date(), ip: "10.0.0.3"))
        try saveVMRegistry(registry, to: url)

        var calls: [(localPath: String, vmIP: String)] = []
        let result = vmSync(
            bundleID: "com.x.Cicero",
            localAppPath: "/Users/me/Cicero.app",
            registry: registry,
            runner: { local, ip in
                calls.append((local, ip))
                return .success(())
            }
        )
        switch result {
        case .success(let count):
            XCTAssertEqual(count, 2)
        case .failure(let err):
            XCTFail("Expected success, got \(err)")
        }
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(Set(calls.map { $0.vmIP }), Set(["10.0.0.1", "10.0.0.2"]))
        XCTAssertTrue(calls.allSatisfy { $0.localPath == "/Users/me/Cicero.app" })
    }

    func testVMSyncFailsWhenNoBaseRegistered() {
        let registry = VMRegistry(vms: [], bases: [])
        let result = vmSync(
            bundleID: "com.x.Missing",
            localAppPath: "/Users/me/X.app",
            registry: registry,
            runner: { _, _ in .success(()) }
        )
        if case .failure(let err) = result {
            XCTAssertTrue(err.description.contains("com.x.Missing"))
        } else {
            XCTFail("Expected failure")
        }
    }

    func testVMSyncSucceedsWithZeroVMsWhenBaseRegisteredButNoneRunning() throws {
        let url = registryURL()
        try recordBase(name: "axon-cicero-base", source: "s",
                       bundleID: "com.x.Cicero", displayName: "Cicero", at: url)
        let registry = loadVMRegistry(at: url)
        var calls = 0
        let result = vmSync(
            bundleID: "com.x.Cicero",
            localAppPath: "/Users/me/Cicero.app",
            registry: registry,
            runner: { _, _ in calls += 1; return .success(()) }
        )
        switch result {
        case .success(let count): XCTAssertEqual(count, 0)
        case .failure(let err): XCTFail("Expected success, got \(err)")
        }
        XCTAssertEqual(calls, 0)
    }
}
