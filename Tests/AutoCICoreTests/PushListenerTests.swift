// Tests/AutoCICoreTests/PushListenerTests.swift
import XCTest
@testable import AutoCICore

final class PushListenerTests: XCTestCase {
    func testDecodesPushEventPayload() throws {
        let json = #"{"project":"demo","branch":"feature-x","sha":"abc","remote":"origin"}"#
        let event = try PushListener.decode(json)
        XCTAssertEqual(event, PushEvent(project: "demo", branch: "feature-x", sha: "abc", remote: "origin"))
    }

    func testIgnoresMalformedPayload() {
        XCTAssertThrowsError(try PushListener.decode("not json"))
    }
}
