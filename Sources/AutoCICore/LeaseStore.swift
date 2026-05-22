// Sources/AutoCICore/LeaseStore.swift
import Foundation

public struct Lease: Codable, Equatable, Sendable {
    public let project: String
    public let branch: String
    public let expiresAt: Date
    public init(project: String, branch: String, expiresAt: Date) {
        self.project = project; self.branch = branch; self.expiresAt = expiresAt
    }
}

/// A JSON-backed store of active "holds" — branches a human (or another tool) has claimed,
/// telling auto-ci to stay out of the way until the lease expires or is released.
public final class LeaseStore: @unchecked Sendable {
    private let fileURL: URL
    private let now: @Sendable () -> Date
    private var leases: [Lease]

    public init(root: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.fileURL = root.appendingPathComponent("holds.json")
        self.now = now
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? dec.decode([Lease].self, from: data) {
            self.leases = decoded
        } else {
            self.leases = []
        }
    }

    /// Upsert a lease for `project`/`branch`, expiring `minutes` from now.
    public func hold(project: String, branch: String, minutes: Int) {
        leases.removeAll { $0.project == project && $0.branch == branch }
        leases.append(Lease(project: project, branch: branch,
                            expiresAt: now().addingTimeInterval(TimeInterval(minutes) * 60)))
        persist()
    }

    /// Remove any lease for `project`/`branch`.
    public func release(project: String, branch: String) {
        leases.removeAll { $0.project == project && $0.branch == branch }
        persist()
    }

    /// True if a non-expired lease exists for `project`/`branch`. Prunes expired leases on read.
    public func isHeld(project: String, branch: String) -> Bool {
        prune()
        return leases.contains { $0.project == project && $0.branch == branch }
    }

    /// All currently non-expired leases.
    public func active() -> [Lease] {
        prune()
        return leases
    }

    private func prune() {
        let cutoff = now()
        let before = leases.count
        leases.removeAll { $0.expiresAt <= cutoff }
        if leases.count != before { persist() }
    }

    private func persist() {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try? enc.encode(leases).write(to: fileURL)
    }
}
