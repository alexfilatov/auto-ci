// Sources/AutoCICore/PanelModel.swift
import Foundation

/// The live state of a single watched project (and, rolled up, the whole app).
/// Severity ranks how urgently the user should look: attention > fixing > fixed > watching > idle.
public enum CIState: String, Codable, Equatable, Sendable, CaseIterable {
    case idle, watching, fixed, fixing, attention

    public var severity: Int {
        switch self {
        case .idle: return 0
        case .watching: return 1
        case .fixed: return 2
        case .fixing: return 3
        case .attention: return 4
        }
    }
}

/// The worst (most urgent) state across all projects; drives the menubar glyph + summary bar.
public func worstState(_ states: [CIState]) -> CIState {
    states.max(by: { $0.severity < $1.severity }) ?? .idle
}

/// Retry progress for a fixing project: e.g. attempt 2 of 3.
public struct Attempt: Equatable, Sendable {
    public let current: Int
    public let max: Int
    public init(current: Int, max: Int) { self.current = current; self.max = max }
}

/// Everything the panel needs to render one project's live status.
public struct ProjectLiveState: Equatable, Sendable {
    public var state: CIState
    public var statusLine: String
    public var runURL: String?
    public var branch: String?
    public var attempt: Attempt?

    public init(state: CIState = .idle, statusLine: String = "",
                runURL: String? = nil, branch: String? = nil, attempt: Attempt? = nil) {
        self.state = state; self.statusLine = statusLine
        self.runURL = runURL; self.branch = branch; self.attempt = attempt
    }
}

/// Maps a HistoryEntry.kind string to its one-glyph marker for the detail history list.
public func historyMarker(forKind kind: String) -> String {
    switch kind {
    case "fixed": return "✓"
    case "deferred": return "⏸"
    case "stuck", "gaveUp", "error": return "⚠"
    default: return "•"
    }
}
