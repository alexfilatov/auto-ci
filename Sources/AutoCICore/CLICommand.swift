// Sources/AutoCICore/CLICommand.swift
import Foundation

public struct CLICommand: Sendable {
    private let store: ConfigStore
    private let runner: CommandRunner
    private let hookInstaller: HookInstaller
    private let socketPath: String
    private let fixRunner: (@Sendable (ProjectConfig, _ sha: String, _ branch: String) -> String)?
    public init(store: ConfigStore, runner: CommandRunner, hookInstaller: HookInstaller, socketPath: String,
                fixRunner: (@Sendable (ProjectConfig, _ sha: String, _ branch: String) -> String)? = nil) {
        self.store = store; self.runner = runner; self.hookInstaller = hookInstaller; self.socketPath = socketPath
        self.fixRunner = fixRunner
    }

    public func run(_ args: [String], cwd: String) throws -> String {
        guard let cmd = args.first else { return usage() }
        switch cmd {
        case "init":
            let name = (cwd as NSString).lastPathComponent
            let remote = try runner.run("git", ["remote", "get-url", "origin"], cwd: cwd, stdin: nil, env: nil)
                .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let project = ProjectConfig(name: name, path: cwd, remote: remote)
            try store.upsert(project)
            try hookInstaller.install(repoPath: cwd, socketPath: socketPath, project: name)
            var message = "Registered \(name) (\(remote)) and installed pre-push hook."
            let checker = DependencyChecker(runner: runner)
            let problems = checker.check().filter { !$0.ok }
            if !problems.isEmpty {
                message += "\n\nWarning: some dependencies need attention before auto-ci can fix runs:"
                for p in problems {
                    message += "\n  - \(p.name): \(p.hint)"
                }
            }
            return message
        case "list":
            let names = store.projects().map { "\($0.name)\t\($0.remote)" }
            return names.isEmpty ? "No projects registered." : names.joined(separator: "\n")
        case "uninstall":
            let name = (cwd as NSString).lastPathComponent
            try hookInstaller.uninstall(repoPath: cwd)
            try store.remove(named: name)
            return "Uninstalled hook and removed \(name)."
        case "doctor":
            return doctor()
        case "fix":
            return try runFix(args: Array(args.dropFirst()), cwd: cwd)
        default:
            return usage()
        }
    }

    private func runFix(args: [String], cwd: String) throws -> String {
        guard let project = store.project(forPath: cwd) else {
            return "Project not registered. Run `auto-ci init` first."
        }
        let opts = parseOptions(args)
        let git = GitClient(runner: runner)
        let sha = try opts["sha"] ?? git.headSHA(cwd: cwd)
        let branch = try opts["branch"] ?? git.currentBranch(cwd: cwd)

        let summary = (fixRunner ?? defaultFixRunner)(project, sha, branch)
        return summary
    }

    private func parseOptions(_ args: [String]) -> [String: String] {
        var opts: [String: String] = [:]
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg.hasPrefix("--"), i + 1 < args.count {
                opts[String(arg.dropFirst(2))] = args[i + 1]
                i += 2
            } else {
                i += 1
            }
        }
        return opts
    }

    /// Real pipeline: clone, poll failed runs, and run the fix once. Hits the network and gh/claude.
    private func defaultFixRunner(_ project: ProjectConfig, _ sha: String, _ branch: String) -> String {
        let workflowYAML = (try? String(contentsOfFile: project.path + "/.github/workflows/ci.yml", encoding: .utf8)) ?? ""
        let github = GitHubClient(runner: runner)
        let git = GitClient(runner: runner)
        let watcher = RunWatcher(github: github)
        let root = ConfigStore.defaultRoot
        do {
            let clone = ClonePool(root: root, git: git).cloneDir(project: project.name)
            try git.cloneOrFetch(remoteURL: project.remote, into: clone)
            let failures = try watcher.waitForTerminal(sha: sha, cwd: clone)
            guard let firstFailure = failures.first else {
                return "No failed runs for \(sha) — nothing to fix."
            }
            let engine = LiveFixEngine(config: project, root: root, runner: runner, workflowYAML: workflowYAML)
            let daemon = Daemon(notifier: ConsoleNotifier(), engine: engine)
            print("Fixing \(project.name) on \(branch) @ \(sha)…")
            let outcome = daemon.handleFailedRun(project: project.name, branch: branch, sha: sha, failedRun: firstFailure)
            switch outcome {
            case .fixed: return "Done: fix applied."
            case .stuck: return "Stuck: the same failure recurred — manual attention needed."
            case .gaveUp: return "Gave up after max attempts."
            case .errored: return "Errored while attempting the fix."
            }
        } catch {
            return "Error: \(error)"
        }
    }

    private func doctor() -> String {
        let statuses = DependencyChecker(runner: runner).check()
        var lines: [String] = []
        for s in statuses {
            if s.ok {
                let authNote = s.authenticated == true ? " (authenticated)" : ""
                lines.append("✓ \(s.name)\(authNote)")
            } else if !s.installed {
                lines.append("✗ \(s.name) — not installed. \(s.hint)")
            } else {
                lines.append("⚠ \(s.name) — installed but not authenticated. \(s.hint)")
            }
        }
        let allOK = statuses.allSatisfy { $0.ok }
        lines.append(allOK ? "All dependencies OK." : "Some dependencies need attention (see above).")
        return lines.joined(separator: "\n")
    }

    private func usage() -> String {
        "Usage: auto-ci <init|list|uninstall|doctor|fix [--sha <sha>] [--branch <branch>]>"
    }
}
