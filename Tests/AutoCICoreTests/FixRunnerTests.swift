// Tests/AutoCICoreTests/FixRunnerTests.swift
import XCTest
@testable import AutoCICore

final class FixRunnerTests: XCTestCase {
    func testBuildsPromptWithContextAndPastFixes() {
        let runner = FixRunner(runner: FakeCommandRunner(), git: GitClient(runner: FakeCommandRunner()))
        let ctx = FixContext(runId: 1, job: "test", step: "rspec", logs: "boom",
                             workflowYAML: "name: CI", commitDiff: "diff", changedFiles: ["a.rb"],
                             pastFixes: [FixRecord(signature: .init(job: "test", step: "rspec", hash: "h"),
                                                   summary: "added gem", succeeded: true, timestamp: Date())])
        let prompt = runner.buildPrompt(ctx)
        XCTAssertTrue(prompt.contains("rspec"))
        XCTAssertTrue(prompt.contains("boom"))
        XCTAssertTrue(prompt.contains("added gem"))
        XCTAssertTrue(prompt.contains("Don't touch unrelated code"))
    }

    func testRunInvokesClaudeAndReturnsDiff() throws {
        let fake = FakeCommandRunner()
        fake.stub(command: "claude", args: ["-p"], stdout: "fixed it")
        fake.stub(command: "git", args: ["diff"], stdout: "diff --git a b\n+fix")
        let runner = FixRunner(runner: fake, git: GitClient(runner: fake))
        let ctx = FixContext(runId: 1, job: "t", step: "s", logs: "x", workflowYAML: "y",
                             commitDiff: "", changedFiles: [], pastFixes: [])
        let result = try runner.run(context: ctx, clonePath: "/clone")
        XCTAssertTrue(result.madeChanges)
        XCTAssertEqual(result.summary, "fixed it")
    }

    func testRunThrowsNoChangesWhenDiffEmpty() {
        let fake = FakeCommandRunner()
        fake.stub(command: "claude", args: ["-p"], stdout: "nothing to do")
        fake.stub(command: "git", args: ["diff"], stdout: "")
        let runner = FixRunner(runner: fake, git: GitClient(runner: fake))
        let ctx = FixContext(runId: 1, job: "t", step: "s", logs: "x", workflowYAML: "y",
                             commitDiff: "", changedFiles: [], pastFixes: [])
        XCTAssertThrowsError(try runner.run(context: ctx, clonePath: "/clone")) {
            XCTAssertEqual($0 as? AppError, .noChanges)
        }
    }
}
