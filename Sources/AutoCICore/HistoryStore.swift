// Sources/AutoCICore/HistoryStore.swift
import Foundation

public struct HistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let project: String
    public let branch: String
    public let kind: String      // "fixed" | "stuck" | "gaveUp" | "error"
    public let detail: String
    public let runURL: String?
    public let timestamp: Date

    public init(id: UUID = UUID(), project: String, branch: String, kind: String,
                detail: String, runURL: String?, timestamp: Date) {
        self.id = id
        self.project = project
        self.branch = branch
        self.kind = kind
        self.detail = detail
        self.runURL = runURL
        self.timestamp = timestamp
    }
}

public struct ProjectHistory: Identifiable, Equatable, Sendable {
    public var id: String { project }
    public let project: String
    public let entries: [HistoryEntry]   // most-recent first

    public init(project: String, entries: [HistoryEntry]) {
        self.project = project
        self.entries = entries
    }
}

public final class HistoryStore: @unchecked Sendable {
    private static let cap = 200
    private let fileURL: URL
    private var entries: [HistoryEntry]   // stored oldest-first

    public init(root: URL) {
        self.fileURL = root.appendingPathComponent("history.json")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? dec.decode([HistoryEntry].self, from: data) {
            self.entries = decoded
        } else {
            self.entries = []
        }
    }

    public func record(_ entry: HistoryEntry) {
        entries.append(entry)
        if entries.count > Self.cap {
            entries.removeFirst(entries.count - Self.cap)
        }
        persist()
    }

    /// Most-recent first.
    public func all() -> [HistoryEntry] {
        entries.sorted { $0.timestamp > $1.timestamp }
    }

    /// Wipes all recorded history.
    public func clear() {
        entries.removeAll()
        persist()
    }

    /// Removes all history entries for a single project.
    public func removeProject(_ project: String) {
        entries.removeAll { $0.project == project }
        persist()
    }

    /// Groups, each project's entries most-recent first; groups ordered by their newest entry desc.
    public func grouped() -> [ProjectHistory] {
        let byProject = Dictionary(grouping: all(), by: { $0.project })
        return byProject
            .map { ProjectHistory(project: $0.key, entries: $0.value) }
            .sorted { lhs, rhs in
                (lhs.entries.first?.timestamp ?? .distantPast) > (rhs.entries.first?.timestamp ?? .distantPast)
            }
    }

    private func persist() {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try? enc.encode(entries).write(to: fileURL)
    }
}
