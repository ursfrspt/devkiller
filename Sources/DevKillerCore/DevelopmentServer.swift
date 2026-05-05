import Foundation

public struct DevelopmentServer: Identifiable, Hashable, Sendable {
    public var id: String { "\(pid):\(port)" }

    public let pid: Int32
    public let command: String
    public let user: String?
    public let port: Int
    public let endpoint: String
    public let classification: ServerClassification

    public init(
        pid: Int32,
        command: String,
        user: String?,
        port: Int,
        endpoint: String,
        classification: ServerClassification
    ) {
        self.pid = pid
        self.command = command
        self.user = user
        self.port = port
        self.endpoint = endpoint
        self.classification = classification
    }

    public var displayName: String {
        if let framework = classification.framework {
            return framework
        }
        return command
    }
}

public struct ServerClassification: Hashable, Sendable {
    public enum Confidence: String, Sendable {
        case low
        case medium
        case high
    }

    public let framework: String?
    public let confidence: Confidence
    public let reasons: [String]

    public init(framework: String?, confidence: Confidence, reasons: [String]) {
        self.framework = framework
        self.confidence = confidence
        self.reasons = reasons
    }

    public var isLikelyDevelopmentServer: Bool {
        confidence == .medium || confidence == .high
    }
}

public struct LsofListeningProcess: Hashable, Sendable {
    public let pid: Int32
    public let command: String
    public let user: String?
    public let port: Int
    public let endpoint: String

    public init(pid: Int32, command: String, user: String?, port: Int, endpoint: String) {
        self.pid = pid
        self.command = command
        self.user = user
        self.port = port
        self.endpoint = endpoint
    }
}
