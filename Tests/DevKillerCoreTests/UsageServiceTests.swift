@testable import DevKillerCore
import XCTest

final class UsageServiceTests: XCTestCase {
    func testFetchAllReturnsBothTools() {
        let service = UsageService(
            claude: { ToolUsage(tool: .claudeCode, state: .notInstalled) },
            codex: { ToolUsage(tool: .codex, state: .available(windows: [], asOf: nil)) }
        )
        let all = service.fetchAll()
        XCTAssertEqual(all.map(\.tool), [.claudeCode, .codex])
    }
}
