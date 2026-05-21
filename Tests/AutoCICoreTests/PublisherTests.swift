// Tests/AutoCICoreTests/PublisherTests.swift
import XCTest
@testable import AutoCICore

final class PublisherTests: XCTestCase {
    func testPublishesToSameBranchWhenNotProtected() throws {
        let fake = FakeCommandRunner()
        fake.stub(command: "git", args: ["rev-parse", "HEAD"], stdout: "abc1234\n")
        let pub = Publisher(git: GitClient(runner: fake), github: GitHubClient(runner: fake))
        let result = try pub.publish(branch: "feature-x", protectedBranches: ["main", "master"],
                                     clonePath: "/clone", summary: "fix", runId: 5)
        if case .pushedToBranch(let b) = result.outcome { XCTAssertEqual(b, "feature-x") }
        else { XCTFail("expected pushedToBranch") }
        XCTAssertTrue(fake.calls.contains { $0.args == ["push", "origin", "feature-x"] })
        XCTAssertEqual(result.fixSHA, "abc1234")
    }

    func testFallsBackToFixBranchAndPRWhenProtected() throws {
        let fake = FakeCommandRunner()
        fake.stub(command: "gh", args: ["pr", "create"], stdout: "https://github.com/x/y/pull/9")
        fake.stub(command: "git", args: ["rev-parse", "HEAD"], stdout: "def5678\n")
        let pub = Publisher(git: GitClient(runner: fake), github: GitHubClient(runner: fake))
        let result = try pub.publish(branch: "main", protectedBranches: ["main", "master"],
                                     clonePath: "/clone", summary: "fix", runId: 5)
        guard case .openedPR(let url, let head) = result.outcome else { return XCTFail("expected openedPR") }
        XCTAssertEqual(url, "https://github.com/x/y/pull/9")
        XCTAssertTrue(head.hasPrefix("auto-ci/fix-main-"))
        XCTAssertTrue(fake.calls.contains { $0.args.first == "checkout" && $0.args.contains("-B") })
        XCTAssertEqual(result.fixSHA, "def5678")
    }
}
