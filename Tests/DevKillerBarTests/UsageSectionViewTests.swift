@testable import DevKillerBar
import DevKillerCore
import SwiftUI
import XCTest

final class UsageSectionViewTests: XCTestCase {
    func testBarColorBySeverity() {
        XCTAssertEqual(usageBarColor(for: .normal), Color.green)
        XCTAssertEqual(usageBarColor(for: .warning), Color.orange)
        XCTAssertEqual(usageBarColor(for: .critical), Color.red)
    }

    func testResetDisplayPrefersTextThenDate() {
        let textWindow = UsageWindow(kind: .fiveHour, label: "5h", usedPercent: 5, resetsAt: nil, resetText: "Jul 14 at 3:49am")
        XCTAssertEqual(usageResetDisplay(window: textWindow), "resets Jul 14 at 3:49am")

        let dateWindow = UsageWindow(kind: .weekly, label: "Week", usedPercent: 19, resetsAt: Date(timeIntervalSince1970: 1784495024), resetText: nil)
        XCTAssertTrue(usageResetDisplay(window: dateWindow)?.hasPrefix("resets ") == true)

        let noneWindow = UsageWindow(kind: .weekly, label: "Week", usedPercent: 19, resetsAt: nil, resetText: nil)
        XCTAssertNil(usageResetDisplay(window: noneWindow))
    }
}
