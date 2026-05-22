// Tests/AutoCICoreTests/LeaseStoreTests.swift
import XCTest
@testable import AutoCICore

final class LeaseStoreTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testHoldThenIsHeld() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let store = LeaseStore(root: root, now: { now })
        store.hold(project: "demo", branch: "feature", minutes: 30)
        XCTAssertTrue(store.isHeld(project: "demo", branch: "feature"))
    }

    func testReleaseClearsHold() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let store = LeaseStore(root: root, now: { now })
        store.hold(project: "demo", branch: "feature", minutes: 30)
        store.release(project: "demo", branch: "feature")
        XCTAssertFalse(store.isHeld(project: "demo", branch: "feature"))
    }

    func testExpiredLeaseIsNotHeldAndPruned() {
        final class Clock: @unchecked Sendable { var t = Date(timeIntervalSince1970: 1_000_000) }
        let clock = Clock()
        let store = LeaseStore(root: root, now: { clock.t })
        store.hold(project: "demo", branch: "feature", minutes: 1)
        clock.t = clock.t.addingTimeInterval(120) // 2 minutes later
        XCTAssertFalse(store.isHeld(project: "demo", branch: "feature"))
        XCTAssertTrue(store.active().isEmpty)
    }

    func testPersistsAcrossReload() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let store = LeaseStore(root: root, now: { now })
        store.hold(project: "demo", branch: "feature", minutes: 30)
        let reloaded = LeaseStore(root: root, now: { now })
        XCTAssertTrue(reloaded.isHeld(project: "demo", branch: "feature"))
    }
}
