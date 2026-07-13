@testable import DevKillerCore
import XCTest

private struct StubCodexLocator: CodexRolloutLocating {
    let lookup: CodexRolloutLookup
    func latestRateLimitLine() -> CodexRolloutLookup { lookup }
}

final class CodexUsageProviderTests: XCTestCase {
    func testNotInstalled() {
        let provider = CodexUsageProvider(locator: StubCodexLocator(lookup: .notInstalled))
        XCTAssertEqual(provider.fetch(), ToolUsage(tool: .codex, state: .notInstalled))
    }

    func testNoData() {
        let provider = CodexUsageProvider(locator: StubCodexLocator(lookup: .noData))
        guard case .unavailable = provider.fetch().state else {
            return XCTFail("expected unavailable")
        }
    }

    func testParsesLine() {
        let line = "{\"timestamp\":\"2026-07-13T14:03:08.874Z\",\"payload\":{\"rate_limits\":{\"primary\":{\"used_percent\":19.0,\"window_minutes\":10080,\"resets_at\":1784495024},\"secondary\":null}}}"
        let provider = CodexUsageProvider(locator: StubCodexLocator(lookup: .line(line)))
        guard case let .available(windows, _) = provider.fetch().state else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(windows.first?.usedPercent, 19.0)
    }
}
