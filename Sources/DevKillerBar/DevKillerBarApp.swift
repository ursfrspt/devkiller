import AppKit
import DevKillerCore
import SwiftUI

@main
struct DevKillerBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = DevKillerStore()

    var body: some Scene {
        MenuBarExtra("DevKiller", systemImage: "bolt.horizontal.circle") {
            DevKillerMenuView(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@MainActor
final class DevKillerStore: ObservableObject {
    @Published var servers: [DevelopmentServer] = []
    @Published var isLoading = false
    @Published var message: String?
    @Published var lastCheckedAt: Date?

    private let devKiller = DevKiller()

    var lastCheckedText: String {
        guard let lastCheckedAt else {
            return "Not checked yet"
        }

        if abs(lastCheckedAt.timeIntervalSinceNow) < 15 {
            return "Updated just now"
        }

        return "Last checked \(lastCheckedAt.formatted(date: .omitted, time: .shortened))"
    }

    func refresh() async {
        guard !isLoading else {
            return
        }

        isLoading = true
        defer { isLoading = false }
        let devKiller = self.devKiller

        do {
            let servers = try await Task.detached {
                try devKiller.list(includeLowConfidence: false)
            }.value

            self.servers = servers
            self.message = servers.isEmpty ? "No dev servers found" : nil
            self.lastCheckedAt = Date()
        } catch {
            self.message = error.localizedDescription
            self.lastCheckedAt = Date()
        }
    }

    func terminate(_ server: DevelopmentServer) async {
        let devKiller = self.devKiller
        let result = await Task.detached {
            devKiller.terminate(server)
        }.value

        if let error = result.error {
            message = error.localizedDescription
        } else {
            message = "Terminated \(server.command) on :\(server.port)"
        }

        await refresh()
    }

    func terminateAll() async {
        let targets = servers
        let devKiller = self.devKiller
        let results = await Task.detached {
            devKiller.terminateAll(targets)
        }.value

        let failures = results.compactMap(\.error)
        if let firstFailure = failures.first {
            message = firstFailure.localizedDescription
        } else {
            message = "Terminated \(results.count) process\(results.count == 1 ? "" : "es")"
        }

        await refresh()
    }
}

struct DevKillerMenuView: View {
    @ObservedObject var store: DevKillerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(store.isLoading ? "Checking..." : store.lastCheckedText)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .font(.caption)

            if !store.servers.isEmpty {
                Button(role: .destructive) {
                    Task { await store.terminateAll() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle")
                            .frame(width: 16)
                        Text("Kill All Dev Servers")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            if let message = store.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(store.servers) { server in
                    ServerMenuItem(server: server) {
                        Task { await store.terminate(server) }
                    }
                }
            }

            Divider()

            Button("Quit DevKiller") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 260)
        .onAppear {
            Task { await store.refresh() }
        }
    }
}

struct ServerMenuItem: View {
    let server: DevelopmentServer
    let terminate: () -> Void

    var body: some View {
        Button(role: .destructive, action: terminate) {
            HStack(spacing: 8) {
                FrameworkIcon(assetName: iconAssetName)
                Text("Kill :\(server.port) \(shortDisplayName)")
                    .lineLimit(1)
                Spacer()
            }
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
    }

    private var shortDisplayName: String {
        let name = server.displayName.lowercased()

        if name.contains("vite") { return "Vite" }
        if name.contains("expo") || name.contains("react native") || name.contains("metro") { return "Expo/Metro" }
        if name.contains("next") { return "Next.js" }
        if name.contains("react") { return "React" }
        if name.contains("node") { return "Node" }
        if name.contains("angular") { return "Angular" }
        if name.contains("astro") { return "Astro" }
        if name.contains("nuxt") { return "Nuxt" }
        if name.contains("storybook") { return "Storybook" }
        if name.contains("python") || name.contains("django") || name.contains("flask") { return "Python" }
        if name.contains("jupyter") { return "Jupyter" }
        if name.contains("rails") || name.contains("ruby") || name.contains("rack") || name.contains("puma") { return "Ruby" }
        if name.contains("php") { return "PHP" }
        if name.contains("java") || name.contains("gradle") || name.contains("jvm") { return "JVM" }
        if name.contains("tauri") { return "Tauri" }
        if name.contains("hugo") { return "Hugo" }

        return server.command
    }

    private var iconAssetName: String? {
        let name = server.displayName.lowercased()
        let command = server.command.lowercased()

        if name.contains("vite") { return "vite" }
        if name.contains("expo") || name.contains("react native") || name.contains("metro") { return "expo" }
        if name.contains("next") { return "nextdotjs" }
        if name.contains("react") { return "react" }
        if name.contains("node") || command.contains("node") { return "nodedotjs" }
        if name.contains("angular") { return "angular" }
        if name.contains("astro") { return "astro" }
        if name.contains("nuxt") { return "nuxt" }
        if name.contains("storybook") { return "storybook" }
        if name.contains("jupyter") { return "jupyter" }
        if name.contains("django") { return "django" }
        if name.contains("flask") { return "flask" }
        if name.contains("python") || command.contains("python") { return "python" }
        if name.contains("rails") { return "rubyonrails" }
        if name.contains("ruby") || name.contains("rack") || name.contains("puma") { return "ruby" }
        if name.contains("php") { return "php" }
        if name.contains("gradle") { return "gradle" }
        if name.contains("java") || name.contains("jvm") { return "openjdk" }
        if name.contains("tauri") { return "tauri" }
        if name.contains("hugo") { return "hugo" }
        if name.contains("bun") || command.contains("bun") { return "bun" }
        if name.contains("deno") || command.contains("deno") { return "deno" }
        if name.contains("webpack") { return "webpack" }

        return nil
    }
}

private struct FrameworkIcon: View {
    let assetName: String?

    var body: some View {
        if let assetName, let bundle = FrameworkIconAssets.bundle, FrameworkIconAssets.contains(assetName, in: bundle) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white)
                Image(assetName, bundle: bundle)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .padding(2)
            }
            .frame(width: 18, height: 18)
        } else {
            Image(systemName: "terminal")
                .frame(width: 18, height: 18)
        }
    }
}

private enum FrameworkIconAssets {
    private static let bundleName = "devkiller_DevKillerBar.bundle"

    static let bundle: Bundle? = {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(bundleName)
        ].compactMap { $0 }

        return candidates.lazy.compactMap { Bundle(url: $0) }.first
    }()

    static func contains(_ assetName: String, in bundle: Bundle) -> Bool {
        bundle.url(forResource: assetName, withExtension: "png") != nil
    }
}
