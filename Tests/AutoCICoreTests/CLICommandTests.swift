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

    func testHelpListsCommands() throws {
        let store = ConfigStore(root: root.appendingPathComponent("cfg"))
        let cli = CLICommand(store: store, runner: FakeCommandRunner(),
                             hookInstaller: HookInstaller(), socketPath: "/tmp/sock")
        for invocation in [["help"], ["--help"], ["-h"], []] {
            let out = try cli.run(invocation, cwd: root.path)
            XCTAssertTrue(out.contains("USAGE"))
            XCTAssertTrue(out.contains("init"))
            XCTAssertTrue(out.contains("doctor"))
            XCTAssertTrue(out.contains("fix"))
        }
    }

    func testUninstallPurgeRemovesCloneMemoryAndHistory() throws {
        let fm = FileManager.default
        let store = ConfigStore(root: root.appendingPathComponent("cfg"))
        try store.upsert(ProjectConfig(name: "demo", path: root.path, remote: "git@github.com:x/y.git"))
        // Seed clone, memory, and history for "demo".
        let cloneDir = root.appendingPathComponent("repos/demo")
        let memDir = root.appendingPathComponent("projects/demo")
        try fm.createDirectory(at: cloneDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: memDir, withIntermediateDirectories: true)
        let history = HistoryStore(root: root)
        history.record(HistoryEntry(project: "demo", branch: "main", kind: "fixed", detail: "x",
                                    runURL: nil, timestamp: Date()))

        // cwd basename must be "demo" so uninstall targets it.
        let repo = root.appendingPathComponent("demo")
        try fm.createDirectory(at: repo.appendingPathComponent(".git/hooks"), withIntermediateDirectories: true)
        try store.upsert(ProjectConfig(name: "demo", path: repo.path, remote: "git@github.com:x/y.git"))

        let cli = CLICommand(store: store, runner: FakeCommandRunner(),
                             hookInstaller: HookInstaller(), socketPath: "/tmp/sock", root: root)
        let out = try cli.run(["uninstall", "--purge"], cwd: repo.path)
        XCTAssertTrue(out.contains("purged"))
        XCTAssertFalse(fm.fileExists(atPath: cloneDir.path))
        XCTAssertFalse(fm.fileExists(atPath: memDir.path))
        XCTAssertTrue(HistoryStore(root: root).all().isEmpty)
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

    func testDoctorReportsMissingTool() throws {
        let fake = FakeCommandRunner()
        fake.stub(command: "gh", args: ["--version"], exit: 127)
        let store = ConfigStore(root: root.appendingPathComponent("cfg"))
        let cli = CLICommand(store: store, runner: fake, hookInstaller: HookInstaller(), socketPath: "/tmp/sock")
        let out = try cli.run(["doctor"], cwd: root.path)
        XCTAssertTrue(out.contains("gh"))
        XCTAssertTrue(out.contains("brew install gh"))
        XCTAssertTrue(out.contains("need attention"))
    }

    func testHoldAndReleaseManageLease() throws {
        let store = ConfigStore(root: root.appendingPathComponent("cfg"))
        try store.upsert(ProjectConfig(name: "demo", path: root.path, remote: "git@github.com:x/y.git"))
        let fake = FakeCommandRunner()
        fake.stub(command: "git", args: ["rev-parse", "--abbrev-ref", "HEAD"], stdout: "feature\n")
        let cli = CLICommand(store: store, runner: fake, hookInstaller: HookInstaller(),
                             socketPath: "/tmp/sock", root: root)

        let held = try cli.run(["hold"], cwd: root.path)
        XCTAssertTrue(held.contains("Holding"))
        XCTAssertTrue(LeaseStore(root: root).isHeld(project: "demo", branch: "feature"))

        let released = try cli.run(["release"], cwd: root.path)
        XCTAssertTrue(released.contains("Released"))
        XCTAssertFalse(LeaseStore(root: root).isHeld(project: "demo", branch: "feature"))
    }

    func testHelpListsHoldAndRelease() throws {
        let store = ConfigStore(root: root.appendingPathComponent("cfg"))
        let cli = CLICommand(store: store, runner: FakeCommandRunner(),
                             hookInstaller: HookInstaller(), socketPath: "/tmp/sock")
        let out = try cli.run(["help"], cwd: root.path)
        XCTAssertTrue(out.contains("hold"))
        XCTAssertTrue(out.contains("release"))
    }

    func testListShowsProjects() throws {
        let store = ConfigStore(root: root.appendingPathComponent("cfg"))
        try store.upsert(ProjectConfig(name: "demo", path: "/x", remote: "origin"))
        let cli = CLICommand(store: store, runner: FakeCommandRunner(), hookInstaller: HookInstaller(), socketPath: "/tmp/sock")
        let out = try cli.run(["list"], cwd: "/x")
        XCTAssertTrue(out.contains("demo"))
    }
}
