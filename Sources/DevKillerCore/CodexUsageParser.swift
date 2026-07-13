import Foundation

public enum CodexUsageParser {
    private struct RolloutLine: Decodable {
        let timestamp: String?
        let payload: Payload?
    }

    private struct Payload: Decodable {
        let rate_limits: RateLimits?
    }

    private struct RateLimits: Decodable {
        let primary: Window?
        let secondary: Window?
    }

    private struct Window: Decodable {
        let used_percent: Double?
        let window_minutes: Int?
        let resets_at: Double?
    }

    public static func parse(_ rolloutLine: String) -> ToolUsageState {
        guard let data = rolloutLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RolloutLine.self, from: data),
              let limits = decoded.payload?.rate_limits else {
            return .unavailable(reason: "No Codex rate limit data")
        }

        let parsed = [limits.primary, limits.secondary]
            .compactMap { $0 }
            .compactMap(window(from:))
            .sorted { lhs, rhs in kindRank(lhs.kind) < kindRank(rhs.kind) }

        if parsed.isEmpty {
            return .unavailable(reason: "No Codex rate limit data")
        }

        let asOf = decoded.timestamp.flatMap { ISO8601DateFormatter().date(from: $0) }
        return .available(windows: parsed, asOf: asOf)
    }

    private static func window(from window: Window) -> UsageWindow? {
        guard let percent = window.used_percent else { return nil }
        let isFiveHour = window.window_minutes == 300
        let kind: WindowKind = isFiveHour ? .fiveHour : .weekly
        let label = isFiveHour ? "5h" : "Week"
        let resetsAt = window.resets_at.map { Date(timeIntervalSince1970: $0) }
        return UsageWindow(kind: kind, label: label, usedPercent: percent, resetsAt: resetsAt, resetText: nil)
    }

    private static func kindRank(_ kind: WindowKind) -> Int {
        kind == .fiveHour ? 0 : 1
    }
}
