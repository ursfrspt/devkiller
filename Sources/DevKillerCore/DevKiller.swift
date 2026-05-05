import Darwin
import Foundation

public enum DevKillerError: Error, LocalizedError, Hashable, Sendable {
    case lsofFailed(status: Int32, output: String)
    case permissionDenied(pid: Int32)
    case processNotFound(pid: Int32)
    case signalFailed(pid: Int32, errno: Int32)

    public var errorDescription: String? {
        switch self {
        case let .lsofFailed(status, output):
            return "lsof failed with status \(status): \(output)"
        case let .permissionDenied(pid):
            return "Permission denied while terminating process \(pid)."
        case let .processNotFound(pid):
            return "Process \(pid) no longer exists."
        case let .signalFailed(pid, errno):
            return "Failed to terminate process \(pid) with errno \(errno)."
        }
    }
}

public struct TerminationResult: Hashable, Sendable {
    public let pid: Int32
    public let signal: Int32
    public let error: DevKillerError?

    public init(pid: Int32, signal: Int32, error: DevKillerError?) {
        self.pid = pid
        self.signal = signal
        self.error = error
    }

    public var succeeded: Bool { error == nil }
}

public protocol LsofRunning: Sendable {
    func listeningTCPOutput() throws -> String
}

public struct SystemLsofRunner: LsofRunning {
    public init() {}

    public func listeningTCPOutput() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcLn"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus == 0 {
            return output
        }

        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ""
        }

        throw DevKillerError.lsofFailed(status: process.terminationStatus, output: output)
    }
}

public protocol ProcessSignaling: Sendable {
    func send(signal: Int32, to pid: Int32) -> Int32
    var lastErrno: Int32 { get }
}

public struct DarwinProcessSignaler: ProcessSignaling {
    public init() {}

    public func send(signal: Int32, to pid: Int32) -> Int32 {
        Darwin.kill(pid, signal)
    }

    public var lastErrno: Int32 {
        errno
    }
}

public struct DevKiller: Sendable {
    private let lsofRunner: LsofRunning
    private let signaler: ProcessSignaling

    public init(
        lsofRunner: LsofRunning = SystemLsofRunner(),
        signaler: ProcessSignaling = DarwinProcessSignaler()
    ) {
        self.lsofRunner = lsofRunner
        self.signaler = signaler
    }

    public func list(includeLowConfidence: Bool = false) throws -> [DevelopmentServer] {
        let records = LsofParser.parseListeningProcesses(try lsofRunner.listeningTCPOutput())
        let servers = records.map { record in
            DevelopmentServer(
                pid: record.pid,
                command: record.command,
                user: record.user,
                port: record.port,
                endpoint: record.endpoint,
                classification: ServerClassifier.classify(command: record.command, port: record.port)
            )
        }

        var seenIDs = Set<String>()
        let deduplicated = servers.filter { server in
            let key = "\(server.pid):\(server.port)"
            return seenIDs.insert(key).inserted
        }

        let filtered = includeLowConfidence ? deduplicated : deduplicated.filter(\.classification.isLikelyDevelopmentServer)
        return filtered.sorted {
            if $0.port == $1.port {
                return $0.pid < $1.pid
            }
            return $0.port < $1.port
        }
    }

    public func terminate(pid: Int32, force: Bool = false) -> TerminationResult {
        let signal = force ? SIGKILL : SIGTERM
        let result = signaler.send(signal: signal, to: pid)
        guard result != 0 else {
            return TerminationResult(pid: pid, signal: signal, error: nil)
        }

        let error: DevKillerError
        switch signaler.lastErrno {
        case EPERM:
            error = .permissionDenied(pid: pid)
        case ESRCH:
            error = .processNotFound(pid: pid)
        default:
            error = .signalFailed(pid: pid, errno: signaler.lastErrno)
        }

        return TerminationResult(pid: pid, signal: signal, error: error)
    }

    public func terminate(_ server: DevelopmentServer, force: Bool = false) -> TerminationResult {
        terminate(pid: server.pid, force: force)
    }

    public func terminateAll(_ servers: [DevelopmentServer], force: Bool = false) -> [TerminationResult] {
        let uniquePIDs = Array(Set(servers.map(\.pid))).sorted()
        return uniquePIDs.map { terminate(pid: $0, force: force) }
    }
}
