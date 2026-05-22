// Sources/AutoCICore/TestEditGuard.swift
import Foundation

public struct TestEditGuard: Sendable {
    public init() {}

    /// Returns the list of test file paths touched by a unified git diff, matching any of
    /// `patterns` (case-insensitive substring match on the file path).
    public func testFilesTouched(in diff: String, patterns: [String]) -> [String] {
        let lowerPatterns = patterns.map { $0.lowercased() }
        var paths: [String] = []
        var seen = Set<String>()

        func consider(_ path: String) {
            let trimmed = path.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed != "/dev/null" else { return }
            guard !seen.contains(trimmed) else { return }
            let lower = trimmed.lowercased()
            if lowerPatterns.contains(where: { !$0.isEmpty && lower.contains($0) }) {
                seen.insert(trimmed)
                paths.append(trimmed)
            }
        }

        for line in diff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("diff --git ") {
                // Format: diff --git a/<path> b/<path>
                if let range = line.range(of: " b/") {
                    consider(String(line[range.upperBound...]))
                }
            } else if line.hasPrefix("+++ b/") {
                consider(String(line.dropFirst("+++ b/".count)))
            }
        }
        return paths
    }
}
