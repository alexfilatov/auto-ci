// Tests/AutoCICoreTests/DependencyCheckerTests.swift
import XCTest
@testable import AutoCICore

final class DependencyCheckerTests: XCTestCase {
    private func status(_ statuses: [DependencyStatus], _ name: String) -> DependencyStatus {
        statuses.first { $0.name == name }!
    }

    func testAllPresentAndAuthed() {
        let fake = FakeCommandRunner()
        // Defaults: every --version exits 0, gh auth status exits 0 → all ok.
        let checker = DependencyChecker(runner: fake)
        let statuses = checker.check()
        XCTAssertEqual(statuses.map(\.name), ["git", "gh", "claude"])
        XCTAssertTrue(checker.allOK())
        XCTAssertTrue(statuses.allSatisfy { $0.ok })
        XCTAssertEqual(status(statuses, "gh").authenticated, true)
    }

    func testGhMissing() {
        let fake = FakeCommandRunner()
        fake.stub(command: "gh", args: ["--version"], exit: 127)
        let checker = DependencyChecker(runner: fake)
        let statuses = checker.check()
        let gh = status(statuses, "gh")
        XCTAssertFalse(gh.installed)
        XCTAssertFalse(gh.ok)
        XCTAssertFalse(checker.allOK())
        XCTAssertTrue(gh.hint.contains("brew install gh"))
    }

    func testGhPresentButNotAuthenticated() {
        let fake = FakeCommandRunner()
        fake.stub(command: "gh", args: ["--version"], exit: 0)
        fake.stub(command: "gh", args: ["auth", "status"], exit: 1)
        let checker = DependencyChecker(runner: fake)
        let statuses = checker.check()
        let gh = status(statuses, "gh")
        XCTAssertTrue(gh.installed)
        XCTAssertEqual(gh.authenticated, false)
        XCTAssertFalse(gh.ok)
        XCTAssertFalse(checker.allOK())
        XCTAssertTrue(gh.hint.contains("gh auth login"))
    }

    func testClaudeMissing() {
        let fake = FakeCommandRunner()
        fake.stub(command: "claude", args: ["--version"], exit: 127)
        let checker = DependencyChecker(runner: fake)
        let statuses = checker.check()
        let claude = status(statuses, "claude")
        XCTAssertFalse(claude.installed)
        XCTAssertFalse(claude.ok)
        XCTAssertFalse(checker.allOK())
    }
}
