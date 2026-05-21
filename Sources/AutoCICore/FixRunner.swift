// Sources/AutoCICore/FixRunner.swift
import Foundation

public struct FixResult: Sendable {
    public let madeChanges: Bool
    public let summary: String
    public let diff: String
}

public struct FixRunner: Sendable {
    private let runner: CommandRunner
    private let git: GitClient
    public init(runner: CommandRunner, git: GitClient) { self.runner = runner; self.git = git }

    public func buildPrompt(_ ctx: FixContext) -> String {
        let past = ctx.pastFixes.isEmpty ? "None recorded." :
            ctx.pastFixes.map { "- (\($0.succeeded ? "worked" : "did not work")) \($0.summary)" }.joined(separator: "\n")
        return """
        CI job "\(ctx.job)" step "\(ctx.step)" failed. Diagnose and fix it.

        ## Failure logs
        \(ctx.logs)

        ## Workflow YAML
        \(ctx.workflowYAML)

        ## Diff of the commit that failed
        \(ctx.commitDiff)

        ## Changed files
        \(ctx.changedFiles.joined(separator: "\n"))

        ## Notes from past fixes on this project
        \(past)

        Fix the failure by editing files in this repository. Don't touch unrelated code.
        Make the minimal change needed to make CI pass.
        """
    }

    public func run(context: FixContext, clonePath: String) throws -> FixResult {
        let prompt = buildPrompt(context)
        let r = try runner.run("claude",
            ["-p", "--permission-mode", "acceptEdits", "--dangerously-skip-permissions"],
            cwd: clonePath, stdin: prompt, env: nil)
        guard r.exitCode == 0 else { throw AppError.commandFailed("claude", r.exitCode) }
        let diff = try git.diff(cwd: clonePath)
        guard !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError.noChanges }
        return FixResult(madeChanges: true,
                         summary: r.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                         diff: diff)
    }
}
