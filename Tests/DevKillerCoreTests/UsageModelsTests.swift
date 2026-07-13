@testable import DevKillerCore
import XCTest

final class UsageModelsTests: XCTestCase {
    func testSeverityThresholds() {
        XCTAssertEqual(usageSeverity(0), .normal)
        XCTAssertEqual(usageSeverity(69.9), .normal)
        XCTAssertEqual(usageSeverity(70), .warning)
        XCTAssertEqual(usageSeverity(90), .warning)
        XCTAssertEqual(usageSeverity(90.1), .critical)
        XCTAssertEqual(usageSeverity(100), .critical)
    }

    func testWindowSeverityMatchesHelper() {
        let window = UsageWindow(kind: .weekly, label: "Week", usedPercent: 95, resetsAt: nil, resetText: nil)
        XCTAssertEqual(window.severity, .critical)
    }

    func testStaleDetection() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(isUsageStale(asOf: now.addingTimeInterval(-3600), now: now))
        XCTAssertTrue(isUsageStale(asOf: now.addingTimeInterval(-25 * 3600), now: now))
    }
}
