// Sources/AutoCICore/LiveFixEngine.swift
import Foundation

public final class LiveFixEngine: FixEngine, @unchecked Sendable {
    private let config: ProjectConfig
    private let root: URL
    private let git: GitClient
    private let github: GitHubClient
    private let pool: ClonePool
    private let signatures = SignatureBuilder()
    private let memory: FixMemory
    private let fixRunner: FixRunner
    private let publisher: Publisher
    private let watcher: RunWatcher
    private let workflowYAML: String

    public init(config: ProjectConfig, root: URL, runner: CommandRunner, workflowYAML: String) {
        self.config = config
        self.root = root
        self.git = GitClient(runner: runner)
        self.github = GitHubClient(runner: runner)
        self.pool = ClonePool(root: root, git: git)
        self.memory = FixMemory(projectDir: root.appendingPathComponent("projects").appendingPathComponent(config.name))
        self.fixRunner = FixRunner(runner: runner, git: git)
        self.publisher = Publisher(git: git, github: github)
        self.watcher = RunWatcher(github: github)
        self.workflowYAML = workflowYAML
    }

    public func signature(of run: WorkflowRun, project: String) throws -> FailureSignature {
        let clone = pool.cloneDir(project: config.name)
        let logs = (try? github.failedLog(runId: run.id, cwd: clone)) ?? ""
        return signatures.signature(job: run.name, step: run.name, logs: logs)
    }

    public func attemptFix(project: String, branch: String, sha: String, run: WorkflowRun) throws -> FixAttempt {
        let clone = try pool.prepare(project: config.name, remoteURL: config.remote, sha: sha)
        let builder = ContextBuilder(github: github, git: git, memory: memory, signatures: signatures)
        let ctx = try builder.build(runId: run.id, job: run.name, step: run.name, sha: sha,
                                    clonePath: clone, workflowYAML: workflowYAML)
        let fix = try fixRunner.run(context: ctx, clonePath: clone)
        let publishResult = try publisher.publish(branch: branch, protectedBranches: config.protectedBranches,
                                                  clonePath: clone, summary: fix.summary, runId: run.id)
        return FixAttempt(outcome: publishResult.outcome, fixSHA: publishResult.fixSHA)
    }

    public func rerunFailures(project: String, sha: String) throws -> [WorkflowRun] {
        let clone = pool.cloneDir(project: config.name)
        return try watcher.waitForTerminal(sha: sha, cwd: clone)
    }

    public func recordOutcome(project: String, signature: FailureSignature, summary: String, succeeded: Bool) {
        try? memory.record(FixRecord(signature: signature, summary: summary, succeeded: succeeded, timestamp: Date()))
    }
}
