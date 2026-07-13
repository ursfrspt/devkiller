import Foundation

public protocol UsageProviding: Sendable {
    func fetchAll() -> [ToolUsage]
}

public struct UsageService: UsageProviding {
    private let claude: @Sendable () -> ToolUsage
    private let codex: @Sendable () -> ToolUsage

    public init(
        claude: @escaping @Sendable () -> ToolUsage,
        codex: @escaping @Sendable () -> ToolUsage
    ) {
        self.claude = claude
        self.codex = codex
    }

    public init(timeout: Duration = .seconds(20)) {
        let claudeProvider = ClaudeUsageProvider(
            locator: SystemClaudeLocator(),
            runner: SystemCommandRunner(),
            timeout: timeout
        )
        let codexProvider = CodexUsageProvider(locator: SystemCodexRolloutLocator())
        self.claude = { claudeProvider.fetch() }
        self.codex = { codexProvider.fetch() }
    }

    public func fetchAll() -> [ToolUsage] {
        // Run both providers concurrently so a slow/hanging Claude CLI fetch
        // doesn't delay returning Codex's already-available data. Results are
        // written into fixed index slots so the returned order stays
        // [claude, codex] regardless of which finishes first.
        var results: [ToolUsage?] = [nil, nil]
        let lock = NSLock()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.claude()
            lock.lock()
            results[0] = result
            lock.unlock()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.codex()
            lock.lock()
            results[1] = result
            lock.unlock()
            group.leave()
        }

        group.wait()
        return results.compactMap { $0 }
    }
}

public struct SystemClaudeLocator: ClaudeBinaryLocating {
    public init() {}

    public func locate() -> String? {
        ClaudeBinaryDiscovery.locate(
            candidates: ClaudeBinaryDiscovery.defaultCandidates,
            fileExists: { FileManager.default.isExecutableFile(atPath: $0) },
            shellLookup: Self.shellLookup
        )
    }

    private static func shellLookup() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", "command -v claude"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

public struct SystemCommandRunner: CommandRunning {
    public init() {}

    public func run(executable: String, arguments: [String], timeout: Duration) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        let readHandle = pipe.fileHandleForReading
        let bufferLock = NSLock()
        var buffer = Data()
        readHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            bufferLock.lock()
            buffer.append(chunk)
            bufferLock.unlock()
        }

        try process.run()

        let deadline = Date().addingTimeInterval(Double(timeout.components.seconds))
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            readHandle.readabilityHandler = nil
            throw UsageRunnerError.timedOut
        }

        readHandle.readabilityHandler = nil
        let remainder = readHandle.availableData
        bufferLock.lock()
        if !remainder.isEmpty {
            buffer.append(remainder)
        }
        let data = buffer
        bufferLock.unlock()

        return String(data: data, encoding: .utf8) ?? ""
    }
}

public enum UsageRunnerError: Error {
    case timedOut
}

public struct SystemCodexRolloutLocator: CodexRolloutLocating {
    public init() {}

    public func latestRateLimitLine() -> CodexRolloutLookup {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sessions = home.appendingPathComponent(".codex/sessions")
        guard FileManager.default.fileExists(atPath: home.appendingPathComponent(".codex").path) else {
            return .notInstalled
        }
        guard let newest = newestRollout(in: sessions),
              let line = lastRateLimitLine(in: newest) else {
            return .noData
        }
        return .line(line)
    }

    private func newestRollout(in root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }

        var newest: URL?
        var newestDate = Date.distantPast
        for case let url as URL in enumerator where url.lastPathComponent.hasPrefix("rollout-") {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if date > newestDate {
                newestDate = date
                newest = url
            }
        }
        return newest
    }

    private func lastRateLimitLine(in file: URL) -> String? {
        guard let contents = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return contents
            .split(whereSeparator: \.isNewline)
            .last { $0.contains("\"rate_limits\"") }
            .map(String.init)
    }
}
