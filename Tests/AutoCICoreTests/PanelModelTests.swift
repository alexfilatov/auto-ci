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
}
