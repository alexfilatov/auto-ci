// Sources/AutoCICore/Publisher.swift
import Foundation

public enum PublishOutcome: Sendable, Equatable {
    case pushedToBranch(String)
    case openedPR(url: String, head: String)
}

public struct PublishResult: Sendable {
    public let outcome: PublishOutcome
    public let fixSHA: String
    public init(outcome: PublishOutcome, fixSHA: String) {
        self.outcome = outcome; self.fixSHA = fixSHA
    }
}

public struct Publisher: Sendable {
    private let git: GitClient
    private let github: GitHubClient
    public init(git: GitClient, github: GitHubClient) { self.git = git; self.github = github }

    public func publish(branch: String, protectedBranches: [String], clonePath: String,
                        summary: String, runId: Int) throws -> PublishResult {
        let message = "fix(ci): \(summary.split(separator: "\n").first.map(String.init) ?? "auto-fix CI failure")"
        let outcome: PublishOutcome
        if protectedBranches.contains(branch) {
            let head = "auto-ci/fix-\(branch)-\(runId)"
            try git.checkoutBranch(head, cwd: clonePath)
            try git.add(cwd: clonePath)
            try git.commit(message: message, cwd: clonePath)
            try git.push(branch: head, cwd: clonePath)
            let url = try github.createDraftPR(head: head, base: branch,
                                               title: message,
                                               body: "Automated CI fix for run #\(runId).\n\n\(summary)",
                                               cwd: clonePath)
            outcome = .openedPR(url: url, head: head)
        } else {
            try git.checkoutBranch(branch, cwd: clonePath)
            try git.add(cwd: clonePath)
            try git.commit(message: message, cwd: clonePath)
            try git.push(branch: branch, cwd: clonePath)
            outcome = .pushedToBranch(branch)
        }
        let sha = try git.headSHA(cwd: clonePath)
        return PublishResult(outcome: outcome, fixSHA: sha)
    }
}
