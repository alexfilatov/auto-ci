// Sources/AutoCIApp/ProjectDetailView.swift
import SwiftUI
import AutoCICore

/// One project's detail screen: status + run link, state-adaptive actions
/// (View run / Hold-Release / Stop watching), config chips, and recent history.
struct ProjectDetailView: View {
    @ObservedObject var controller: AppController
    let project: String
    var onBack: () -> Void

    private var live: ProjectLiveState { controller.liveState(project) }
    private var config: ProjectConfig? { controller.projects.first { $0.name == project } }
    private var entries: [HistoryEntry] {
        controller.groupedHistory.first { $0.project == project }?.entries ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            statusLine
            actions
            chips
            Divider().padding(.horizontal, 14)
            historyList
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Button(action: onBack) { Image(systemName: "chevron.left") }
                .buttonStyle(.plain).frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.06)))
            Circle().fill(live.state.color).frame(width: 9, height: 9)
            Text(project).font(.system(size: 14, weight: .semibold))
            Spacer()
            Text(stateWord).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.top, 13).padding(.bottom, 12)
    }

    private var statusLine: some View {
        Text(live.statusLine.isEmpty ? "Watching for pushes." : live.statusLine)
            .font(.system(size: 11.5)).foregroundStyle(.primary)
            .padding(.horizontal, 14).padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        HStack(spacing: 7) {
            if controller.lastError != nil && live.state == .attention {
                Button { controller.showErrorDetails() } label: { actionLabel("Error details…") }
                    .buttonStyle(.plain)
            }
            if let urlString = live.runURL, let url = URL(string: urlString) {
                Link(destination: url) { actionLabel("View run ↗") }
            }
            if controller.isHeld(project) {
                Button { controller.releaseActiveBranch(project) } label: { actionLabel("Release") }
                    .buttonStyle(.plain)
            } else {
                Button { controller.holdActiveBranch(project) } label: { actionLabel("Hold") }
                    .buttonStyle(.plain).disabled(controller.activeBranch(project) == nil)
            }
            Button {
                if let c = config { controller.stopWatching(c); onBack() }
            } label: { actionLabel("Stop watching", danger: true) }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.bottom, 12)
    }

    private func actionLabel(_ text: String, danger: Bool = false) -> some View {
        Text(text).font(.system(size: 11)).frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(danger ? Color.red.opacity(0.16) : .white.opacity(0.07)))
            .foregroundStyle(danger ? Color.red : .primary)
    }

    @ViewBuilder private var chips: some View {
        if let c = config {
            HStack(spacing: 6) {
                chip("protected: \(c.protectedBranches.joined(separator: ", "))")
                chip(c.protectTests ? "test-guard on" : "test-guard off")
                chip("grace \(c.graceSeconds)s")
            }
            .padding(.horizontal, 14).padding(.bottom, 12)
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text).font(.system(size: 10)).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(.white.opacity(0.06)))
    }

    private var historyList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("RECENT").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if !entries.isEmpty {
                        Button("Clear") { controller.clearHistory(project: project) }
                            .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
                if entries.isEmpty {
                    Text("No fixes yet").font(.caption).foregroundStyle(.secondary).padding(14)
                } else {
                    ForEach(entries) { e in historyRow(e) }
                }
            }
        }
        .frame(maxHeight: 220)
    }

    private func historyRow(_ e: HistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(historyMarker(forKind: e.kind)).font(.system(size: 12)).frame(width: 13)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(e.branch.isEmpty ? "—" : e.branch) — \(e.detail)").font(.system(size: 11.5)).lineLimit(2)
                Text(ProjectTile.rel(e.timestamp)).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer()
            if let urlString = e.runURL, let url = URL(string: urlString) {
                Link("↗", destination: url).font(.system(size: 11))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private var stateWord: String {
        switch live.state {
        case .attention: return "Needs you"
        case .fixed: return "Healthy"
        case .fixing: return "Fixing"
        case .watching: return "Watching"
        case .idle: return "Idle"
        }
    }
}
