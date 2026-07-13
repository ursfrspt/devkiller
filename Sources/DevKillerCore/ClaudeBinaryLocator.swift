import Foundation

public protocol ClaudeBinaryLocating: Sendable {
    func locate() -> String?
}

public enum ClaudeBinaryDiscovery {
    public static func locate(
        candidates: [String],
        fileExists: (String) -> Bool,
        shellLookup: () -> String?
    ) -> String? {
        for candidate in candidates where fileExists(candidate) {
            return candidate
        }
        if let resolved = shellLookup()?.trimmingCharacters(in: .whitespacesAndNewlines),
           !resolved.isEmpty,
           fileExists(resolved) {
            return resolved
        }
        return nil
    }

    public static var defaultCandidates: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var paths = [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude"
        ]
        // nvm-installed node bin dirs
        let nvmVersions = "\(home)/.nvm/versions/node"
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: nvmVersions) {
            paths.append(contentsOf: entries.map { "\(nvmVersions)/\($0)/bin/claude" })
        }
        return paths
    }
}
