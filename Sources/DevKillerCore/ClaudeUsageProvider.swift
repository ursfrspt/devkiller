import Foundation

public protocol CommandRunning: Sendable {
    func run(executable: String, arguments: [String], timeout: Duration) throws -> String
}

public struct ClaudeUsageProvider {
    private let locator: ClaudeBinaryLocating
    private let runner: CommandRunning
    private let timeout: Duration

    public init(locator: ClaudeBinaryLocating, runner: CommandRunning, timeout: Duration) {
        self.locator = locator
        self.runner = runner
        self.timeout = timeout
    }

    public func fetch() -> ToolUsage {
        guard let executable = locator.locate() else {
            return ToolUsage(tool: .claudeCode, state: .notInstalled)
        }
        do {
            let output = try runner.run(
                executable: executable,
                arguments: ["-p", "/usage", "--output-format", "text"],
                timeout: timeout
            )
            return ToolUsage(tool: .claudeCode, state: ClaudeUsageParser.parse(output))
        } catch {
            return ToolUsage(tool: .claudeCode, state: .unavailable(reason: "Claude usage unavailable"))
        }
    }
}
