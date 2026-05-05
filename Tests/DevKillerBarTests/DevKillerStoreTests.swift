@testable import DevKillerBar
import DevKillerCore
import XCTest

@MainActor
final class DevKillerStoreTests: XCTestCase {
    func testAutoRefreshDiscoversServersStartedAfterStoreInitialization() async throws {
        let provider = SequenceServerProvider([
            [],
            [Self.server(port: 5173)]
        ])
        let store = DevKillerStore(
            usesSampleServers: false,
            serverProvider: { try provider.list() },
            autoRefreshInterval: .milliseconds(10)
        )

        store.startAutoRefresh()
        try await waitUntil(timeout: .seconds(1)) {
            store.servers.map(\.port) == [5173]
        }

        XCTAssertEqual(provider.callCount, 2)
        store.stopAutoRefresh()
    }

    private static func server(port: Int) -> DevelopmentServer {
        DevelopmentServer(
            pid: 100,
            command: "node",
            user: "tester",
            port: port,
            endpoint: "localhost:\(port)",
            classification: ServerClassification(
                framework: "Vite dev server",
                confidence: .high,
                reasons: ["test fixture"]
            )
        )
    }

    private func waitUntil(
        timeout: Duration,
        predicate: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if predicate() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for predicate")
    }
}

private final class SequenceServerProvider: @unchecked Sendable {
    private var snapshots: [[DevelopmentServer]]
    private let lock = NSLock()

    init(_ snapshots: [[DevelopmentServer]]) {
        self.snapshots = snapshots
    }

    var callCount: Int {
        lock.withLock {
            snapshotsCallCount
        }
    }

    private var snapshotsCallCount = 0

    func list() throws -> [DevelopmentServer] {
        lock.withLock {
            snapshotsCallCount += 1
            guard snapshots.count > 1 else {
                return snapshots.first ?? []
            }
            return snapshots.removeFirst()
        }
    }
}
