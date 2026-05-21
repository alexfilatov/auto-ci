// Tests/AutoCICoreTests/ConfigStoreTests.swift
import XCTest
@testable import AutoCICore

final class ConfigStoreTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testAddAndLoadProject() throws {
        let store = ConfigStore(root: dir)
        let p = ProjectConfig(name: "demo", path: "/tmp/demo", remote: "origin")
        try store.upsert(p)
        let reloaded = ConfigStore(root: dir)
        XCTAssertEqual(reloaded.projects(), [p])
        XCTAssertEqual(reloaded.project(named: "demo"), p)
    }

    func testProjectForPathMatches() throws {
        let store = ConfigStore(root: dir)
        try store.upsert(ProjectConfig(name: "demo", path: "/tmp/demo", remote: "origin"))
        XCTAssertEqual(store.project(forPath: "/tmp/demo")?.name, "demo")
        XCTAssertNil(store.project(forPath: "/tmp/other"))
    }
}
