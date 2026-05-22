// Tests/AutoCICoreTests/CLICommandTests.swift
import XCTest
@testable import AutoCICore

final class CLICommandTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git/hooks"), withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testInitRegistersProjectAndInstallsHook() throws {
        let fake = FakeCommandRunner()
        fake.stub(command: "git", args: ["remote", "get-url"], stdout: "git@github.com:x/y.git\n")
        let store = ConfigStore(root: root.appendingPathComponent("cfg"))
        let cli = CLICommand(store: store, runner: fake, hookInstaller: HookInstaller(),
                             socketPath: "/tmp/sock")
        let out = try cli.run(["init"], cwd: root.path)
        XCTAssertTrue(out.contains("Registered"))
        XCTAssertEqual(store.projects().count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(".git/hooks/pre-push").path))
    }

    func testFixResolvesProjectShaAndBranchAndInvokesPipeline() throws {
        let store = ConfigStore(root: root.appendingPathComponent("cfg"))
        try store.upsert(ProjectConfig(name: "demo", path: root.path, remote: "git@github.com:x/y.git"))
        let fake = FakeCommandRunner()
        fake.stub(command: "git", args: ["rev-parse", "HEAD"], stdout: "abc123\n")
        fake.stub(command: "git", args: ["rev-parse", "--abbrev-ref", "HEAD"], stdout: "feature\n")

        final class Box: @unchecked Sendable { var sha = ""; var branch = "" }
        let box = Box()
        let stub: @Sendable (ProjectConfig, String, String) -> String = { _, sha, branch in
            box.sha = sha; box.branch = branch
            return "fixed: added missing import"
        }
        let cli = CLICommand(store: store, runner: fake, hookInstaller: HookInstaller(),
                             socketPath: "/tmp/sock", fixRunner: stub)
        let out = try cli.run(["fix"], cwd: root.path)
        XCTAssertTrue(out.contains("fixed: added missing import"))
        XCTAssertEqual(box.sha, "abc123")
        XCTAssertEqual(box.branch, "feature")
    }

    func testFixOnUnregisteredProjectReturnsHelpfulMessage() throws {
        let store = ConfigStore(root: root.appendingPathComponent("cfg"))
        let cli = CLICommand(store: store, runner: FakeCommandRunner(), hookInstaller: HookInstaller(),
                             socketPath: "/tmp/sock", fixRunner: { _, _, _ in "should not run" })
        let out = try cli.run(["fix"], cwd: root.path)
        XCTAssertTrue(out.contains("not registered"))
        XCTAssertTrue(out.contains("auto-ci init"))
    }

    func testListShowsProjects() throws {
        let store = ConfigStore(root: root.appendingPathComponent("cfg"))
        try store.upsert(ProjectConfig(name: "demo", path: "/x", remote: "origin"))
        let cli = CLICommand(store: store, runner: FakeCommandRunner(), hookInstaller: HookInstaller(), socketPath: "/tmp/sock")
        let out = try cli.run(["list"], cwd: "/x")
        XCTAssertTrue(out.contains("demo"))
    }
}
