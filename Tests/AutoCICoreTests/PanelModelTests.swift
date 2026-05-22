import XCTest
@testable import AutoCICore

final class PanelModelTests: XCTestCase {
    func testWorstStatePicksMostUrgent() {
        XCTAssertEqual(worstState([.idle, .watching, .fixed]), .fixed)
        XCTAssertEqual(worstState([.watching, .fixing, .fixed]), .fixing)
        XCTAssertEqual(worstState([.fixed, .attention, .fixing]), .attention)
        XCTAssertEqual(worstState([.idle, .watching]), .watching)
    }
    func testWorstStateEmptyIsIdle() {
        XCTAssertEqual(worstState([]), .idle)
    }

    func testProjectLiveStateDefaults() {
        let s = ProjectLiveState()
        XCTAssertEqual(s.state, .idle)
        XCTAssertNil(s.runURL)
        XCTAssertNil(s.branch)
        XCTAssertNil(s.attempt)
        XCTAssertEqual(s.statusLine, "")
    }
    func testAttemptEquatable() {
        XCTAssertEqual(Attempt(current: 2, max: 3), Attempt(current: 2, max: 3))
        XCTAssertNotEqual(Attempt(current: 1, max: 3), Attempt(current: 2, max: 3))
    }

    func testHistoryMarkerMapping() {
        XCTAssertEqual(historyMarker(forKind: "fixed"), "✓")
        XCTAssertEqual(historyMarker(forKind: "deferred"), "⏸")
        XCTAssertEqual(historyMarker(forKind: "stuck"), "⚠")
        XCTAssertEqual(historyMarker(forKind: "gaveUp"), "⚠")
        XCTAssertEqual(historyMarker(forKind: "error"), "⚠")
        XCTAssertEqual(historyMarker(forKind: "anything-else"), "•")
    }

    func testOrderingByRankThenRecency() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 2_000)
        let keys = [
            ProjectOrderKey(name: "idleRepo",   state: .idle,      lastActivity: nil),
            ProjectOrderKey(name: "greenOld",   state: .fixed,     lastActivity: t0),
            ProjectOrderKey(name: "greenNew",   state: .fixed,     lastActivity: t1),
            ProjectOrderKey(name: "watch",      state: .watching,  lastActivity: t1),
            ProjectOrderKey(name: "fixing",     state: .fixing,    lastActivity: t1),
            ProjectOrderKey(name: "needsYou",   state: .attention, lastActivity: t0),
        ]
        XCTAssertEqual(orderedProjectNames(keys),
                       ["needsYou", "fixing", "watch", "greenNew", "greenOld", "idleRepo"])
    }
    func testOrderingNameTiebreak() {
        let keys = [
            ProjectOrderKey(name: "bravo", state: .idle, lastActivity: nil),
            ProjectOrderKey(name: "alpha", state: .idle, lastActivity: nil),
        ]
        XCTAssertEqual(orderedProjectNames(keys), ["alpha", "bravo"])
    }
}
