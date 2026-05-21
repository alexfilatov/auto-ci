// Sources/AutoCICore/ContextBuilder.swift
import Foundation

public struct ContextBuilder: Sendable {
    private let github: GitHubClient
    private let git: GitClient
    private let memory: FixMemory
    private let signatures: SignatureBuilder
    public init(github: GitHubClient, git: GitClient, memory: FixMemory, signatures: SignatureBuilder) {
        self.github = github; self.git = git; self.memory = memory; self.signatures = signatures
    }

    public func build(runId: Int, job: String, step: String, sha: String,
                      clonePath: String, workflowYAML: String) throws -> FixContext {
        let logs = try github.failedLog(runId: runId, cwd: clonePath)
        let diff = (try? git.commitDiff(sha: sha, cwd: clonePath)) ?? ""
        let changed = (try? git.changedFiles(sha: sha, cwd: clonePath)) ?? []
        let sig = signatures.signature(job: job, step: step, logs: logs)
        let past = memory.matching(sig)
        return FixContext(runId: runId, job: job, step: step, logs: logs, workflowYAML: workflowYAML,
                          commitDiff: diff, changedFiles: changed, pastFixes: past)
    }
}
