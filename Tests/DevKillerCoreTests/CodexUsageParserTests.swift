@testable import DevKillerCore
import XCTest

final class CodexUsageParserTests: XCTestCase {
    // Real rollout shape (weekly-only, secondary null).
    private let weeklyOnly = """
    {"timestamp":"2026-07-13T14:03:08.874Z","type":"event_msg","payload":{"type":"token_count","info":{"model_context_window":258400},"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":19.0,"window_minutes":10080,"resets_at":1784495024},"secondary":null,"credits":null,"individual_limit":null,"plan_type":"prolite","rate_limit_reached_type":null}}}
    """

    // Synthesized both-window shape.
    private let bothWindows = """
    {"timestamp":"2026-07-13T14:03:08.874Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":42.0,"window_minutes":10080,"resets_at":1784495024},"secondary":{"used_percent":8.5,"window_minutes":300,"resets_at":1784400000}}}}
    """

    // Real rollout shape with a whole-second (non-fractional) timestamp.
    private let weeklyOnlyWholeSecondTimestamp = """
    {"timestamp":"2026-07-13T14:03:08Z","type":"event_msg","payload":{"type":"token_count","info":{"model_context_window":258400},"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":19.0,"window_minutes":10080,"resets_at":1784495024},"secondary":null,"credits":null,"individual_limit":null,"plan_type":"prolite","rate_limit_reached_type":null}}}
    """

    func testParsesWeeklyOnly() {
        guard case let .available(windows, asOf) = CodexUsageParser.parse(weeklyOnly) else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].kind, .weekly)
        XCTAssertEqual(windows[0].label, "Week")
        XCTAssertEqual(windows[0].usedPercent, 19.0)
        XCTAssertEqual(windows[0].resetsAt, Date(timeIntervalSince1970: 1784495024))
        XCTAssertNil(windows[0].resetText)

        // Verify that asOf is not nil (regression check: broken formatter returns nil)
        XCTAssertNotNil(asOf)

        // Build expected date from components to avoid relying on broken formatter
        var expectedComponents = DateComponents()
        expectedComponents.year = 2026
        expectedComponents.month = 7
        expectedComponents.day = 13
        expectedComponents.hour = 14
        expectedComponents.minute = 3
        expectedComponents.second = 8
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let expectedDate = utcCalendar.date(from: expectedComponents)!

        // Assert parsed asOf is close to expected (within ~1 second to tolerate fractional seconds)
        XCTAssertEqual(asOf!.timeIntervalSince1970, expectedDate.timeIntervalSince1970, accuracy: 1.0)
    }

    func testParsesAsOfWithoutFractionalSeconds() {
        guard case let .available(_, asOf) = CodexUsageParser.parse(weeklyOnlyWholeSecondTimestamp) else {
            return XCTFail("expected available")
        }

        // Regression check: a formatter that requires fractional seconds
        // would fail to parse a whole-second timestamp and return nil.
        XCTAssertNotNil(asOf)

        // Build expected date from components to avoid relying on any
        // ISO8601DateFormatter (which would be a tautological assertion).
        var expectedComponents = DateComponents()
        expectedComponents.year = 2026
        expectedComponents.month = 7
        expectedComponents.day = 13
        expectedComponents.hour = 14
        expectedComponents.minute = 3
        expectedComponents.second = 8
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let expectedDate = utcCalendar.date(from: expectedComponents)!

        XCTAssertEqual(asOf!.timeIntervalSince1970, expectedDate.timeIntervalSince1970, accuracy: 1.0)
    }

    func testParsesBothWindowsFiveHourFirst() {
        guard case let .available(windows, _) = CodexUsageParser.parse(bothWindows) else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].kind, .fiveHour)
        XCTAssertEqual(windows[0].usedPercent, 8.5)
        XCTAssertEqual(windows[1].kind, .weekly)
        XCTAssertEqual(windows[1].usedPercent, 42.0)
    }

    func testMissingRateLimitsIsUnavailable() {
        let line = "{\"timestamp\":\"2026-07-13T14:03:08.874Z\",\"payload\":{\"type\":\"token_count\"}}"
        guard case .unavailable = CodexUsageParser.parse(line) else {
            return XCTFail("expected unavailable")
        }
    }
}
