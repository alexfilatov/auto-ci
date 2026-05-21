// Tests/AutoCICoreTests/HookInstallerTests.swift
import XCTest
@testable import AutoCICore

final class HookInstallerTests: XCTestCase {
    var repo: URL!
    override func setUpWithError() throws {
        repo = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git/hooks"), withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: repo) }

    var hookPath: String { repo.appendingPathComponent(".git/hooks/pre-push").path }

    func testInstallsHookWhenNoneExists() throws {
        let installer = HookInstaller()
        try installer.install(repoPath: repo.path, socketPath: "/tmp/sock", project: "demo")
        XCTAssertTrue(FileManager.default.fileExists(atPath: hookPath))
        let content = try String(contentsOfFile: hookPath, encoding: .utf8)
        XCTAssertTrue(content.contains("AUTO-CI"))
        XCTAssertTrue(content.contains("demo"))
    }

    func testChainsExistingHookWithoutOverwriting() throws {
        let original = "#!/bin/sh\necho existing\n"
        try original.write(toFile: hookPath, atomically: true, encoding: .utf8)
        let installer = HookInstaller()
        try installer.install(repoPath: repo.path, socketPath: "/tmp/sock", project: "demo")
        // original preserved as backup, and called from our hook
        XCTAssertTrue(FileManager.default.fileExists(atPath: hookPath + ".auto-ci-orig"))
        let content = try String(contentsOfFile: hookPath, encoding: .utf8)
        XCTAssertTrue(content.contains("pre-push.auto-ci-orig"))
    }

    func testUninstallRestoresOriginal() throws {
        let original = "#!/bin/sh\necho existing\n"
        try original.write(toFile: hookPath, atomically: true, encoding: .utf8)
        let installer = HookInstaller()
        try installer.install(repoPath: repo.path, socketPath: "/tmp/sock", project: "demo")
        try installer.uninstall(repoPath: repo.path)
        let restored = try String(contentsOfFile: hookPath, encoding: .utf8)
        XCTAssertEqual(restored, original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: hookPath + ".auto-ci-orig"))
    }
}
