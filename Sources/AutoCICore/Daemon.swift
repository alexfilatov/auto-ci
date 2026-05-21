// Sources/AutoCICore/Daemon.swift
import Foundation

public enum DaemonEvent: Sendable, Equatable {
    case fixed(project: String, branch: String, detail: String)
    case stuck(project: String, branch: String)
    case gaveUp(project: String, branch: String)
    case error(project: String, message: String)
}

public protocol Notifier: Sendable {
    func notify(_ event: DaemonEvent)
}

public enum FixOutcome: Sendable, Equatable {
    case fixed, stuck, gaveUp, errored
}

/// The work the Daemon orchestrates. Real impl wraps ClonePool/ContextBuilder/FixRunner/Publisher/RunWatcher.
public protocol FixEngine: Sendable {
    func signature(of run: WorkflowRun, project: String) throws -> FailureSignature
    func attemptFix(project: String, branch: String, sha: String, run: WorkflowRun) throws -> PublishOutcome
    func rerunFailures(project: String, sha: String) throws -> [WorkflowRun]
    func recordOutcome(project: String, signature: FailureSignature, summary: String, succeeded: Bool)
}

public final class Daemon: @unchecked Sendable {
    private let maxAttempts: Int
    private let notifier: Notifier
    private let engine: FixEngine
    public init(maxAttempts: Int = 3, notifier: Notifier, engine: FixEngine) {
        self.maxAttempts = maxAttempts; self.notifier = notifier; self.engine = engine
    }

    @discardableResult
    public func handleFailedRun(project: String, branch: String, sha: String, failedRun: WorkflowRun) -> FixOutcome {
        var previousSignature: FailureSignature?
        var currentRun = failedRun
        for attempt in 1...maxAttempts {
            do {
                let sig = try engine.signature(of: currentRun, project: project)

                let outcome = try engine.attemptFix(project: project, branch: branch, sha: sha, run: currentRun)
                let detail: String
                switch outcome {
                case .pushedToBranch(let b): detail = "pushed to \(b)"
                case .openedPR(let url, _): detail = "opened PR \(url)"
                }

                let failures = try engine.rerunFailures(project: project, sha: sha)
                if failures.isEmpty {
                    engine.recordOutcome(project: project, signature: sig, summary: detail, succeeded: true)
                    notifier.notify(.fixed(project: project, branch: branch, detail: detail))
                    return .fixed
                }
                engine.recordOutcome(project: project, signature: sig, summary: detail, succeeded: false)
                currentRun = failures[0]

                // If the same failure signature recurs after a fix, we're stuck — stop early.
                if let prev = previousSignature, prev == sig {
                    notifier.notify(.stuck(project: project, branch: branch))
                    return .stuck
                }
                previousSignature = sig
                _ = attempt
            } catch {
                notifier.notify(.error(project: project, message: "\(error)"))
                return .errored
            }
        }
        notifier.notify(.gaveUp(project: project, branch: branch))
        return .gaveUp
    }
}
