// Sources/AutoCIApp/SettingsView.swift
import SwiftUI
import AutoCICore

/// Per-project configuration: grace period, test protection, protected branches, test patterns.
struct SettingsView: View {
    @ObservedObject var controller: AppController

    @State private var selectedName: String = ""
    @State private var graceSeconds: Int = 180
    @State private var protectTests: Bool = true
    @State private var protectedBranches: String = ""
    @State private var testPathPatterns: String = ""
    @State private var savedConfirmation: Bool = false

    var body: some View {
        Group {
            if controller.projects.isEmpty {
                VStack(spacing: 8) {
                    Text("No projects yet")
                        .font(.headline)
                    Text("Run `auto-ci init` in a repo.")
                        .foregroundStyle(.secondary)
                }
                .padding(40)
            } else {
                projectForm
            }
        }
        .frame(width: 420)
        .onAppear(perform: loadInitialSelection)
    }

    private var projectForm: some View {
        Form {
            Section {
                Picker("Project", selection: $selectedName) {
                    ForEach(controller.projects, id: \.name) { project in
                        Text(project.name).tag(project.name)
                    }
                }
            }

            Section("Behavior") {
                Stepper(value: $graceSeconds, in: 0...3600, step: 30) {
                    HStack {
                        Text("Grace period (seconds)")
                        Spacer()
                        TextField("", value: $graceSeconds, format: .number)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 64)
                    }
                }
                Text("How long auto-ci waits before fixing, so a human or another agent can take it first. 0 = act immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Protect tests", isOn: $protectTests)
                Text("Refuse fixes that weaken or delete tests.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Protected branches") {
                TextField("main, master", text: $protectedBranches)
                Text("Never push fixes directly to these; open a PR instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Test path patterns") {
                TextField("tests/, _test, .test.", text: $testPathPatterns)
                Text("Paths treated as tests for the protect-tests guard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("App") {
                Toggle("Start at Login", isOn: Binding(
                    get: { controller.launchAtLogin },
                    set: { _ in controller.toggleLaunchAtLogin() }
                ))
            }

            Section {
                HStack {
                    Button("Save", action: save)
                    if savedConfirmation {
                        Text("Saved ✓")
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: selectedName) { _, _ in loadFields() }
    }

    private func loadInitialSelection() {
        if selectedName.isEmpty, let first = controller.projects.first {
            selectedName = first.name
        }
        loadFields()
    }

    private func loadFields() {
        guard let project = controller.projects.first(where: { $0.name == selectedName }) else { return }
        graceSeconds = project.graceSeconds
        protectTests = project.protectTests
        protectedBranches = project.protectedBranches.joined(separator: ", ")
        testPathPatterns = project.testPathPatterns.joined(separator: ", ")
    }

    private func save() {
        guard let existing = controller.projects.first(where: { $0.name == selectedName }) else { return }
        let updated = ProjectConfig(
            name: existing.name,
            path: existing.path,
            remote: existing.remote,
            protectedBranches: splitCSV(protectedBranches),
            protectTests: protectTests,
            testPathPatterns: splitCSV(testPathPatterns),
            graceSeconds: graceSeconds
        )
        controller.updateProject(updated)
        withAnimation { savedConfirmation = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { savedConfirmation = false }
        }
    }

    private func splitCSV(_ input: String) -> [String] {
        input.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
