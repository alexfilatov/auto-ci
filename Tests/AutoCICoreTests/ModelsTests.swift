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

    func testProjectConfigDecodesLegacyJSONWithoutNewFields() throws {
        let json = """
        {"name":"demo","path":"/tmp/demo","remote":"origin","protectedBranches":["main"]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ProjectConfig.self, from: json)
        XCTAssertTrue(decoded.protectTests)
        XCTAssertFalse(decoded.testPathPatterns.isEmpty)
    }

    func testProjectConfigDefaultsGraceSeconds() {
        let p = ProjectConfig(name: "demo", path: "/tmp/demo", remote: "origin")
        XCTAssertEqual(p.graceSeconds, 180)
    }

    func testProjectConfigDecodesLegacyJSONWithoutGraceSeconds() throws {
        let json = """
        {"name":"demo","path":"/tmp/demo","remote":"origin","protectedBranches":["main"]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ProjectConfig.self, from: json)
        XCTAssertEqual(decoded.graceSeconds, 180)
    }

    func testProjectConfigRoundTripPreservesCustomGraceSeconds() throws {
        let p = ProjectConfig(name: "demo", path: "/tmp/demo", remote: "origin", graceSeconds: 42)
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(ProjectConfig.self, from: data)
        XCTAssertEqual(decoded.graceSeconds, 42)
        XCTAssertEqual(decoded, p)
    }

    func testRunStatusTerminalDetection() {
        XCTAssertTrue(RunStatus.failed.isTerminal)
        XCTAssertTrue(RunStatus.succeeded.isTerminal)
        XCTAssertFalse(RunStatus.inProgress.isTerminal)
    }
}
