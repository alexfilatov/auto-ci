// Sources/AutoCICore/GraceGate.swift
import Foundation

public enum GraceDecision: Equatable, Sendable {
    case proceed
    case deferred(String)
}

/// Decides whether auto-ci should step in to fix a failure, or defer because someone else is
/// already handling it. auto-ci is a *secondary* fixer: it waits out a grace period, and bails
/// the moment a hold is active or the branch advances past the failed commit.
public struct GraceGate: Sendable {
    private let git: GitClient
    private let leases: LeaseStore
    private let graceSeconds: Int
    private let pollInterval: TimeInterval
    private let sleep: @Sendable (TimeInterval) -> Void
    private let now: @Sendable () -> Date

    public init(git: GitClient, leases: LeaseStore, graceSeconds: Int, pollInterval: TimeInterval = 15,
                sleep: @escaping @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.git = git; self.leases = leases; self.graceSeconds = graceSeconds
        self.pollInterval = pollInterval; self.sleep = sleep; self.now = now
    }

    /// Decide whether auto-ci should fix this failure, deferring if anyone else is handling it.
    public func evaluate(project: String, branch: String, failedSHA: String, cwd: String) -> GraceDecision {
        let deadline = now().addingTimeInterval(TimeInterval(graceSeconds))
        while true {
            if leases.isHeld(project: project, branch: branch) {
                return .deferred("a hold is active on \(branch)")
            }
            let tip = (try? git.remoteSHA(branch: branch, cwd: cwd)) ?? ""
            if !tip.isEmpty && tip != failedSHA {
                return .deferred("\(branch) advanced — another fix landed")
            }
            if now() >= deadline { break }
            sleep(pollInterval)
        }
        return .proceed
    }
}
