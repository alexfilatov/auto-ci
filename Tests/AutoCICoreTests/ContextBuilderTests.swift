// Tests/AutoCICoreTests/ContextBuilderTests.swift
import XCTest
@testable import AutoCICore

final class ContextBuilderTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testBuildsContextFromRun() throws {
        let fake = FakeCommandRunner()
        fake.stub(command: "gh", args: ["run", "view"], stdout: "job: test\nstep: rspec\nerror: boom")
        fake.stub(command: "git", args: ["show"], stdout: "diff content")
        fake.stub(command: "git", args: ["diff-tree"], stdout: "app/x.rb\napp/y.rb")
        let mem = FixMemory(projectDir: dir)
        let builder = ContextBuilder(github: GitHubClient(runner: fake),
                                     git: GitClient(runner: fake),
                                     memory: mem,
                                     signatures: SignatureBuilder())
        let ctx = try builder.build(runId: 111, job: "test", step: "rspec",
                                    sha: "abc", clonePath: "/clone", workflowYAML: "name: CI")
        XCTAssertEqual(ctx.runId, 111)
        XCTAssertEqual(ctx.changedFiles, ["app/x.rb", "app/y.rb"])
        XCTAssertEqual(ctx.workflowYAML, "name: CI")
        XCTAssertTrue(ctx.logs.contains("boom"))
    }
}
