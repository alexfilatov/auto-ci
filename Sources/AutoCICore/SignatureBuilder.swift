// Sources/AutoCICore/SignatureBuilder.swift
import Foundation
import CryptoKit

public struct SignatureBuilder: Sendable {
    public init() {}

    public func signature(job: String, step: String, logs: String) -> FailureSignature {
        let normalized = normalize(logs)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined().prefix(16)
        return FailureSignature(job: job, step: step, hash: String(hash))
    }

    /// Keep only error-bearing lines, strip volatile tokens (timestamps, paths, line numbers, hex, digits).
    func normalize(_ logs: String) -> String {
        let errorKeywords = ["error", "fail", "exception", "fatal", "undefined", "expected"]
        let lines = logs.split(separator: "\n").map(String.init)
        let relevant = lines.filter { line in
            let lower = line.lowercased()
            return errorKeywords.contains { lower.contains($0) }
        }
        let chosen: [String] = relevant.isEmpty ? Array(lines.suffix(20)) : relevant
        return chosen.map(scrub).joined(separator: "\n")
    }

    private func scrub(_ line: String) -> String {
        var s = line
        let patterns = [
            "\\d{4}-\\d{2}-\\d{2}[T ]\\d{2}:\\d{2}:\\d{2}\\S*", // timestamps
            "/[\\w./-]+",                                       // absolute paths
            "0x[0-9a-fA-F]+",                                   // hex addresses
            ":\\d+",                                            // :linenumbers
            "\\b\\d+\\b",                                       // bare numbers
        ]
        for p in patterns {
            s = s.replacingOccurrences(of: p, with: "", options: .regularExpression)
        }
        return s.trimmingCharacters(in: .whitespaces)
    }
}
