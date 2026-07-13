@testable import DevKillerCore
import XCTest

final class ClaudeBinaryLocatorTests: XCTestCase {
    func testReturnsFirstExistingCandidate() {
        let found = ClaudeBinaryDiscovery.locate(
            candidates: ["/a/claude", "/b/claude"],
            fileExists: { $0 == "/b/claude" },
            shellLookup: { XCTFail("should not reach shell"); return nil }
        )
        XCTAssertEqual(found, "/b/claude")
    }

    func testFallsBackToShellLookup() {
        let found = ClaudeBinaryDiscovery.locate(
            candidates: ["/a/claude"],
            fileExists: { $0 == "/shell/claude" },
            shellLookup: { "/shell/claude\n" }
        )
        XCTAssertEqual(found, "/shell/claude")
    }

    func testReturnsNilWhenNothingFound() {
        let found = ClaudeBinaryDiscovery.locate(
            candidates: ["/a/claude"],
            fileExists: { _ in false },
            shellLookup: { nil }
        )
        XCTAssertNil(found)
    }
}
