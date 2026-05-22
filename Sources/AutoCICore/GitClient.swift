// Sources/AutoCICore/GitClient.swift
import Foundation

public struct GitClient: Sendable {
    private let runner: CommandRunner
    public init(runner: CommandRunner) { self.runner = runner }

    @discardableResult
    private func git(_ args: [String], cwd: String?, stdin: String? = nil) throws -> String {
        let r = try runner.run("git", args, cwd: cwd, stdin: stdin, env: nil)
        guard r.exitCode == 0 else { throw AppError.commandFailed("git " + args.joined(separator: " "), r.exitCode) }
        return r.stdout
    }

    public func cloneOrFetch(remoteURL: String, into dir: String) throws {
        if FileManager.default.fileExists(atPath: dir + "/.git") {
            try git(["fetch", "--all", "--prune"], cwd: dir)
        } else {
            try git(["clone", remoteURL, dir], cwd: nil)
        }
    }

    public func checkout(sha: String, cwd: String) throws { try git(["checkout", sha], cwd: cwd) }
    public func checkoutBranch(_ name: String, cwd: String) throws { try git(["checkout", "-B", name], cwd: cwd) }
    public func currentBranch(cwd: String) throws -> String {
        try git(["rev-parse", "--abbrev-ref", "HEAD"], cwd: cwd).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public func add(all: Bool = true, cwd: String) throws { try git(["add", "-A"], cwd: cwd) }
    public func commit(message: String, cwd: String) throws { try git(["commit", "-m", message], cwd: cwd) }
    public func push(branch: String, cwd: String, force: Bool = false) throws {
        var args = ["push", "origin", branch]; if force { args.insert("--force-with-lease", at: 1) }
        try git(args, cwd: cwd)
    }
    public func diff(cwd: String) throws -> String { try git(["diff", "HEAD"], cwd: cwd) }
    public func discardChanges(cwd: String) throws {
        try git(["reset", "--hard", "HEAD"], cwd: cwd)
        try git(["clean", "-fd"], cwd: cwd)
    }
    public func hasUncommittedChanges(cwd: String) throws -> Bool {
        !(try git(["status", "--porcelain"], cwd: cwd)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    public func shaExists(_ sha: String, cwd: String) -> Bool {
        (try? git(["cat-file", "-e", sha], cwd: cwd)) != nil
    }
    public func changedFiles(sha: String, cwd: String) throws -> [String] {
        try git(["diff-tree", "--no-commit-id", "--name-only", "-r", sha], cwd: cwd)
            .split(separator: "\n").map(String.init)
    }
    public func commitDiff(sha: String, cwd: String) throws -> String {
        try git(["show", sha], cwd: cwd)
    }
    public func headSHA(cwd: String) throws -> String {
        try git(["rev-parse", "HEAD"], cwd: cwd).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
