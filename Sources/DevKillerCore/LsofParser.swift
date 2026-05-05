import Foundation

public enum LsofParser {
    public static func parseListeningProcesses(_ output: String) -> [LsofListeningProcess] {
        var records: [LsofListeningProcess] = []
        var pid: Int32?
        var command = ""
        var user: String?

        func resetProcess(nextPID: Int32) {
            pid = nextPID
            command = ""
            user = nil
        }

        for rawLine in output.split(whereSeparator: \.isNewline) {
            guard let field = rawLine.first else { continue }
            let value = String(rawLine.dropFirst())

            switch field {
            case "p":
                if let nextPID = Int32(value) {
                    resetProcess(nextPID: nextPID)
                }
            case "c":
                command = value
            case "L":
                user = value.isEmpty ? nil : value
            case "n":
                guard let pid, let port = extractPort(from: value) else { continue }
                records.append(
                    LsofListeningProcess(
                        pid: pid,
                        command: command.isEmpty ? "unknown" : command,
                        user: user,
                        port: port,
                        endpoint: value
                    )
                )
            default:
                continue
            }
        }

        return records
    }

    private static func extractPort(from nameField: String) -> Int? {
        let endpoint = nameField.split(separator: " ", maxSplits: 1).first.map(String.init) ?? nameField
        guard let colon = endpoint.lastIndex(of: ":") else { return nil }

        let suffix = endpoint[endpoint.index(after: colon)...]
        let digits = suffix.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }

        return Int(digits)
    }
}
