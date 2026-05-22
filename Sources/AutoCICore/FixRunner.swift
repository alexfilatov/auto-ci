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
    private let guardian: TestEditGuard
    public init(runner: CommandRunner, git: GitClient, guardian: TestEditGuard = TestEditGuard()) {
        self.runner = runner; self.git = git; self.guardian = guardian
    }

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

        CRITICAL RULES:
        - Fix the application/source code so the existing tests pass. NEVER modify, weaken, delete, or skip tests or assertions to make CI green.
        - If a test failure is caused by a source regression, fix the source — not the test.
        - Only edit a test if the test itself is genuinely, provably incorrect; if so, leave a clear note in your output explaining why. Default to fixing source.
        """
    }

    public func run(context: FixContext, clonePath: String,
                    protectTests: Bool = true,
                    testPatterns: [String] = ProjectConfig.defaultTestPathPatterns) throws -> FixResult {
        var prompt = buildPrompt(context)
        let maxAttempts = 2
        for attempt in 1...maxAttempts {
            let r = try runner.run("claude",
                ["-p", "--permission-mode", "acceptEdits", "--dangerously-skip-permissions"],
                cwd: clonePath, stdin: prompt, env: nil)
            guard r.exitCode == 0 else { throw AppError.commandFailed("claude", r.exitCode) }
            let diff = try git.diff(cwd: clonePath)
            guard !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError.noChanges }

            if protectTests {
                let touched = guardian.testFilesTouched(in: diff, patterns: testPatterns)
                if !touched.isEmpty {
                    if attempt == maxAttempts {
                        throw AppError.testsModified(touched)
                    }
                    try git.discardChanges(cwd: clonePath)
                    prompt = buildPrompt(context) + """


                    Your previous attempt modified test files: \(touched.joined(separator: ", ")). \
                    That is forbidden. Revert any test changes and fix the SOURCE code instead.
                    """
                    continue
                }
            }

            return FixResult(madeChanges: true,
                             summary: r.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                             diff: diff)
        }
        // Unreachable: loop either returns or throws.
        throw AppError.noChanges
    }
}
