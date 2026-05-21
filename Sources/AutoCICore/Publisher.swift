// Sources/AutoCICore/Publisher.swift
import Foundation

public enum PublishOutcome: Sendable, Equatable {
    case pushedToBranch(String)
    case openedPR(url: String, head: String)
}

public struct Publisher: Sendable {
    private let git: GitClient
    private let github: GitHubClient
    public init(git: GitClient, github: GitHubClient) { self.git = git; self.github = github }

    public func publish(branch: String, protectedBranches: [String], clonePath: String,
                        summary: String, runId: Int) throws -> PublishOutcome {
        let message = "fix(ci): \(summary.split(separator: "\n").first.map(String.init) ?? "auto-fix CI failure")"
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
            return .openedPR(url: url, head: head)
        } else {
            try git.checkoutBranch(branch, cwd: clonePath)
            try git.add(cwd: clonePath)
            try git.commit(message: message, cwd: clonePath)
            try git.push(branch: branch, cwd: clonePath)
            return .pushedToBranch(branch)
        }
    }
}
