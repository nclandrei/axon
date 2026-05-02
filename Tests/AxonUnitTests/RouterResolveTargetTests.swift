import XCTest
@testable import AxonLib

final class RouterResolveTargetTests: XCTestCase {

    private func makeRegistry(
        vms: [VMEntry] = [],
        bases: [BaseEntry] = []
    ) -> VMRegistry {
        VMRegistry(vms: vms, bases: bases)
    }

    // --- flag/env paths ---

    func testLocalFlagWins() throws {
        let target = try resolveTarget(
            argv: ["--local", "--app", "Cicero"],
            command: "click",
            registry: makeRegistry(),
            env: [:],
            acquirer: StubAcquirer()
        )
        XCTAssertEqual(target, .local)
    }

    func testEnvAxonTargetLocalSelectsLocal() throws {
        let target = try resolveTarget(
            argv: ["--app", "Cicero"],
            command: "click",
            registry: makeRegistry(),
            env: ["AXON_TARGET": "local"],
            acquirer: StubAcquirer()
        )
        XCTAssertEqual(target, .local)
    }

    func testFlagBeatsEnvWhenBothPresent() throws {
        let target = try resolveTarget(
            argv: ["--local", "--app", "Cicero"],
            command: "click",
            registry: makeRegistry(),
            env: ["AXON_TARGET": "vm-or-whatever"],
            acquirer: StubAcquirer()
        )
        XCTAssertEqual(target, .local)
    }

    func testVMFlagSelectsRegisteredVM() throws {
        let entry = VMEntry(name: "axon-pinned", base: "sequoia-base", created: Date(), ip: "10.0.0.5")
        let registry = makeRegistry(vms: [entry])
        let target = try resolveTarget(
            argv: ["--vm", "axon-pinned"],
            command: "click",
            registry: registry,
            env: [:],
            acquirer: StubAcquirer()
        )
        XCTAssertEqual(target, .remote(entry))
    }

    func testVMFlagErrorsWhenVMNotFound() {
        XCTAssertThrowsError(try resolveTarget(
            argv: ["--vm", "axon-ghost"],
            command: "click",
            registry: makeRegistry(),
            env: [:],
            acquirer: StubAcquirer()
        )) { err in
            XCTAssertEqual(err as? RouterError, .vmNotFound(name: "axon-ghost"))
        }
    }

    func testVMFlagErrorsWhenVMHasNoIP() {
        let entry = VMEntry(name: "axon-broken", base: "b", created: Date(), ip: nil)
        XCTAssertThrowsError(try resolveTarget(
            argv: ["--vm", "axon-broken"],
            command: "click",
            registry: makeRegistry(vms: [entry]),
            env: [:],
            acquirer: StubAcquirer()
        )) { err in
            XCTAssertEqual(err as? RouterError, .vmNotReady(name: "axon-broken"))
        }
    }
    // --- bundle ID resolution ---

    func testAppResolvesViaRegistryDisplayName() throws {
        let base = BaseEntry(
            name: "axon-cicero-base", source: "s",
            bundleID: "com.andreinicolas.Cicero", displayName: "Cicero", baked: Date()
        )
        let runningVM = VMEntry(name: "axon-running", base: "axon-cicero-base", created: Date(), ip: "10.0.0.7")
        let registry = makeRegistry(vms: [runningVM], bases: [base])
        let target = try resolveTarget(
            argv: ["--app", "Cicero"],
            command: "click",
            registry: registry,
            env: [:],
            acquirer: StubAcquirer(),
            bundleIDResolver: StubBundleIDResolver()
        )
        XCTAssertEqual(target, .remote(runningVM))
    }

    func testAppResolutionIsCaseInsensitive() throws {
        let base = BaseEntry(
            name: "axon-cicero-base", source: "s",
            bundleID: "com.andreinicolas.Cicero", displayName: "Cicero", baked: Date()
        )
        let runningVM = VMEntry(name: "axon-r", base: "axon-cicero-base", created: Date(), ip: "10.0.0.8")
        let registry = makeRegistry(vms: [runningVM], bases: [base])
        let target = try resolveTarget(
            argv: ["--app", "cicero"],
            command: "click",
            registry: registry,
            env: [:],
            acquirer: StubAcquirer(),
            bundleIDResolver: StubBundleIDResolver()
        )
        XCTAssertEqual(target, .remote(runningVM))
    }

    func testBundleIDFlagBypassesAppLookup() throws {
        let base = BaseEntry(
            name: "axon-x-base", source: "s",
            bundleID: "com.example.X", displayName: nil, baked: Date()
        )
        let runningVM = VMEntry(name: "axon-x-vm", base: "axon-x-base", created: Date(), ip: "10.0.0.9")
        let registry = makeRegistry(vms: [runningVM], bases: [base])
        let target = try resolveTarget(
            argv: ["--bundle-id", "com.example.X"],
            command: "click",
            registry: registry,
            env: [:],
            acquirer: StubAcquirer(),
            bundleIDResolver: StubBundleIDResolver()
        )
        XCTAssertEqual(target, .remote(runningVM))
    }

    func testAppFallsBackToHostBundleIDResolver() throws {
        // No matching displayName in registry — fall through to host lookup.
        let base = BaseEntry(
            name: "axon-hostlookup-base", source: "s",
            bundleID: "com.host.Looked", displayName: nil, baked: Date()
        )
        let runningVM = VMEntry(name: "axon-h", base: "axon-hostlookup-base", created: Date(), ip: "10.0.0.10")
        let registry = makeRegistry(vms: [runningVM], bases: [base])
        let resolver = StubBundleIDResolver(map: ["WeirdName": "com.host.Looked"])
        let target = try resolveTarget(
            argv: ["--app", "WeirdName"],
            command: "click",
            registry: registry,
            env: [:],
            acquirer: StubAcquirer(),
            bundleIDResolver: resolver
        )
        XCTAssertEqual(target, .remote(runningVM))
    }

    // --- acquire-on-miss ---

    func testNoRunningVMForBaseTriggersAcquire() throws {
        let base = BaseEntry(
            name: "axon-cicero-base", source: "s",
            bundleID: "com.andreinicolas.Cicero", displayName: "Cicero", baked: Date()
        )
        // No matching VMs in registry.
        let registry = makeRegistry(bases: [base])
        let acquired = VMEntry(name: "axon-fresh", base: "axon-cicero-base", created: Date(), ip: "10.0.0.42")
        let target = try resolveTarget(
            argv: ["--app", "Cicero"],
            command: "click",
            registry: registry,
            env: [:],
            acquirer: StubAcquirer(entryToReturn: acquired),
            bundleIDResolver: StubBundleIDResolver()
        )
        XCTAssertEqual(target, .remote(acquired))
    }

    func testAcquireFailureSurfacesAsRouterError() {
        let base = BaseEntry(
            name: "axon-x", source: "s", bundleID: "com.x.A", displayName: nil, baked: Date()
        )
        let registry = makeRegistry(bases: [base])
        struct FailingAcquirer: VMAcquirer {
            func acquire(base: String, headless: Bool, timeout: Int) -> Result<VMEntry, VMError> {
                .failure(VMError("clone failed: disk full"))
            }
        }
        XCTAssertThrowsError(try resolveTarget(
            argv: ["--bundle-id", "com.x.A"],
            command: "click",
            registry: registry,
            env: [:],
            acquirer: FailingAcquirer(),
            bundleIDResolver: StubBundleIDResolver()
        )) { err in
            if case .vmAcquireFailed(let msg) = err as? RouterError {
                XCTAssertTrue(msg.contains("clone failed"))
            } else {
                XCTFail("Expected .vmAcquireFailed, got \(err)")
            }
        }
    }
}

// MARK: - Stub acquirer used by all RouterResolveTargetTests

final class StubAcquirer: VMAcquirer {
    var entryToReturn: VMEntry = VMEntry(name: "axon-stub", base: "b", created: Date(), ip: "10.0.0.99")
    private(set) var calls: [(base: String, headless: Bool, timeout: Int)] = []

    init(entryToReturn: VMEntry? = nil) {
        if let e = entryToReturn { self.entryToReturn = e }
    }

    func acquire(base: String, headless: Bool, timeout: Int) -> Result<VMEntry, VMError> {
        calls.append((base, headless, timeout))
        return .success(entryToReturn)
    }
}

struct StubBundleIDResolver: BundleIDResolver {
    var map: [String: String] = [:]
    func bundleID(forAppName name: String) -> String? { map[name] }
}
