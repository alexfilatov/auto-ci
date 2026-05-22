// Sources/AutoCIApp/ProjectGridView.swift
import SwiftUI
import AutoCICore

/// The grid of project tiles (or an empty/setup-issue state). Tapping a tile
/// asks the parent to navigate to that project's detail.
struct ProjectGridView: View {
    @ObservedObject var controller: AppController
    var onSelect: (String) -> Void

    private var orderedNames: [String] {
        let keys = controller.projects.map { p -> ProjectOrderKey in
            let last = controller.groupedHistory.first(where: { $0.project == p.name })?
                .entries.first?.timestamp
            return ProjectOrderKey(name: p.name, state: controller.liveState(p.name).state, lastActivity: last)
        }
        return orderedProjectNames(keys)
    }

    var body: some View {
        if !controller.setupIssues.isEmpty {
            setupBanner
        } else if controller.projects.isEmpty {
            emptyState
        } else {
            grid
        }
    }

    private var grid: some View {
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(orderedNames, id: \.self) { name in
                let live = controller.liveState(name)
                let last = controller.groupedHistory.first(where: { $0.project == name })?.entries.first
                if live.state == .fixing {
                    FixingTile(name: name, live: live)
                        .contentShape(Rectangle()).onTapGesture { onSelect(name) }
                        .gridCellColumns(2)
                } else {
                    ProjectTile(name: name, live: live, lastEntry: last)
                        .contentShape(Rectangle()).onTapGesture { onSelect(name) }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No repos watched").font(.subheadline.weight(.semibold))
            Text("Run `auto-ci init` in a repo to start watching it.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28).padding(.horizontal, 16)
    }

    private var setupBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("⚠ Setup required").font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
            ForEach(controller.setupIssues, id: \.self) { issue in
                Text(issue).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
    }
}

/// A standard square-ish tile for one project.
struct ProjectTile: View {
    let name: String
    let live: ProjectLiveState
    let lastEntry: HistoryEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Circle().fill(live.state.color).frame(width: 8, height: 8)
                Text(name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
            }
            Text(stateLabel).font(.system(size: 11)).foregroundStyle(ACColor.textPrimary).lineLimit(1)
            Text(metaLine).font(.system(size: 10.5)).foregroundStyle(ACColor.textSecondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(ACColor.surfaceCard))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ACColor.strokeSubtle, lineWidth: 0.5))
        .shadow(color: ACColor.cardShadow, radius: 2.5, x: 0, y: 1)
    }

    private var stateLabel: String {
        switch live.state {
        case .attention: return "Needs you"
        case .fixed: return "Fixed ✓"
        case .watching: return "Watching"
        case .fixing: return "Fixing…"
        case .idle: return "Idle"
        }
    }

    private var metaLine: String {
        if let e = lastEntry { return "\(e.branch.isEmpty ? "—" : e.branch) · \(Self.rel(e.timestamp))" }
        if let b = live.branch { return b }
        return "no pushes yet"
    }

    static func rel(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}

/// The emphasized full-width tile for the project currently being fixed.
struct FixingTile: View {
    let name: String
    let live: ProjectLiveState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle().fill(ACColor.stateFixing).frame(width: 8, height: 8)
                Text(name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Spacer()
                if let a = live.attempt {
                    Text("attempt \(a.current) of \(a.max)").font(.system(size: 10.5)).foregroundStyle(ACColor.textSecondary)
                }
            }
            Text(live.statusLine).font(.system(size: 11)).foregroundStyle(ACColor.textPrimary).lineLimit(1)
            ProgressView().progressViewStyle(.linear).tint(ACColor.stateFixing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(ACColor.surfaceCard))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ACColor.stateFixing.opacity(0.45), lineWidth: 1))
        .shadow(color: ACColor.cardShadow, radius: 2.5, x: 0, y: 1)
    }
}
