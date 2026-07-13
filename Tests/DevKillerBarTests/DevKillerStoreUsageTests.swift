@testable import DevKillerBar
import DevKillerCore
import XCTest

private struct StubUsageProvider: UsageProviding {
    let usage: [ToolUsage]
    func fetchAll() -> [ToolUsage] { usage }
}

@MainActor
final class DevKillerStoreUsageTests: XCTestCase {
    func testRefreshUsagePopulatesUsage() async {
        let store = DevKillerStore(
            usesSampleServers: true,
            usageProvider: StubUsageProvider(usage: [
                ToolUsage(tool: .claudeCode, state: .available(windows: [], asOf: nil))
            ])
        )
        await store.refreshUsage()
        XCTAssertEqual(store.usage.map(\.tool), [.claudeCode])
        XCTAssertFalse(store.isUsageLoading)
    }
}
