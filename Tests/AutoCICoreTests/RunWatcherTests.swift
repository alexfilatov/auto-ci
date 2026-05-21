// Tests/AutoCICoreTests/RunWatcherTests.swift
import XCTest
@testable import AutoCICore

final class RunWatcherTests: XCTestCase {
    func testPollsUntilTerminalThenReturnsFailedRuns() throws {
        let fake = FakeCommandRunner()
        // first poll: in_progress; second poll: failure
        var inProgress = """
        [{"databaseId":7,"name":"CI","status":"in_progress","conclusion":"","headSha":"abc"}]
        """
        let failed = """
        [{"databaseId":7,"name":"CI","status":"completed","conclusion":"failure","headSha":"abc"}]
        """
        var pollCount = 0
        let github = GitHubClient(runner: fake)
        let watcher = RunWatcher(github: github, pollInterval: 0, timeout: 5, sleep: { _ in })
        // Use a stubbing fake that flips after first call:
        let flip = FlippingRunner(first: inProgress, then: failed)
        let watcher2 = RunWatcher(github: GitHubClient(runner: flip), pollInterval: 0, timeout: 5, sleep: { _ in })
        let result = try watcher2.waitForTerminal(sha: "abc", cwd: "/repo")
        XCTAssertEqual(result.map { $0.id }, [7])
        XCTAssertEqual(result.first?.status, .failed)
        _ = (inProgress, pollCount, watcher) // silence unused
    }

    func testTimesOutWhenNoRunAppears() {
        let fake = FakeCommandRunner()
        fake.stub(command: "gh", args: ["run", "list"], stdout: "[]")
        let watcher = RunWatcher(github: GitHubClient(runner: fake), pollInterval: 0, timeout: 0, sleep: { _ in })
        XCTAssertThrowsError(try watcher.waitForTerminal(sha: "abc", cwd: "/repo")) {
            XCTAssertEqual($0 as? AppError, .timedOut)
        }
    }
}

/// Returns `first` on call 1, `then` thereafter.
final class FlippingRunner: CommandRunner, @unchecked Sendable {
    let first: String; let then: String; var count = 0
    init(first: String, then: String) { self.first = first; self.then = then }
    func run(_ command: String, _ args: [String], cwd: String?, stdin: String?, env: [String: String]?) throws -> CommandResult {
        count += 1
        return CommandResult(exitCode: 0, stdout: count == 1 ? first : then, stderr: "")
    }
}
