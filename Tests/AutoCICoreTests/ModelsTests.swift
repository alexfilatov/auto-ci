// Tests/AutoCICoreTests/ModelsTests.swift
import XCTest
@testable import AutoCICore

final class ModelsTests: XCTestCase {
    func testProjectConfigDefaultsProtectedBranches() {
        let p = ProjectConfig(name: "demo", path: "/tmp/demo", remote: "origin")
        XCTAssertEqual(p.protectedBranches, ["main", "master"])
    }

    func testProjectConfigCodableRoundTrip() throws {
        let p = ProjectConfig(name: "demo", path: "/tmp/demo", remote: "origin", protectedBranches: ["main"])
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(ProjectConfig.self, from: data)
        XCTAssertEqual(decoded, p)
    }

    func testRunStatusTerminalDetection() {
        XCTAssertTrue(RunStatus.failed.isTerminal)
        XCTAssertTrue(RunStatus.succeeded.isTerminal)
        XCTAssertFalse(RunStatus.inProgress.isTerminal)
    }
}
