// Tests/AutoCICoreTests/LiveFixEngineTests.swift
import XCTest
@testable import AutoCICore

final class LiveFixEngineTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testAttemptFixPreparesCloneRunsClaudeAndPublishes() throws {
        let fake = FakeCommandRunner()
        fake.stub(command: "gh", args: ["run", "view"], stdout: "error: boom")
        fake.stub(command: "claude", args: ["-p"], stdout: "added missing import")
        fake.stub(command: "git", args: ["diff"], stdout: "diff --git a b\n+import x")
        let project = ProjectConfig(name: "demo", path: "/src/demo", remote: "git@github.com:x/y.git")
        let engine = LiveFixEngine(config: project, root: root, runner: fake, workflowYAML: "name: CI")
        let outcome = try engine.attemptFix(project: "demo", branch: "feature-x", sha: "abc",
                                            run: WorkflowRun(id: 9, name: "CI", status: .failed, headSha: "abc"))
        if case .pushedToBranch(let b) = outcome { XCTAssertEqual(b, "feature-x") }
        else { XCTFail("expected push to feature-x") }
        XCTAssertTrue(fake.calls.contains { $0.command == "claude" })
    }
}
