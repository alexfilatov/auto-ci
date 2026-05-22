// Sources/AutoCICore/DependencyChecker.swift
import Foundation

public struct DependencyStatus: Equatable, Sendable {
    public let name: String          // "git", "gh", "claude"
    public let installed: Bool
    public let authenticated: Bool?  // nil = N/A (e.g. git), true/false for gh
    public let hint: String          // actionable fix, e.g. "Install: brew install gh"
    public var ok: Bool { installed && (authenticated ?? true) }

    public init(name: String, installed: Bool, authenticated: Bool?, hint: String) {
        self.name = name; self.installed = installed
        self.authenticated = authenticated; self.hint = hint
    }
}

public struct DependencyChecker: Sendable {
    private let runner: CommandRunner
    public init(runner: CommandRunner) { self.runner = runner }

    /// Checks git, gh, claude. Returns one status per tool, in that order.
    public func check() -> [DependencyStatus] {
        [checkGit(), checkGh(), checkClaude()]
    }

    /// Convenience: all required tools ok.
    public func allOK() -> Bool { check().allSatisfy { $0.ok } }

    /// Runs a command and returns its exit code, treating any thrown error as failure (e.g. missing binary).
    private func exitCode(_ command: String, _ args: [String]) -> Int32 {
        do {
            return try runner.run(command, args, cwd: nil, stdin: nil, env: nil).exitCode
        } catch {
            return 127
        }
    }

    private func checkGit() -> DependencyStatus {
        let installed = exitCode("git", ["--version"]) == 0
        return DependencyStatus(
            name: "git", installed: installed, authenticated: nil,
            hint: installed ? "" : "Install Xcode Command Line Tools: xcode-select --install")
    }

    private func checkGh() -> DependencyStatus {
        let installed = exitCode("gh", ["--version"]) == 0
        if !installed {
            return DependencyStatus(name: "gh", installed: false, authenticated: nil,
                                    hint: "Install: brew install gh")
        }
        let authed = exitCode("gh", ["auth", "status"]) == 0
        return DependencyStatus(
            name: "gh", installed: true, authenticated: authed,
            hint: authed ? "" : "Authenticate: gh auth login")
    }

    private func checkClaude() -> DependencyStatus {
        let installed = exitCode("claude", ["--version"]) == 0
        return DependencyStatus(
            name: "claude", installed: installed, authenticated: nil,
            hint: installed ? "" : "Install Claude Code: see https://docs.claude.com/claude-code")
    }
}
