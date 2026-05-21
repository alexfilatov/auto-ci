// Tests/AutoCICoreTests/FixMemoryTests.swift
import XCTest
@testable import AutoCICore

final class FixMemoryTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testRecordAndRecallBySignature() throws {
        let mem = FixMemory(projectDir: dir)
        let sig = FailureSignature(job: "test", step: "rspec", hash: "abc")
        let rec = FixRecord(signature: sig, summary: "added gem", succeeded: true, timestamp: Date())
        try mem.record(rec)
        let recalled = FixMemory(projectDir: dir).matching(sig)
        XCTAssertEqual(recalled.count, 1)
        XCTAssertEqual(recalled.first?.summary, "added gem")
    }

    func testNoMatchReturnsEmpty() throws {
        let mem = FixMemory(projectDir: dir)
        XCTAssertTrue(mem.matching(FailureSignature(job: "x", step: "y", hash: "z")).isEmpty)
    }
}
