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

    func testListShowsProjects() throws {
        let store = ConfigStore(root: root.appendingPathComponent("cfg"))
        try store.upsert(ProjectConfig(name: "demo", path: "/x", remote: "origin"))
        let cli = CLICommand(store: store, runner: FakeCommandRunner(), hookInstaller: HookInstaller(), socketPath: "/tmp/sock")
        let out = try cli.run(["list"], cwd: "/x")
        XCTAssertTrue(out.contains("demo"))
    }
}
