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
            (Text(controller.state.dotEmoji).font(.system(size: 8))
             + Text("  \(controller.statusLine)").font(.headline))

            if let url = controller.currentRunURL, let link = URL(string: url) {
                Link("View workflow run ↗", destination: link)
            }

            if controller.lastError != nil {
                Button("Show error details…") { controller.showErrorDetails() }
            }

            if !controller.setupIssues.isEmpty {
                Divider()
                Text("⚠ Setup required")
                ForEach(controller.setupIssues, id: \.self) { issue in
                    Text(issue)
                }
            }

            Divider()

            Menu("Projects") {
                if controller.projects.isEmpty {
                    Text("None — run `auto-ci init` in a repo").foregroundStyle(.secondary)
                } else {
                    ForEach(controller.projects, id: \.name) { project in
                        Menu(project.name) {
                            Button("Stop watching") { controller.stopWatching(project) }
                        }
                    }
                }
            }

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
            SettingsLink { Text("Settings…") }
            Button("About") { controller.showAbout() }
            Button("Quit Auto-CI") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(nsImage: AutoCIIcon(color: controller.state.color)
                .rendered(template: controller.state == .idle))
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(controller: controller)
        }
    }

    @ViewBuilder
    private func entryView(_ entry: HistoryEntry) -> some View {
        let mark = entry.kind == "fixed" ? "✓" : entry.kind == "deferred" ? "⏸" : "⚠"
        let label = "\(mark) \(entry.branch) — \(entry.detail)"
        if let urlString = entry.runURL, let link = URL(string: urlString) {
            Link("\(label) ↗", destination: link)
        } else {
            Text(label)
        }
    }
}

/// UI presentation for the Core CIState. The glyph is identical in every state — only color changes.
extension CIState {
    var color: Color {
        switch self {
        case .idle: return .black   // template image → auto-tinted by the menu bar
        case .watching: return .blue
        case .fixing: return .orange
        case .fixed: return .green
        case .attention: return .red
        }
    }

    var isActive: Bool { self == .watching || self == .fixing }

    /// A colored status dot that renders reliably in color inside native UI.
    var dotEmoji: String {
        switch self {
        case .watching: return "🔵"
        case .fixing: return "🟠"
        case .fixed: return "🟢"
        case .attention: return "🔴"
        case .idle: return "⚪️"
        }
    }
}

@MainActor
final class AppController: ObservableObject, Notifier {
    /// Per-project live state — the source of truth for the grid.
    @Published var projectStates: [String: ProjectLiveState] = [:]
    /// App-level status message (setup/login errors), shown when no per-project context applies.
    @Published var statusLine = "Idle — watching for pushes"
    @Published var groupedHistory: [ProjectHistory] = []
    @Published var setupIssues: [String] = []
    @Published var launchAtLogin: Bool = false
    @Published var projects: [ProjectConfig] = []
    @Published var lastError: String?
    @Published var lastErrorURL: String?

    /// Worst state across all projects; drives the menubar glyph color + summary bar.
    /// Setup issues (missing gh/claude) force attention so the menubar signals it.
    var state: CIState {
        if !setupIssues.isEmpty { return .attention }
        return worstState(projectStates.values.map { $0.state })
    }

    /// The live state for a project (idle default if unseen).
    func liveState(_ project: String) -> ProjectLiveState { projectStates[project] ?? ProjectLiveState() }

    /// Convenience for the currently-active run URL (first project that has one).
    var currentRunURL: String? { projectStates.values.compactMap { $0.runURL }.first }

    private let store = ConfigStore(root: ConfigStore.defaultRoot)
    private let history = HistoryStore(root: ConfigStore.defaultRoot)
    private let leases = LeaseStore(root: ConfigStore.defaultRoot)
    /// Default UI hold duration (mirrors the CLI default).
    private static let holdMinutes = 30
    private var listener: PushListener?
    private var configTimer: Timer?

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        groupedHistory = history.grouped()
        projects = store.projects()
        startListener()
        startConfigWatch()
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
            self.statusLine = "Setup required"
            self.setupIssues = problems.map { $0.hint }
        }
    }

    /// Poll ~/.auto-ci so the menu reflects changes made by the CLI (e.g. `auto-ci init`
    /// in another repo) without an app restart. A poll is more reliable than a file
    /// watcher here because `config.json` is rewritten in place, which a directory
    /// vnode watch doesn't reliably report.
    private func startConfigWatch() {
        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reloadFromDisk() }
        }
        RunLoop.main.add(timer, forMode: .common)
        configTimer = timer
    }

    /// Reload from disk, republishing only when something actually changed (avoids menu churn).
    private func reloadFromDisk() {
        store.reload()
        let latest = store.projects()
        if latest != projects { projects = latest }
        let groups = history.grouped()
        if groups != groupedHistory { groupedHistory = groups }
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
        enterWatching(project: config.name, branch: event.branch)

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
        let eventProject = configCopy.name
        let enterFixingFn: @Sendable (String) -> Void = { [weak self] url in
            Task { await self?.enterFixing(project: eventProject, branch: eventBranch, runURL: url) }
        }
        let enterHoldingFn: @Sendable () -> Void = { [weak self] in
            Task { await self?.enterHolding(project: eventProject, branch: eventBranch, graceSeconds: configCopy.graceSeconds) }
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

                // Grace gate: auto-ci is a secondary fixer. Wait out the grace period and
                // defer if a human (or another agent) is already handling this failure.
                enterHoldingFn()
                let gate = GraceGate(git: GitClient(runner: runner),
                                     leases: LeaseStore(root: ConfigStore.defaultRoot),
                                     graceSeconds: configCopy.graceSeconds)
                switch gate.evaluate(project: configCopy.name, branch: eventBranch,
                                     failedSHA: eventSha, cwd: clone) {
                case .deferred(let reason):
                    notifyFn(.deferred(project: configCopy.name, branch: eventBranch, reason: reason))
                    return
                case .proceed:
                    break
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

    private func enterWatching(project: String, branch: String) {
        projectStates[project] = ProjectLiveState(
            state: .watching, statusLine: "Watching \(project)/\(branch)…", branch: branch)
        lastError = nil; lastErrorURL = nil
    }

    /// Show the last error in a readable popup, with a button to open the workflow run if known.
    func showErrorDetails() {
        guard let err = lastError else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Auto-CI error"
        alert.informativeText = err
        let hasURL = lastErrorURL != nil
        if hasURL { alert.addButton(withTitle: "Open workflow run") }
        alert.addButton(withTitle: "Close")
        let response = alert.runModal()
        if hasURL, response == .alertFirstButtonReturn,
           let urlString = lastErrorURL, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Saw a failure but holding back during the grace period. Stays benign (watching).
    private func enterHolding(project: String, branch: String, graceSeconds: Int) {
        projectStates[project] = ProjectLiveState(
            state: .watching,
            statusLine: "CI failed on \(project)/\(branch) — waiting \(graceSeconds)s to see if it's handled…",
            branch: branch)
    }

    private func enterFixing(project: String, branch: String, runURL: String) {
        projectStates[project] = ProjectLiveState(
            state: .fixing, statusLine: "Fixing \(project)/\(branch)…",
            runURL: runURL.isEmpty ? nil : runURL, branch: branch)
    }

    private func returnToIdle(project: String) {
        if var s = projectStates[project] {
            s.state = .idle; s.statusLine = "Idle — watching for pushes"; s.runURL = nil
            projectStates[project] = s
        }
    }

    func clearHistory() {
        history.clear()
        groupedHistory = []
    }

    /// The branch a Hold/Release acts on for a project: its active/most-recent branch.
    func activeBranch(_ project: String) -> String? { liveState(project).branch }

    /// True if the project's active branch is currently held.
    func isHeld(_ project: String) -> Bool {
        guard let branch = activeBranch(project) else { return false }
        return leases.isHeld(project: project, branch: branch)
    }

    /// Claim the project's active branch so auto-ci stands down. No-op if no branch is known.
    func holdActiveBranch(_ project: String) {
        guard let branch = activeBranch(project) else { return }
        leases.hold(project: project, branch: branch, minutes: Self.holdMinutes)
        objectWillChange.send()
    }

    /// Release the hold on the project's active branch.
    func releaseActiveBranch(_ project: String) {
        guard let branch = activeBranch(project) else { return }
        leases.release(project: project, branch: branch)
        objectWillChange.send()
    }

    /// Stop watching a project: remove its pre-push hook and unregister it (no CLI needed).
    func stopWatching(_ project: ProjectConfig) {
        _ = try? HookInstaller().uninstall(repoPath: project.path)
        store.reload()
        try? store.remove(named: project.name)
        projects = store.projects()
    }

    func updateProject(_ config: ProjectConfig) {
        store.reload()
        try? store.upsert(config)
        projects = store.projects()
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
            (title, body) = ("CI fixed ✓", "\(p)/\(br): \(det)")
            projectStates[p] = ProjectLiveState(state: .fixed, statusLine: "CI fixed ✓ — \(p)/\(br)",
                                                runURL: liveState(p).runURL, branch: br)
            (project, branch, kind, detail) = (p, br, "fixed", det)
            scheduleIdleReset(project: p)
        case .stuck(let p, let br):
            (title, body) = ("CI stuck — needs you", "\(p)/\(br)")
            projectStates[p] = ProjectLiveState(state: .attention,
                                                statusLine: "CI stuck — needs you: \(p)/\(br)",
                                                runURL: liveState(p).runURL, branch: br)
            (project, branch, kind, detail) = (p, br, "stuck", "stuck — needs you")
        case .gaveUp(let p, let br):
            (title, body) = ("CI fix gave up", "\(p)/\(br)")
            projectStates[p] = ProjectLiveState(state: .attention,
                                                statusLine: "CI fix gave up: \(p)/\(br)",
                                                runURL: liveState(p).runURL, branch: br)
            (project, branch, kind, detail) = (p, br, "gaveUp", "fix gave up")
        case .error(let p, let message):
            (title, body) = ("Auto-CI error", "\(p): \(message)")
            projectStates[p] = ProjectLiveState(state: .attention, statusLine: "Auto-CI error — \(p)",
                                                runURL: liveState(p).runURL, branch: liveState(p).branch)
            lastError = message
            lastErrorURL = liveState(p).runURL
            (project, branch, kind, detail) = (p, "", "error", message)
        case .deferred(let p, let br, let reason):
            (title, body) = ("Auto-CI stood down", "\(p)/\(br): \(reason)")
            projectStates[p] = ProjectLiveState(state: .idle,
                                                statusLine: "Stood down — \(p)/\(br) is being fixed elsewhere",
                                                branch: br)
            (project, branch, kind, detail) = (p, br, "deferred", reason)
        }

        let entry = HistoryEntry(project: project, branch: branch, kind: kind,
                                 detail: detail, runURL: liveState(project).runURL, timestamp: Date())
        history.record(entry)
        groupedHistory = history.grouped()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
    }

    private func scheduleIdleReset(project: String) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self else { return }
            if self.liveState(project).state == .fixed { self.returnToIdle(project: project) }
        }
    }
}

/// Minimal Notifier wrapper for use in detached tasks where AppController cannot be captured directly.
private struct SimpleNotifier: Notifier {
    let fn: @Sendable (DaemonEvent) -> Void
    func notify(_ event: DaemonEvent) { fn(event) }
}
