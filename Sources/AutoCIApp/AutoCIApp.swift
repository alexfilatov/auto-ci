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

            if let url = controller.currentRunURL, let link = URL(string: url) {
                Link("View workflow run ↗", destination: link)
            }

            Divider()

            if controller.recent.isEmpty {
                Text("No activity yet").foregroundStyle(.secondary)
            } else {
                ForEach(controller.recent) { item in
                    if let urlString = item.url, let link = URL(string: urlString) {
                        Link("\(item.text) ↗", destination: link)
                    } else {
                        Text(item.text)
                    }
                }
            }

            Divider()
            Button("Quit Auto-CI") { NSApplication.shared.terminate(nil) }
        }
    }
}

/// One line in the "recent activity" list, optionally linking to a GitHub run.
struct RecentItem: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let url: String?
}

@MainActor
final class AppController: ObservableObject, Notifier {
    // Icons read clearly at a glance: idle vs actively watching/fixing vs needs-you.
    enum Icon {
        static let idle = "wrench.and.screwdriver"
        static let watching = "eye.fill"
        static let fixing = "wrench.and.screwdriver.fill"
        static let fixed = "checkmark.circle.fill"
        static let attention = "exclamationmark.triangle.fill"
    }

    @Published var statusLine = "Idle — watching for pushes"
    @Published var recent: [RecentItem] = []
    @Published var iconName = Icon.idle
    @Published var currentRunURL: String?

    private let store = ConfigStore(root: ConfigStore.defaultRoot)
    private var listener: PushListener?

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        startListener()
        runDependencyPreflight()
    }

    /// On launch, surface missing/unauthenticated CLI dependencies as a "setup required" state.
    private func runDependencyPreflight() {
        Task { [weak self] in
            let statuses = await Task.detached { @Sendable in
                DependencyChecker(runner: ProcessCommandRunner()).check()
            }.value
            guard let self else { return }
            let problems = statuses.filter { !$0.ok }
            guard !problems.isEmpty else { return }
            self.iconName = Icon.attention
            self.statusLine = "Setup required"
            self.recent = problems.map { RecentItem(text: $0.hint, url: nil) }
        }
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
        enterWatching(branch: event.branch)

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
        let enterFixingFn: @Sendable (String) -> Void = { [weak self] url in
            Task { await self?.enterFixing(branch: eventBranch, runURL: url) }
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
                enterFixingFn(firstFailure.url)
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

    private func enterWatching(branch: String) {
        iconName = Icon.watching
        statusLine = "Watching \(branch)…"
        currentRunURL = nil
    }

    private func enterFixing(branch: String, runURL: String) {
        iconName = Icon.fixing
        statusLine = "Fixing \(branch)…"
        currentRunURL = runURL.isEmpty ? nil : runURL
    }

    private func returnToIdle() {
        iconName = Icon.idle
        statusLine = "Idle — watching for pushes"
    }

    nonisolated func notify(_ event: DaemonEvent) {
        Task { await self.notifyAsync(event) }
    }

    func notifyAsync(_ event: DaemonEvent) async {
        let (title, body): (String, String)
        switch event {
        case .fixed(_, let branch, let detail):
            (title, body) = ("CI fixed ✓", "\(branch): \(detail)")
            iconName = Icon.fixed
            statusLine = title
            // Drop back to idle shortly so the menubar reflects "watching" again.
            scheduleIdleReset()
        case .stuck(_, let branch):
            (title, body) = ("CI stuck — needs you", branch)
            iconName = Icon.attention
            statusLine = title
        case .gaveUp(_, let branch):
            (title, body) = ("CI fix gave up", branch)
            iconName = Icon.attention
            statusLine = title
        case .error(_, let message):
            (title, body) = ("Auto-CI error", message)
            iconName = Icon.attention
            statusLine = title
        }

        recent.insert(RecentItem(text: "\(title) — \(body)", url: currentRunURL), at: 0)
        recent = Array(recent.prefix(10))

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
    }

    private func scheduleIdleReset() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self else { return }
            // Only reset if nothing newer changed the icon to an alert state.
            if self.iconName == Icon.fixed { self.returnToIdle() }
        }
    }
}

/// Minimal Notifier wrapper for use in detached tasks where AppController cannot be captured directly.
private struct SimpleNotifier: Notifier {
    let fn: @Sendable (DaemonEvent) -> Void
    func notify(_ event: DaemonEvent) { fn(event) }
}
