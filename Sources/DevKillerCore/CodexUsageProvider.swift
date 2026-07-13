import Foundation

public enum CodexRolloutLookup: Sendable, Equatable {
    case notInstalled
    case noData
    case line(String)
}

public protocol CodexRolloutLocating: Sendable {
    func latestRateLimitLine() -> CodexRolloutLookup
}

public struct CodexUsageProvider {
    private let locator: CodexRolloutLocating

    public init(locator: CodexRolloutLocating) {
        self.locator = locator
    }

    public func fetch() -> ToolUsage {
        switch locator.latestRateLimitLine() {
        case .notInstalled:
            return ToolUsage(tool: .codex, state: .notInstalled)
        case .noData:
            return ToolUsage(tool: .codex, state: .unavailable(reason: "No recent Codex usage"))
        case let .line(line):
            return ToolUsage(tool: .codex, state: CodexUsageParser.parse(line))
        }
    }
}
