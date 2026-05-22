// Tests/AutoCICoreTests/CommandRunnerTests.swift
import XCTest
@testable import AutoCICore

final class CommandRunnerTests: XCTestCase {
    func testRealRunnerCapturesStdout() throws {
        let runner = ProcessCommandRunner()
        let result = try runner.run("/bin/echo", ["hello"], cwd: nil, stdin: nil, env: nil)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }

    func testRealRunnerAugmentsPATHForGUILaunch() throws {
        let runner = ProcessCommandRunner()
        let result = try runner.run("/bin/sh", ["-c", "echo $PATH"], cwd: nil, stdin: nil, env: nil)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("/opt/homebrew/bin"))
        XCTAssertTrue(result.stdout.contains(".local/bin"))
    }

    func testFakeMatchesByPrefix() throws {
        let fake = FakeCommandRunner()
        fake.stub(command: "git", args: ["status"], stdout: "clean", exit: 0)
        let r = try fake.run("git", ["status"], cwd: nil, stdin: nil, env: nil)
        XCTAssertEqual(r.stdout, "clean")
        XCTAssertEqual(fake.calls.count, 1)
    }
}
