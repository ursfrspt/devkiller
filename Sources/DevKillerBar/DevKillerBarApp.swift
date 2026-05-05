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
        .menuBarExtraStyle(.menu)

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
        VStack(alignment: .leading, spacing: 0) {
            Button {} label: {
                Label(store.isLoading ? "Checking..." : store.lastCheckedText, systemImage: "clock")
            }
            .disabled(true)

            Divider()

            if !store.servers.isEmpty {
                Button(role: .destructive) {
                    Task { await store.terminateAll() }
                } label: {
                    Label("Kill All Dev Servers", systemImage: "xmark.circle")
                }

                Divider()
            }

            if let message = store.message {
                Text(message)
                    .foregroundStyle(.secondary)
            }

            ForEach(store.servers) { server in
                ServerMenuItem(server: server) {
                    Task { await store.terminate(server) }
                }
            }

            Divider()

            Button("Quit DevKiller") {
                NSApp.terminate(nil)
            }
        }
        .onAppear {
            Task { await store.refresh() }
        }
    }
}

struct ServerMenuItem: View {
    let server: DevelopmentServer
    let terminate: () -> Void

    var body: some View {
        Menu {
            Text("PID \(server.pid)")
            Text(server.endpoint)
            Text(server.classification.confidence.rawValue.capitalized)

            if !server.classification.reasons.isEmpty {
                Divider()
                ForEach(server.classification.reasons, id: \.self) { reason in
                    Text(reason)
                }
            }

            Divider()

            Button(role: .destructive, action: terminate) {
                Label("Kill", systemImage: "xmark.circle")
            }
        } label: {
            Label {
                Text(":\(server.port) \(server.displayName)")
            } icon: {
                Image(systemName: "terminal")
            }
        }
    }
}
