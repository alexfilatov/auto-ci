// Sources/AutoCIApp/AutoCIApp.swift
import SwiftUI
import AutoCICore
import UserNotifications
import ServiceManagement

@main
struct AutoCIApp: App {
    @StateObject private var controller = AppController()
    var body: some Scene {
        MenuBarExtra {
            Text(controller.statusLine).font(.headline)

            if let url = controller.currentRunURL, let link = URL(string: url) {
                Link("View workflow run ↗", destination: link)
            }

            if !controller.setupIssues.isEmpty {
                Divider()
                Text("⚠ Setup required")
                ForEach(controller.setupIssues, id: \.self) { issue in
                    Text(issue)
                }
            }

            Divider()

            Menu("Recent") {
                if controller.groupedHistory.isEmpty {
                    Text("No fixes yet").foregroundStyle(.secondary)
                } else {
                    ForEach(controller.groupedHistory) { group in
                        Menu(group.project) {
                            ForEach(group.entries) { entry in
                                entryView(entry)
                            }
                        }
                    }
                    Divider()
                    Button("Clear History") { controller.clearHistory() }
                }
            }

            Divider()
            Button(controller.launchAtLogin ? "✓ Start at Login" : "Start at Login") {
                controller.toggleLaunchAtLogin()
            }
            Button("About") { controller.showAbout() }
            Button("Quit Auto-CI") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(nsImage: AutoCIIcon(color: controller.state.color).rendered())
        }
        .menuBarExtraStyle(.menu)
    }

    @ViewBuilder
    private func entryView(_ entry: HistoryEntry) -> some View {
        let mark = entry.kind == "fixed" ? "✓" : "⚠"
        let label = "\(mark) \(entry.branch) — \(entry.detail)"
        if let urlString = entry.runURL, let link = URL(string: urlString) {
            Link("\(label) ↗", destination: link)
        } else {
            Text(label)
        }
    }
}

/// The single Auto-CI glyph stays the same in every state — only the color changes.
enum AppState: Equatable {
    case idle, watching, fixing, fixed, attention
    var color: Color {
        switch self {
        case .idle: return .primary
        case .watching: return .blue
        case .fixing: return .orange
        case .fixed: return .green
        case .attention: return .red
        }
    }
}

@MainActor
final class AppController: ObservableObject, Notifier {
    @Published var statusLine = "Idle — watching for pushes"
    @Published var groupedHistory: [ProjectHistory] = []
    @Published var setupIssues: [String] = []
    @Published var state: AppState = .idle
    @Published var currentRunURL: String?
    @Published var launchAtLogin: Bool = false

    private let store = ConfigStore(root: ConfigStore.defaultRoot)
    private let history = HistoryStore(root: ConfigStore.defaultRoot)
    private var listener: PushListener?

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        groupedHistory = history.grouped()
        startListener()
        runDependencyPreflight()
        enableLoginItemOnFirstRun()
        refreshLoginStatus()
    }

    private func refreshLoginStatus() {
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    /// Register as a login item once, so a fresh install auto-starts at boot.
    /// After that we respect whatever the user toggles (SMAppService persists it).
    private func enableLoginItemOnFirstRun() {
        let key = "didInitialLoginRegister"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        try? SMAppService.mainApp.register()
        UserDefaults.standard.set(true, forKey: key)
    }

    func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            statusLine = "Couldn't change login item: \(error.localizedDescription)"
        }
        refreshLoginStatus()
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
            self.state = .attention
            self.statusLine = "Setup required"
            self.setupIssues = problems.map { $0.hint }
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
        state = .watching
        statusLine = "Watching \(branch)…"
        currentRunURL = nil
    }

    private func enterFixing(branch: String, runURL: String) {
        state = .fixing
        statusLine = "Fixing \(branch)…"
        currentRunURL = runURL.isEmpty ? nil : runURL
    }

    private func returnToIdle() {
        state = .idle
        statusLine = "Idle — watching for pushes"
    }

    func clearHistory() {
        history.clear()
        groupedHistory = []
    }

    /// Show a native About popup with readable text and a clickable LinkedIn link.
    func showAbout() {
        let body = NSMutableAttributedString(
            string: "Built by Alex Filatov, who was far too lazy to keep refreshing the "
                  + "Actions tab to see if CI went red again. So now a robot babysits the "
                  + "pipeline and fixes it while he naps. 🛠️😴\n\n",
            attributes: [.foregroundColor: NSColor.labelColor,
                         .font: NSFont.systemFont(ofSize: 11)]
        )
        body.append(NSAttributedString(
            string: "Alex Filatov on LinkedIn ↗",
            attributes: [.link: URL(string: "https://www.linkedin.com/in/alexfilatov/")!,
                         .font: NSFont.systemFont(ofSize: 11)]
        ))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Auto-CI",
            .credits: body,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"):
                "Auto-fixes your CI so you don't have to."
        ])
    }

    nonisolated func notify(_ event: DaemonEvent) {
        Task { await self.notifyAsync(event) }
    }

    func notifyAsync(_ event: DaemonEvent) async {
        let (title, body): (String, String)
        let project: String, branch: String, kind: String, detail: String
        switch event {
        case .fixed(let p, let br, let det):
            (title, body) = ("CI fixed ✓", "\(br): \(det)")
            state = .fixed
            statusLine = title
            (project, branch, kind, detail) = (p, br, "fixed", det)
            // Drop back to idle shortly so the menubar reflects "watching" again.
            scheduleIdleReset()
        case .stuck(let p, let br):
            (title, body) = ("CI stuck — needs you", br)
            state = .attention
            statusLine = title
            (project, branch, kind, detail) = (p, br, "stuck", "stuck — needs you")
        case .gaveUp(let p, let br):
            (title, body) = ("CI fix gave up", br)
            state = .attention
            statusLine = title
            (project, branch, kind, detail) = (p, br, "gaveUp", "fix gave up")
        case .error(let p, let message):
            (title, body) = ("Auto-CI error", message)
            state = .attention
            statusLine = title
            (project, branch, kind, detail) = (p, "", "error", message)
        }

        let entry = HistoryEntry(project: project, branch: branch, kind: kind,
                                 detail: detail, runURL: currentRunURL, timestamp: Date())
        history.record(entry)
        groupedHistory = history.grouped()

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
            // Only reset if nothing newer changed the state to an alert state.
            if self.state == .fixed { self.returnToIdle() }
        }
    }
}

/// Minimal Notifier wrapper for use in detached tasks where AppController cannot be captured directly.
private struct SimpleNotifier: Notifier {
    let fn: @Sendable (DaemonEvent) -> Void
    func notify(_ event: DaemonEvent) { fn(event) }
}
