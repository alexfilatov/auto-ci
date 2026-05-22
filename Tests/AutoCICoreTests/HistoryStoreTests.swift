// Tests/AutoCICoreTests/HistoryStoreTests.swift
import XCTest
@testable import AutoCICore

final class HistoryStoreTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testRecordPersistsAndReloadsMostRecentFirst() throws {
        let store = HistoryStore(root: dir)
        let older = HistoryEntry(project: "a", branch: "main", kind: "fixed", detail: "first",
                                 runURL: nil, timestamp: Date(timeIntervalSince1970: 100))
        let newer = HistoryEntry(project: "a", branch: "main", kind: "stuck", detail: "second",
                                 runURL: nil, timestamp: Date(timeIntervalSince1970: 200))
        store.record(older)
        store.record(newer)

        let reloaded = HistoryStore(root: dir)
        let all = reloaded.all()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first?.detail, "second")
        XCTAssertEqual(all.last?.detail, "first")
    }

    func testGroupedByProjectOrderedByNewest() throws {
        let store = HistoryStore(root: dir)
        // project "a" has an older entry; project "b" has a newer one → b first.
        store.record(HistoryEntry(project: "a", branch: "m", kind: "fixed", detail: "a-old",
                                  runURL: nil, timestamp: Date(timeIntervalSince1970: 100)))
        store.record(HistoryEntry(project: "a", branch: "m", kind: "fixed", detail: "a-mid",
                                  runURL: nil, timestamp: Date(timeIntervalSince1970: 150)))
        store.record(HistoryEntry(project: "b", branch: "m", kind: "fixed", detail: "b-new",
                                  runURL: nil, timestamp: Date(timeIntervalSince1970: 300)))

        let groups = store.grouped()
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first?.project, "b")
        XCTAssertEqual(groups.last?.project, "a")
        // each group's entries most-recent first
        XCTAssertEqual(groups.last?.entries.first?.detail, "a-mid")
        XCTAssertEqual(groups.last?.entries.last?.detail, "a-old")
    }

    func testCapsAtTwoHundredDroppingOldest() throws {
        let store = HistoryStore(root: dir)
        for i in 0..<205 {
            store.record(HistoryEntry(project: "p", branch: "b", kind: "fixed", detail: "e\(i)",
                                      runURL: nil, timestamp: Date(timeIntervalSince1970: Double(i))))
        }
        let all = store.all()
        XCTAssertEqual(all.count, 200)
        // oldest (e0) dropped; newest is e204
        XCTAssertEqual(all.first?.detail, "e204")
        XCTAssertFalse(all.contains { $0.detail == "e0" })
        XCTAssertFalse(all.contains { $0.detail == "e4" })
        XCTAssertTrue(all.contains { $0.detail == "e5" })
    }
}
