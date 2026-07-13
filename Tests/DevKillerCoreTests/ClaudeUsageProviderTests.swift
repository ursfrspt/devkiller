@testable import DevKillerCore
import XCTest

private struct StubLocator: ClaudeBinaryLocating {
    let path: String?
    func locate() -> String? { path }
}

private struct StubRunner: CommandRunning {
    let result: Result<String, Error>
    func run(executable: String, arguments: [String], timeout: Duration) throws -> String {
        try result.get()
    }
}

private struct RunnerError: Error {}

private struct TrappingRunner: CommandRunning {
    func run(executable: String, arguments: [String], timeout: Duration) throws -> String {
        XCTFail("runner should not be invoked when binary is not installed")
        return ""
    }
}

final class ClaudeUsageProviderTests: XCTestCase {
    func testNotInstalledWhenBinaryMissing() {
        let provider = ClaudeUsageProvider(
            locator: StubLocator(path: nil),
            runner: TrappingRunner(),
            timeout: .seconds(20)
        )
        XCTAssertEqual(provider.fetch(), ToolUsage(tool: .claudeCode, state: .notInstalled))
    }

    func testParsesRunnerOutput() {
        let provider = ClaudeUsageProvider(
            locator: StubLocator(path: "/bin/claude"),
            runner: StubRunner(result: .success("Current session: 5% used")),
            timeout: .seconds(20)
        )
        guard case let .available(windows, _) = provider.fetch().state else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(windows.first?.usedPercent, 5)
    }

    func testUnavailableWhenRunnerThrows() {
        let provider = ClaudeUsageProvider(
            locator: StubLocator(path: "/bin/claude"),
            runner: StubRunner(result: .failure(RunnerError())),
            timeout: .seconds(20)
        )
        guard case .unavailable = provider.fetch().state else {
            return XCTFail("expected unavailable")
        }
    }
}
