// Tests/AutoCICoreTests/SignatureBuilderTests.swift
import XCTest
@testable import AutoCICore

final class SignatureBuilderTests: XCTestCase {
    let builder = SignatureBuilder()

    func testStripsVolatileBitsSoEquivalentFailuresMatch() {
        let logA = "2026-05-21T10:00:00Z /Users/alex/x/file.rb:12: error: undefined method `foo'"
        let logB = "2026-05-21T11:42:13Z /Users/bob/y/file.rb:99: error: undefined method `foo'"
        let a = builder.signature(job: "test", step: "rspec", logs: logA)
        let b = builder.signature(job: "test", step: "rspec", logs: logB)
        XCTAssertEqual(a.hash, b.hash)
    }

    func testDifferentErrorsDiffer() {
        let a = builder.signature(job: "test", step: "rspec", logs: "error: undefined method `foo'")
        let b = builder.signature(job: "test", step: "rspec", logs: "error: undefined method `bar'")
        XCTAssertNotEqual(a.hash, b.hash)
    }

    func testKeepsJobAndStep() {
        let s = builder.signature(job: "build", step: "compile", logs: "boom")
        XCTAssertEqual(s.job, "build"); XCTAssertEqual(s.step, "compile")
    }
}
