// Sources/AutoCIApp/AutoCIApp.swift
import SwiftUI
import AutoCICore
import UserNotifications

@main
struct AutoCIApp: App {
    @StateObject private var controller = AppController()
    var body: some Scene {
        MenuBarExtra("Auto-CI", systemImage: controller.iconName) {
            Text(controller.statusLine).font(.headline)
            Divider()
            ForEach(controller.recent, id: \.self) { Text($0) }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}

@MainActor
final class AppController: ObservableObject, Notifier {
    @Published var statusLine = "Idle"
    @Published var recent: [String] = []
    @Published var iconName = "wrench.and.screwdriver"

    private let store = ConfigStore(root: ConfigStore.defaultRoot)
    private var listener: PushListener?

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        startListener()
    }

    private func startListener() {
        let socketPath = ConfigStore.defaultRoot.appendingPathComponent("daemon.sock").path
        let listener = PushListener(socketPath: socketPath) { [weak self] event in
            Task { await self?.handle(event) }
        }
        try? listener.start()
        self.listener = listener
    }

    private func handle(_ event: PushEvent) async {
        guard let config = store.project(named: event.project) else { return }
        self.statusLine = "Watching \(event.branch)…"
        let runner = ProcessCommandRunner()
        let workflowYAML = (try? String(contentsOfFile: config.path + "/.github/workflows/ci.yml", encoding: .utf8)) ?? ""
        let github = GitHubClient(runner: runner)
        let watcher = RunWatcher(github: github)
        let configCopy = config
        let eventBranch = event.branch
        let eventSha = event.sha
        let notifyFn: @Sendable (DaemonEvent) -> Void = { [weak self] ev in
            Task { await self?.notifyAsync(ev) }
        }
        await Task.detached { @Sendable in
            do {
                let clone = ClonePool(root: ConfigStore.defaultRoot, git: GitClient(runner: runner))
                    .cloneDir(project: configCopy.name)
                _ = try? GitClient(runner: runner).cloneOrFetch(remoteURL: configCopy.remote, into: clone)
                let failures = try watcher.waitForTerminal(sha: eventSha, cwd: clone)
                guard let firstFailure = failures.first else {
                    notifyFn(.fixed(project: configCopy.name, branch: eventBranch, detail: "green, nothing to do"))
                    return
                }
                let engine = LiveFixEngine(config: configCopy, root: ConfigStore.defaultRoot,
                                           runner: runner, workflowYAML: workflowYAML)
                let daemon = Daemon(notifier: SimpleNotifier(fn: notifyFn), engine: engine)
                _ = daemon.handleFailedRun(project: configCopy.name, branch: eventBranch,
                                           sha: eventSha, failedRun: firstFailure)
            } catch {
                notifyFn(.error(project: configCopy.name, message: "\(error)"))
            }
        }.value
    }

    nonisolated func notify(_ event: DaemonEvent) {
        Task { await self.notifyAsync(event) }
    }

    func notifyAsync(_ event: DaemonEvent) async {
        let (title, body): (String, String)
        switch event {
        case .fixed(_, let branch, let detail): (title, body) = ("CI fixed ✓", "\(branch): \(detail)")
        case .stuck(_, let branch): (title, body) = ("CI stuck — needs you", branch)
        case .gaveUp(_, let branch): (title, body) = ("CI fix gave up", branch)
        case .error(_, let message): (title, body) = ("Auto-CI error", message)
        }
        self.statusLine = title
        self.recent.insert("\(title) — \(body)", at: 0)
        self.recent = Array(self.recent.prefix(10))
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
    }
}

/// Minimal Notifier wrapper for use in detached tasks where AppController cannot be captured directly.
private struct SimpleNotifier: Notifier {
    let fn: @Sendable (DaemonEvent) -> Void
    func notify(_ event: DaemonEvent) { fn(event) }
}
