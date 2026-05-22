// Sources/AutoCIApp/PanelView.swift
import SwiftUI
import AutoCICore

enum PanelRoute: Equatable { case grid, detail(String), settings, about }

/// The popover root: summary bar on top, grid/detail/settings/about in the middle
/// (with a slide transition), footer toolbar on the bottom. Settings and About are
/// shown inline here — no separate popup windows.
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
        .frame(width: route == .settings || route == .about ? 360 : 320)
        .background(PanelBackground().ignoresSafeArea())
    }

    private func go(_ to: PanelRoute) {
        withAnimation(.easeInOut(duration: 0.22)) { route = to }
    }

    @ViewBuilder private var content: some View {
        switch route {
        case .grid:
            ProjectGridView(controller: controller) { go(.detail($0)) }
                .transition(.move(edge: .leading).combined(with: .opacity))
        case .detail(let name):
            ProjectDetailView(controller: controller, project: name) { go(.grid) }
                .transition(.move(edge: .trailing).combined(with: .opacity))
        case .settings:
            settingsScreen
                .transition(.move(edge: .trailing).combined(with: .opacity))
        case .about:
            aboutScreen
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    // MARK: Settings / About (inline)

    private var settingsScreen: some View {
        VStack(spacing: 0) {
            panelHeader("Settings")
            SettingsView(controller: controller).frame(maxHeight: 400)
        }
    }

    private var aboutScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader("About")
            VStack(alignment: .leading, spacing: 12) {
                Text("Auto-CI").font(.system(size: 15, weight: .semibold))
                Text("Built by Alex Filatov, who was far too lazy to keep refreshing the "
                   + "Actions tab to see if CI went red again. So now a robot babysits the "
                   + "pipeline and fixes it while he naps. 🛠️😴")
                    .font(.system(size: 11.5)).foregroundStyle(ACColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("Alex Filatov on LinkedIn ↗",
                     destination: URL(string: "https://www.linkedin.com/in/alexfilatov/")!)
                    .font(.system(size: 11.5))
                Text("Auto-fixes your CI so you don't have to.")
                    .font(.system(size: 10.5)).foregroundStyle(ACColor.textTertiary)
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func panelHeader(_ title: String) -> some View {
        HStack(spacing: 9) {
            Button { go(.grid) } label: {
                Image(systemName: "chevron.left").frame(width: 24, height: 24)
                    .foregroundStyle(ACColor.textSecondary)
                    .background(RoundedRectangle(cornerRadius: 7).fill(ACColor.fillSecondary))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(title).font(.system(size: 14, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 14).padding(.top, 13).padding(.bottom, 10)
    }

    // MARK: Chrome

    private var summaryBar: some View {
        let states = controller.projects.map { controller.liveState($0.name).state }
        let roll = summaryRollup(states: states, hasSetupIssues: !controller.setupIssues.isEmpty)
        return HStack(spacing: 10) {
            Circle().fill(controller.state.color).frame(width: 10, height: 10)
                .shadow(color: controller.state.color.opacity(0.7), radius: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(roll.title).font(.system(size: 13, weight: .semibold))
                Text(roll.subtitle).font(.system(size: 11)).foregroundStyle(ACColor.textSecondary)
            }
            Spacer()
            Button { go(.settings) } label: {
                Image(systemName: "gearshape").frame(width: 26, height: 26)
                    .foregroundStyle(ACColor.textSecondary)
                    .background(RoundedRectangle(cornerRadius: 7).fill(ACColor.fillSecondary))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Button("Settings") { go(.settings) }.buttonStyle(.borderless)
            Spacer()
            Button("About") { go(.about) }.buttonStyle(.borderless)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }.buttonStyle(.borderless)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 18).padding(.vertical, 10)
    }
}
