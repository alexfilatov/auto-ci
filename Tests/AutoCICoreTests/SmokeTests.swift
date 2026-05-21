// Tests/AutoCICoreTests/SmokeTests.swift
import XCTest
@testable import AutoCICore

final class SmokeTests: XCTestCase {
    func testVersion() { XCTAssertEqual(AutoCI.version, "0.1.0") }
}
