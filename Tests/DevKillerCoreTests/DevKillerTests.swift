@testable import DevKillerCore
import XCTest

final class DevKillerTests: XCTestCase {
    func testListFiltersLowConfidenceByDefault() throws {
        let lsof = StubLsofRunner(output: """
        p1
        claunchd
        n*:80
        p2
        cnode
        n*:5173
        """)

        let devKiller = DevKiller(lsofRunner: lsof, signaler: StubSignaler())
        let servers = try devKiller.list()

        XCTAssertEqual(servers.map(\.port), [5173])
    }

    func testListDeduplicatesSamePIDAndPort() throws {
        let lsof = StubLsofRunner(output: """
        p2
        cnode
        n*:5173
        n*:5173
        """)

        let devKiller = DevKiller(lsofRunner: lsof, signaler: StubSignaler())
        let servers = try devKiller.list()

        XCTAssertEqual(servers.count, 1)
        XCTAssertEqual(servers[0].port, 5173)
    }

    func testTerminateUsesSIGTERMByDefault() {
        let signaler = StubSignaler()
        let devKiller = DevKiller(lsofRunner: StubLsofRunner(output: ""), signaler: signaler)

        let result = devKiller.terminate(pid: 42)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(signaler.sentSignals, [SIGTERM])
        XCTAssertEqual(signaler.sentPIDs, [42])
    }

    func testTerminateUsesSIGKILLWhenForced() {
        let signaler = StubSignaler()
        let devKiller = DevKiller(lsofRunner: StubLsofRunner(output: ""), signaler: signaler)

        _ = devKiller.terminate(pid: 42, force: true)

        XCTAssertEqual(signaler.sentSignals, [SIGKILL])
    }

    func testTerminateSurfacesPermissionDenied() {
        let signaler = StubSignaler(result: -1, errnoValue: EPERM)
        let devKiller = DevKiller(lsofRunner: StubLsofRunner(output: ""), signaler: signaler)

        let result = devKiller.terminate(pid: 42)

        XCTAssertEqual(result.error, .permissionDenied(pid: 42))
    }
}

private struct StubLsofRunner: LsofRunning {
    let output: String

    func listeningTCPOutput() throws -> String {
        output
    }
}

private final class StubSignaler: @unchecked Sendable, ProcessSignaling {
    var sentSignals: [Int32] = []
    var sentPIDs: [Int32] = []
    private let result: Int32
    private let errnoValue: Int32

    init(result: Int32 = 0, errnoValue: Int32 = 0) {
        self.result = result
        self.errnoValue = errnoValue
    }

    func send(signal: Int32, to pid: Int32) -> Int32 {
        sentSignals.append(signal)
        sentPIDs.append(pid)
        return result
    }

    var lastErrno: Int32 {
        errnoValue
    }
}
