import Foundation

public enum UsageTool: String, Sendable {
    case claudeCode
    case codex
}

public enum WindowKind: Sendable, Equatable {
    case fiveHour
    case weekly
}

public enum UsageSeverity: Sendable, Equatable {
    case normal
    case warning
    case critical
}

public func usageSeverity(_ percent: Double) -> UsageSeverity {
    if percent > 90 { return .critical }
    if percent >= 70 { return .warning }
    return .normal
}

public func isUsageStale(asOf: Date, now: Date, threshold: TimeInterval = 24 * 3600) -> Bool {
    now.timeIntervalSince(asOf) > threshold
}

public struct UsageWindow: Sendable, Equatable {
    public let kind: WindowKind
    public let label: String
    public let usedPercent: Double
    public let resetsAt: Date?
    public let resetText: String?

    public init(kind: WindowKind, label: String, usedPercent: Double, resetsAt: Date?, resetText: String?) {
        self.kind = kind
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.resetText = resetText
    }

    public var severity: UsageSeverity { usageSeverity(usedPercent) }
}

public enum ToolUsageState: Sendable, Equatable {
    case available(windows: [UsageWindow], asOf: Date?)
    case notInstalled
    case unavailable(reason: String)
}

public struct ToolUsage: Sendable, Equatable {
    public let tool: UsageTool
    public let state: ToolUsageState

    public init(tool: UsageTool, state: ToolUsageState) {
        self.tool = tool
        self.state = state
    }
}
