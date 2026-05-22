// Tests/AutoCICoreTests/TestEditGuardTests.swift
import XCTest
@testable import AutoCICore

final class TestEditGuardTests: XCTestCase {
    private let patterns = ["tests/", "_test", ".test.", "spec"]

    func testDetectsTouchedTestFile() {
        let diff = """
        diff --git a/Tests/AutoCICoreTests/ModelsTests.swift b/Tests/AutoCICoreTests/ModelsTests.swift
        index 111..222 100644
        --- a/Tests/AutoCICoreTests/ModelsTests.swift
        +++ b/Tests/AutoCICoreTests/ModelsTests.swift
        @@ -1 +1 @@
        -old
        +new
        """
        let touched = TestEditGuard().testFilesTouched(in: diff, patterns: patterns)
        XCTAssertEqual(touched, ["Tests/AutoCICoreTests/ModelsTests.swift"])
    }

    func testIgnoresSourceOnlyDiff() {
        let diff = """
        diff --git a/Sources/AutoCICore/Models.swift b/Sources/AutoCICore/Models.swift
        --- a/Sources/AutoCICore/Models.swift
        +++ b/Sources/AutoCICore/Models.swift
        @@ -1 +1 @@
        -old
        +new
        """
        XCTAssertEqual(TestEditGuard().testFilesTouched(in: diff, patterns: patterns), [])
    }

    func testReturnsOnlyTestPathWhenBothTouched() {
        let diff = """
        diff --git a/Sources/AutoCICore/Models.swift b/Sources/AutoCICore/Models.swift
        +++ b/Sources/AutoCICore/Models.swift
        diff --git a/Tests/AutoCICoreTests/ModelsTests.swift b/Tests/AutoCICoreTests/ModelsTests.swift
        +++ b/Tests/AutoCICoreTests/ModelsTests.swift
        """
        XCTAssertEqual(TestEditGuard().testFilesTouched(in: diff, patterns: patterns),
                       ["Tests/AutoCICoreTests/ModelsTests.swift"])
    }
}
