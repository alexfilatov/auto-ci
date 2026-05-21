// Tests/AutoCICoreTests/ClonePoolTests.swift
import XCTest
@testable import AutoCICore

final class ClonePoolTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testPreparesCloneAtSha() throws {
        let fake = FakeCommandRunner()
        let pool = ClonePool(root: root, git: GitClient(runner: fake))
        let path = try pool.prepare(project: "demo", remoteURL: "git@github.com:x/y.git", sha: "abc")
        XCTAssertTrue(path.hasSuffix("repos/demo"))
        // clone (no .git yet) then checkout the sha
        XCTAssertTrue(fake.calls.contains { $0.command == "git" && $0.args.first == "clone" })
        XCTAssertTrue(fake.calls.contains { $0.command == "git" && $0.args == ["checkout", "abc"] })
    }
}
