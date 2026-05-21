// Tests/AutoCICoreTests/GitHubClientTests.swift
import XCTest
@testable import AutoCICore

final class GitHubClientTests: XCTestCase {
    func testRunsForShaParsesJSON() throws {
        let json = """
        [{"databaseId":111,"name":"CI","status":"completed","conclusion":"failure","headSha":"abc"},
         {"databaseId":222,"name":"Lint","status":"in_progress","conclusion":"","headSha":"abc"}]
        """
        let fake = FakeCommandRunner()
        fake.stub(command: "gh", args: ["run", "list"], stdout: json)
        let gh = GitHubClient(runner: fake)
        let runs = try gh.runs(forSha: "abc", cwd: "/repo")
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs[0].status, .failed)
        XCTAssertEqual(runs[1].status, .inProgress)
        XCTAssertEqual(runs[0].id, 111)
    }

    func testFailedJobLogReturnsStdout() throws {
        let fake = FakeCommandRunner()
        fake.stub(command: "gh", args: ["run", "view"], stdout: "boom log")
        let gh = GitHubClient(runner: fake)
        XCTAssertEqual(try gh.failedLog(runId: 111, cwd: "/repo"), "boom log")
    }

    func testCreateDraftPRReturnsURL() throws {
        let fake = FakeCommandRunner()
        fake.stub(command: "gh", args: ["pr", "create"], stdout: "https://github.com/x/y/pull/3\n")
        let gh = GitHubClient(runner: fake)
        let url = try gh.createDraftPR(head: "fix/x", base: "main", title: "fix", body: "b", cwd: "/repo")
        XCTAssertEqual(url, "https://github.com/x/y/pull/3")
    }
}
