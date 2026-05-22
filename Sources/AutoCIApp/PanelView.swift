// Sources/AutoCIApp/PanelView.swift
import SwiftUI
import AutoCICore

enum PanelRoute: Equatable { case grid, detail(String) }

/// The popover root: summary bar on top, grid/detail in the middle (with a slide
/// transition), footer toolbar on the bottom.
struct PanelView: View {
    @ObservedObject var controller: AppController
    @State private var route: PanelRoute = .grid

    var body: some View {
        VStack(spacing: 0) {
            summaryBar
            Divider().padding(.horizontal, 14)
            content
            Divider().padding(.horizontal, 14)
            footer
        }
        .frame(width: 320)
    }

    @ViewBuilder private var content: some View {
        switch route {
        case .grid:
            ProjectGridView(controller: controller) { name in
                withAnimation(.easeInOut(duration: 0.22)) { route = .detail(name) }
            }
            .transition(.move(edge: .leading).combined(with: .opacity))
        case .detail(let name):
            ProjectDetailView(controller: controller, project: name) {
                withAnimation(.easeInOut(duration: 0.22)) { route = .grid }
            }
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private var summaryBar: some View {
        let states = controller.projects.map { controller.liveState($0.name).state }
        let roll = summaryRollup(states: states, hasSetupIssues: !controller.setupIssues.isEmpty)
        return HStack(spacing: 10) {
            Circle().fill(controller.state.color).frame(width: 10, height: 10)
                .shadow(color: controller.state.color.opacity(0.7), radius: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(roll.title).font(.system(size: 13, weight: .semibold))
                Text(roll.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            SettingsLink { Image(systemName: "gearshape") }
                .buttonStyle(.plain).frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.06)))
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            SettingsLink { footerItem("Settings…") }.buttonStyle(.plain)
            Button { controller.showAbout() } label: { footerItem("About") }.buttonStyle(.plain)
            Button { NSApplication.shared.terminate(nil) } label: { footerItem("Quit") }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    private func footerItem(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(.clear))
            .contentShape(Rectangle())
    }
}
