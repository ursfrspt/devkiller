import DevKillerCore
import Foundation

enum CLI {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let command = arguments.first ?? "list"
        let devKiller = DevKiller()

        do {
            switch command {
            case "list":
                let includeAll = arguments.contains("--all")
                let servers = try devKiller.list(includeLowConfidence: includeAll)
                printList(servers)
            case "kill":
                guard let target = arguments.dropFirst().first else {
                    fail("usage: devkillerctl kill <port|pid> [--force]")
                }

                let force = arguments.contains("--force")
                let servers = try devKiller.list(includeLowConfidence: true)
                let matches = matchingServers(target: target, in: servers)
                guard !matches.isEmpty else {
                    fail("no listening process found for \(target)")
                }

                let results = devKiller.terminateAll(matches, force: force)
                printResults(results)
                if results.contains(where: { !$0.succeeded }) {
                    Foundation.exit(1)
                }
            case "kill-all":
                let force = arguments.contains("--force")
                let servers = try devKiller.list(includeLowConfidence: false)
                let results = devKiller.terminateAll(servers, force: force)
                printResults(results)
                if results.contains(where: { !$0.succeeded }) {
                    Foundation.exit(1)
                }
            case "usage":
                printUsage(UsageService().fetchAll())
            default:
                fail("""
                usage:
                  devkillerctl list [--all]
                  devkillerctl kill <port|pid> [--force]
                  devkillerctl kill-all [--force]
                  devkillerctl usage
                """)
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    private static func printList(_ servers: [DevelopmentServer]) {
        if servers.isEmpty {
            print("No likely development servers found.")
            return
        }

        for server in servers {
            let user = server.user.map { " user=\($0)" } ?? ""
            let reasons = server.classification.reasons.joined(separator: ", ")
            print(
                "port=\(server.port) pid=\(server.pid) command=\(server.command)\(user) " +
                "kind=\"\(server.displayName)\" confidence=\(server.classification.confidence.rawValue) " +
                "endpoint=\"\(server.endpoint)\" reasons=\"\(reasons)\""
            )
        }
    }

    private static func matchingServers(target: String, in servers: [DevelopmentServer]) -> [DevelopmentServer] {
        guard let numericTarget = Int32(target) else {
            return []
        }

        return servers.filter { server in
            server.pid == numericTarget || server.port == Int(numericTarget)
        }
    }

    private static func printResults(_ results: [TerminationResult]) {
        if results.isEmpty {
            print("No processes matched.")
            return
        }

        for result in results {
            if let error = result.error {
                print("pid=\(result.pid) signal=\(result.signal) failed=\"\(error.localizedDescription)\"")
            } else {
                print("pid=\(result.pid) signal=\(result.signal) terminated")
            }
        }
    }

    private static func printUsage(_ usage: [ToolUsage]) {
        for tool in usage {
            let name = tool.tool == .claudeCode ? "claude-code" : "codex"
            switch tool.state {
            case .notInstalled:
                print("\(name): not installed")
            case let .unavailable(reason):
                print("\(name): unavailable (\(reason))")
            case let .available(windows, asOf):
                let asOfText = asOf.map { " asOf=\($0)" } ?? ""
                print("\(name):\(asOfText)")
                for window in windows {
                    let reset = window.resetsAt.map { " resetsAt=\($0)" }
                        ?? window.resetText.map { " resets=\"\($0)\"" }
                        ?? ""
                    print("  \(window.label): \(window.usedPercent)%\(reset)")
                }
            }
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        Foundation.exit(1)
    }
}

CLI.main()
