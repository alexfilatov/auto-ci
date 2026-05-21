// Sources/AutoCICore/FixMemory.swift
import Foundation

public final class FixMemory: @unchecked Sendable {
    private let fileURL: URL
    private var records: [FixRecord]

    public init(projectDir: URL) {
        self.fileURL = projectDir.appendingPathComponent("fixes.json")
        try? FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? dec.decode([FixRecord].self, from: data) {
            self.records = decoded
        } else {
            self.records = []
        }
    }

    public func record(_ record: FixRecord) throws {
        records.append(record)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(records).write(to: fileURL)
    }

    /// Records sharing job+step, most-recent first. Exact-hash matches ranked first.
    public func matching(_ sig: FailureSignature) -> [FixRecord] {
        records
            .filter { $0.signature.job == sig.job && $0.signature.step == sig.step }
            .sorted { lhs, rhs in
                if (lhs.signature.hash == sig.hash) != (rhs.signature.hash == sig.hash) {
                    return lhs.signature.hash == sig.hash
                }
                return lhs.timestamp > rhs.timestamp
            }
    }
}
