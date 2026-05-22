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

/// One project's sort inputs for the grid ordering.
public struct ProjectOrderKey: Equatable, Sendable {
    public let name: String
    public let state: CIState
    public let lastActivity: Date?
    public init(name: String, state: CIState, lastActivity: Date?) {
        self.name = name; self.state = state; self.lastActivity = lastActivity
    }
}

/// Display order for the grid: attention, fixing, watching, fixed, idle;
/// then most-recent activity first; then name ascending.
public func orderedProjectNames(_ keys: [ProjectOrderKey]) -> [String] {
    func rank(_ s: CIState) -> Int {
        switch s {
        case .attention: return 0
        case .fixing: return 1
        case .watching: return 2
        case .fixed: return 3
        case .idle: return 4
        }
    }
    return keys.sorted { a, b in
        if rank(a.state) != rank(b.state) { return rank(a.state) < rank(b.state) }
        let ta = a.lastActivity ?? .distantPast
        let tb = b.lastActivity ?? .distantPast
        if ta != tb { return ta > tb }
        return a.name < b.name
    }.map { $0.name }
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

/// Title + subtitle for the summary bar. Title precedence: setup issues, then needs-you,
/// then fixing, then all-clear. Empty list = no repos.
public func summaryRollup(states: [CIState], hasSetupIssues: Bool) -> (title: String, subtitle: String) {
    if hasSetupIssues { return ("Setup required", "Resolve the issues below") }
    if states.isEmpty { return ("No repos watched", "Run `auto-ci init` in a repo") }

    let needYou = states.filter { $0 == .attention }.count
    let fixing = states.filter { $0 == .fixing }.count
    let subtitle = "\(states.count) watched · \(fixing) fixing · \(needYou) need you"

    let title: String
    if needYou > 0 {
        title = needYou == 1 ? "1 repo needs you" : "\(needYou) repos need you"
    } else if fixing > 0 {
        title = fixing == 1 ? "Fixing 1 repo" : "Fixing \(fixing) repos"
    } else {
        title = "All clear"
    }
    return (title, subtitle)
}
