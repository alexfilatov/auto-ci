// Sources/AutoCICore/CLICommand.swift
import Foundation

public struct CLICommand: Sendable {
    private let store: ConfigStore
    private let runner: CommandRunner
    private let hookInstaller: HookInstaller
    private let socketPath: String
    public init(store: ConfigStore, runner: CommandRunner, hookInstaller: HookInstaller, socketPath: String) {
        self.store = store; self.runner = runner; self.hookInstaller = hookInstaller; self.socketPath = socketPath
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
            return "Registered \(name) (\(remote)) and installed pre-push hook."
        case "list":
            let names = store.projects().map { "\($0.name)\t\($0.remote)" }
            return names.isEmpty ? "No projects registered." : names.joined(separator: "\n")
        case "uninstall":
            let name = (cwd as NSString).lastPathComponent
            try hookInstaller.uninstall(repoPath: cwd)
            try store.remove(named: name)
            return "Uninstalled hook and removed \(name)."
        default:
            return usage()
        }
    }

    private func usage() -> String {
        "Usage: auto-ci <init|list|uninstall>"
    }
}
