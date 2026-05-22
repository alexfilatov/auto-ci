// Tests/AutoCICoreTests/GitClientTests.swift
import XCTest
@testable import AutoCICore

final class GitClientTests: XCTestCase {
    func testCheckoutInvokesGit() throws {
        let fake = FakeCommandRunner()
        let git = GitClient(runner: fake)
        try git.checkout(sha: "abc123", cwd: "/repo")
        let call = fake.calls.first!
        XCTAssertEqual(call.command, "git")
        XCTAssertEqual(call.args, ["checkout", "abc123"])
        XCTAssertEqual(call.cwd, "/repo")
    }

    func testCurrentBranchParsesOutput() throws {
        let fake = FakeCommandRunner()
        fake.stub(command: "git", args: ["rev-parse", "--abbrev-ref"], stdout: "feature-x\n")
        let git = GitClient(runner: fake)
        XCTAssertEqual(try git.currentBranch(cwd: "/repo"), "feature-x")
    }

    func testPushThrowsOnNonZeroExit() {
        let fake = FakeCommandRunner()
        fake.stub(command: "git", args: ["push"], stderr: "rejected", exit: 1)
        let git = GitClient(runner: fake)
        XCTAssertThrowsError(try git.push(branch: "feature-x", cwd: "/repo"))
    }

    func testRemoteSHAParsesLeadingSHA() throws {
        let fake = FakeCommandRunner()
        fake.stub(command: "git", args: ["ls-remote", "origin", "refs/heads/feature"],
                  stdout: "deadbeef1234\trefs/heads/feature\n")
        let git = GitClient(runner: fake)
        XCTAssertEqual(try git.remoteSHA(branch: "feature", cwd: "/repo"), "deadbeef1234")
    }

    func testRemoteSHAEmptyWhenBranchAbsent() throws {
        let fake = FakeCommandRunner()
        fake.stub(command: "git", args: ["ls-remote", "origin", "refs/heads/gone"], stdout: "")
        let git = GitClient(runner: fake)
        XCTAssertEqual(try git.remoteSHA(branch: "gone", cwd: "/repo"), "")
    }

    func testDiffReturnsStdout() throws {
        let fake = FakeCommandRunner()
        fake.stub(command: "git", args: ["diff"], stdout: "diff --git a b")
        let git = GitClient(runner: fake)
        XCTAssertEqual(try git.diff(cwd: "/repo"), "diff --git a b")
    }
}
