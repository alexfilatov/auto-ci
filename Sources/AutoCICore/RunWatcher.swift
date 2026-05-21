// Sources/AutoCICore/RunWatcher.swift
import Foundation

public struct RunWatcher: Sendable {
    private let github: GitHubClient
    private let pollInterval: TimeInterval
    private let timeout: TimeInterval
    private let sleep: @Sendable (TimeInterval) -> Void
    private let now: @Sendable () -> Date

    public init(github: GitHubClient, pollInterval: TimeInterval = 15, timeout: TimeInterval = 1800,
                sleep: @escaping @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.github = github; self.pollInterval = pollInterval; self.timeout = timeout
        self.sleep = sleep; self.now = now
    }

    /// Polls until all runs for the SHA are terminal (or until one appears and resolves),
    /// returning the failed runs. Throws `.timedOut` if no run ever appears.
    public func waitForTerminal(sha: String, cwd: String) throws -> [WorkflowRun] {
        let deadline = now().addingTimeInterval(timeout)
        var sawRun = false
        while true {
            let runs = try github.runs(forSha: sha, cwd: cwd)
            if !runs.isEmpty {
                sawRun = true
                if runs.allSatisfy({ $0.status.isTerminal }) {
                    return runs.filter { $0.status == .failed }
                }
            }
            if now() >= deadline {
                if sawRun { return try github.runs(forSha: sha, cwd: cwd).filter { $0.status == .failed } }
                throw AppError.timedOut
            }
            sleep(pollInterval)
        }
    }
}
