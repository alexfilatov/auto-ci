// Tests/AutoCICoreTests/PublisherTests.swift
import XCTest
@testable import AutoCICore

final class PublisherTests: XCTestCase {
    func testPublishesToSameBranchWhenNotProtected() throws {
        let fake = FakeCommandRunner()
        let pub = Publisher(git: GitClient(runner: fake), github: GitHubClient(runner: fake))
        let outcome = try pub.publish(branch: "feature-x", protectedBranches: ["main", "master"],
                                      clonePath: "/clone", summary: "fix", runId: 5)
        if case .pushedToBranch(let b) = outcome { XCTAssertEqual(b, "feature-x") }
        else { XCTFail("expected pushedToBranch") }
        XCTAssertTrue(fake.calls.contains { $0.args == ["push", "origin", "feature-x"] })
    }

    func testFallsBackToFixBranchAndPRWhenProtected() throws {
        let fake = FakeCommandRunner()
        fake.stub(command: "gh", args: ["pr", "create"], stdout: "https://github.com/x/y/pull/9")
        let pub = Publisher(git: GitClient(runner: fake), github: GitHubClient(runner: fake))
        let outcome = try pub.publish(branch: "main", protectedBranches: ["main", "master"],
                                      clonePath: "/clone", summary: "fix", runId: 5)
        guard case .openedPR(let url, let head) = outcome else { return XCTFail("expected openedPR") }
        XCTAssertEqual(url, "https://github.com/x/y/pull/9")
        XCTAssertTrue(head.hasPrefix("auto-ci/fix-main-"))
        XCTAssertTrue(fake.calls.contains { $0.args.first == "checkout" && $0.args.contains("-B") })
    }
}
