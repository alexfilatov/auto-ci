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
