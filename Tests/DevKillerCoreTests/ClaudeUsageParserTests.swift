@testable import DevKillerCore
import XCTest

final class ClaudeUsageParserTests: XCTestCase {
    private let sample = """
    You are currently using your subscription to power your Claude Code usage

    Current session: 5% used · resets Jul 14 at 3:49am (Asia/Seoul)
    Current week (all models): 78% used · resets Jul 14 at 1:59am (Asia/Seoul)
    Current week (Fable): 97% used · resets Jul 14 at 1:59am (Asia/Seoul)

    What's contributing to your limits usage?
    Last 24h · 217 requests · 7 sessions
    """

    func testParsesAllWindows() {
        guard case let .available(windows, asOf) = ClaudeUsageParser.parse(sample) else {
            return XCTFail("expected available")
        }
        XCTAssertNil(asOf)
        XCTAssertEqual(windows.count, 3)

        XCTAssertEqual(windows[0].kind, .fiveHour)
        XCTAssertEqual(windows[0].label, "5h")
        XCTAssertEqual(windows[0].usedPercent, 5)
        XCTAssertEqual(windows[0].resetText, "Jul 14 at 3:49am (Asia/Seoul)")
        XCTAssertNil(windows[0].resetsAt)

        XCTAssertEqual(windows[1].kind, .weekly)
        XCTAssertEqual(windows[1].label, "Week (all models)")
        XCTAssertEqual(windows[1].usedPercent, 78)

        XCTAssertEqual(windows[2].label, "Week (Fable)")
        XCTAssertEqual(windows[2].usedPercent, 97)
    }

    func testParsesWindowWithoutResetSuffix() {
        guard case let .available(windows, _) = ClaudeUsageParser.parse("Current session: 12% used") else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].usedPercent, 12)
        XCTAssertNil(windows[0].resetText)
    }

    func testGarbledOutputIsUnavailable() {
        guard case .unavailable = ClaudeUsageParser.parse("error: not logged in") else {
            return XCTFail("expected unavailable")
        }
    }
}
