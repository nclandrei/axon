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
