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
}
