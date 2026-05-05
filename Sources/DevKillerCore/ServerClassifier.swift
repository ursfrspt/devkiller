import Foundation

public enum ServerClassifier {
    private static let portHints: [Int: String] = [
        3000: "React / Next.js / Node dev server",
        3001: "Node dev server",
        3030: "Node dev server",
        4173: "Vite preview",
        4200: "Angular dev server",
        4321: "Astro dev server",
        5000: "Flask / local web server",
        5001: "local web server",
        5173: "Vite dev server",
        5174: "Vite dev server",
        6006: "Storybook",
        7007: "Storybook",
        8000: "Python / Django / local web server",
        8001: "local web server",
        8080: "local web server",
        8081: "Expo / React Native Metro",
        8082: "Expo / React Native Metro",
        8888: "Jupyter Notebook",
        9000: "local web server",
        9292: "Rack / Ruby web server",
        1313: "Hugo dev server",
        1420: "Tauri dev server",
        19000: "Expo dev server",
        19001: "Expo dev server",
        19002: "Expo dev server",
        24678: "Vite HMR"
    ]

    private static let commandHints: [(needle: String, label: String)] = [
        ("node", "Node.js dev server"),
        ("bun", "Bun dev server"),
        ("deno", "Deno dev server"),
        ("vite", "Vite dev server"),
        ("next", "Next.js dev server"),
        ("astro", "Astro dev server"),
        ("nuxt", "Nuxt dev server"),
        ("webpack", "webpack dev server"),
        ("python", "Python web server"),
        ("uvicorn", "Uvicorn"),
        ("gunicorn", "Gunicorn"),
        ("django", "Django dev server"),
        ("flask", "Flask dev server"),
        ("ruby", "Ruby web server"),
        ("rails", "Rails dev server"),
        ("puma", "Puma / Rails server"),
        ("php", "PHP dev server"),
        ("java", "JVM local server"),
        ("gradle", "Gradle local server"),
        ("cargo", "Rust local server"),
        ("air", "Go air dev server")
    ]

    private static let macOSSystemCommands: Set<String> = [
        "controlcenter",
        "sharingd",
        "rapportd",
        "mDNSResponder".lowercased()
    ]

    public static func classify(command: String, port: Int) -> ServerClassification {
        let normalizedCommand = command.lowercased()
        if macOSSystemCommands.contains(normalizedCommand) {
            return ServerClassification(
                framework: nil,
                confidence: .low,
                reasons: ["macOS system process \(command)"]
            )
        }

        var reasons: [String] = []
        var label: String?
        var score = 0

        if let portLabel = portHints[port] {
            label = portLabel
            score += 2
            reasons.append("common dev port \(port)")
        } else if (1024...10000).contains(port) {
            score += 1
            reasons.append("user-space local port \(port)")
        }

        if let commandHint = commandHints.first(where: { normalizedCommand.contains($0.needle) }) {
            if label == nil || !["node", "bun", "deno"].contains(commandHint.needle) {
                label = commandHint.label
            }
            score += 2
            reasons.append("process command matches \(commandHint.needle)")
        }

        let confidence: ServerClassification.Confidence
        switch score {
        case 4...:
            confidence = .high
        case 2...:
            confidence = .medium
        default:
            confidence = .low
        }

        return ServerClassification(framework: label, confidence: confidence, reasons: reasons)
    }
}
