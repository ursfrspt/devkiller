import Foundation

public enum ClaudeUsageParser {
    public static func parse(_ output: String) -> ToolUsageState {
        var windows: [UsageWindow] = []

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let window = parseLine(line) else { continue }
            windows.append(window)
        }

        if windows.isEmpty {
            return .unavailable(reason: "Could not read Claude usage")
        }
        return .available(windows: windows, asOf: nil)
    }

    private static func parseLine(_ line: String) -> UsageWindow? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let head = String(line[line.startIndex..<colon])
        let rest = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)

        let kind: WindowKind
        let label: String
        if head == "Current session" {
            kind = .fiveHour
            label = "5h"
        } else if head.hasPrefix("Current week") {
            kind = .weekly
            // "Current week (all models)" -> "Week (all models)"
            label = "Week" + head.dropFirst("Current week".count)
        } else {
            return nil
        }

        // rest looks like "5% used · resets Jul 14 at 3:49am (Asia/Seoul)"
        guard let percentEnd = rest.firstIndex(of: "%") else { return nil }
        guard let percent = Double(rest[rest.startIndex..<percentEnd]) else { return nil }

        var resetText: String?
        if let resetsRange = rest.range(of: "resets ") {
            let text = String(rest[resetsRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            resetText = text.isEmpty ? nil : text
        }

        return UsageWindow(kind: kind, label: label, usedPercent: percent, resetsAt: nil, resetText: resetText)
    }
}
