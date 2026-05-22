// Tests/AutoCICoreTests/HookInstallerTests.swift
import XCTest
@testable import AutoCICore

final class HookInstallerTests: XCTestCase {
    var repo: URL!
    var fake: FakeCommandRunner!
    var installer: HookInstaller!
    override func setUpWithError() throws {
        repo = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git/hooks"), withIntermediateDirectories: true)
        fake = FakeCommandRunner()
        // Default: core.hooksPath unset -> empty output, so the default .git/hooks is used.
        fake.stub(command: "git", args: ["-C"], stdout: "")
        installer = HookInstaller(runner: fake)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: repo) }

    var hookPath: String { repo.appendingPathComponent(".git/hooks/pre-push").path }

    func testInstallsHookWhenNoneExists() throws {
        try installer.install(repoPath: repo.path, socketPath: "/tmp/sock", project: "demo")
        XCTAssertTrue(FileManager.default.fileExists(atPath: hookPath))
        let content = try String(contentsOfFile: hookPath, encoding: .utf8)
        XCTAssertTrue(content.contains("AUTO-CI"))
        XCTAssertTrue(content.contains("demo"))
    }

    func testChainsExistingHookWithoutOverwriting() throws {
        let original = "#!/bin/sh\necho existing\n"
        try original.write(toFile: hookPath, atomically: true, encoding: .utf8)
        try installer.install(repoPath: repo.path, socketPath: "/tmp/sock", project: "demo")
        // original preserved as backup, and called from our hook
        XCTAssertTrue(FileManager.default.fileExists(atPath: hookPath + ".auto-ci-orig"))
        let content = try String(contentsOfFile: hookPath, encoding: .utf8)
        XCTAssertTrue(content.contains("pre-push.auto-ci-orig"))
    }

    func testUninstallRestoresOriginal() throws {
        let original = "#!/bin/sh\necho existing\n"
        try original.write(toFile: hookPath, atomically: true, encoding: .utf8)
        try installer.install(repoPath: repo.path, socketPath: "/tmp/sock", project: "demo")
        try installer.uninstall(repoPath: repo.path)
        let restored = try String(contentsOfFile: hookPath, encoding: .utf8)
        XCTAssertEqual(restored, original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: hookPath + ".auto-ci-orig"))
    }

    func testUninstallPreservesUserEditsToManagedHook() throws {
        try installer.install(repoPath: repo.path, socketPath: "/tmp/sock", project: "demo")
        // User edits the managed hook (e.g. adds their own step), not realizing it's managed.
        var managed = try String(contentsOfFile: hookPath, encoding: .utf8)
        managed += "\necho 'my custom pre-push step'\n"
        try managed.write(toFile: hookPath, atomically: true, encoding: .utf8)

        let notes = try installer.uninstall(repoPath: repo.path)
        // Their edited hook must be preserved in a saved copy, not silently lost.
        let saved = try FileManager.default.contentsOfDirectory(atPath: repo.path + "/.git/hooks")
            .filter { $0.contains(".auto-ci-modified.") }
        XCTAssertEqual(saved.count, 1)
        let savedContent = try String(contentsOfFile: repo.path + "/.git/hooks/" + saved[0], encoding: .utf8)
        XCTAssertTrue(savedContent.contains("my custom pre-push step"))
        XCTAssertFalse(notes.isEmpty)
    }

    func testUninstallDoesNotClobberUserReplacedHook() throws {
        // Existing hook, then auto-ci installs (chaining), then the user REPLACES pre-push entirely.
        let original = "#!/bin/sh\necho existing\n"
        try original.write(toFile: hookPath, atomically: true, encoding: .utf8)
        try installer.install(repoPath: repo.path, socketPath: "/tmp/sock", project: "demo")
        let userHook = "#!/bin/sh\necho totally new user hook\n"
        try userHook.write(toFile: hookPath, atomically: true, encoding: .utf8)

        try installer.uninstall(repoPath: repo.path)
        // The user's new hook must remain — not be overwritten by the old backup.
        let after = try String(contentsOfFile: hookPath, encoding: .utf8)
        XCTAssertEqual(after, userHook)
    }

    func testInstallsIntoCoreHooksPath() throws {
        let f = FakeCommandRunner()
        f.stub(command: "git", args: ["-C"], stdout: ".githooks\n")
        let inst = HookInstaller(runner: f)
        try inst.install(repoPath: repo.path, socketPath: "/tmp/sock", project: "demo")
        let trackedHook = repo.appendingPathComponent(".githooks/pre-push").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: trackedHook))
        XCTAssertFalse(FileManager.default.fileExists(atPath: hookPath))
    }

    func testInstallWarnsWhenHooksPathTracked() throws {
        let f = FakeCommandRunner()
        f.stub(command: "git", args: ["-C"], stdout: ".githooks\n")
        let inst = HookInstaller(runner: f)
        let notes = try inst.install(repoPath: repo.path, socketPath: "/tmp/sock", project: "demo")
        XCTAssertTrue(notes.contains { $0.contains("tracked") || $0.contains("core.hooksPath") })
    }

    func testUninstallUsesCoreHooksPath() throws {
        let f = FakeCommandRunner()
        f.stub(command: "git", args: ["-C"], stdout: ".githooks\n")
        let inst = HookInstaller(runner: f)
        try inst.install(repoPath: repo.path, socketPath: "/tmp/sock", project: "demo")
        let trackedHook = repo.appendingPathComponent(".githooks/pre-push").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: trackedHook))
        try inst.uninstall(repoPath: repo.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: trackedHook))
    }
}
