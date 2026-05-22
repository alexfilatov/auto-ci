# Auto-CI Menubar Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `MenuBarExtra(.menu)` dropdown with a SwiftUI popover panel showing a per-project status grid that slides to per-repo detail.

**Architecture:** Pure, unit-testable logic (worst-state roll-up, tile ordering, summary text, history markers) lives in `AutoCICore` and is TDD'd. The panel views and the `AppController` refactor to per-project live state live in `AutoCIApp`, verified by `swift build` + manual run (the App target has no test target, matching the repo).

**Tech Stack:** Swift 6, SwiftUI, `MenuBarExtra(.window)`, AppKit (existing). Tests via `swift test` (XCTest in `AutoCICoreTests`).

---

## File Structure

**Create:**
- `Sources/AutoCICore/PanelModel.swift` — pure types + functions: `CIState`, `ProjectLiveState`, `Attempt`, `worstState`, `orderedProjectNames`, `summaryRollup`, `historyMarker`.
- `Sources/AutoCIApp/PanelView.swift` — popover root: route state, summary bar, footer, hosts grid/detail.
- `Sources/AutoCIApp/ProjectGridView.swift` — the tile grid, tile cell, empty state, setup banner.
- `Sources/AutoCIApp/ProjectDetailView.swift` — per-repo detail screen.
- `Tests/AutoCICoreTests/PanelModelTests.swift` — tests for the pure logic.

**Modify:**
- `Sources/AutoCIApp/AutoCIApp.swift` — replace `AppState` enum with a `CIState` UI extension; refactor `AppController` to a `projectStates` map with derived global state; switch `MenuBarExtra` to `.window` hosting `PanelView`; add Hold/Release helpers.
- `Sources/AutoCIApp/SettingsView.swift` — add the "Start at Login" toggle (moved out of the menu footer).

---

## Task 1: Core — `CIState` + `worstState`

**Files:**
- Create: `Sources/AutoCICore/PanelModel.swift`
- Test: `Tests/AutoCICoreTests/PanelModelTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/AutoCICoreTests/PanelModelTests.swift`:

```swift
import XCTest
@testable import AutoCICore

final class PanelModelTests: XCTestCase {
    func testWorstStatePicksMostUrgent() {
        XCTAssertEqual(worstState([.idle, .watching, .fixed]), .fixed)
        XCTAssertEqual(worstState([.watching, .fixing, .fixed]), .fixing)
        XCTAssertEqual(worstState([.fixed, .attention, .fixing]), .attention)
        XCTAssertEqual(worstState([.idle, .watching]), .watching)
    }

    func testWorstStateEmptyIsIdle() {
        XCTAssertEqual(worstState([]), .idle)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PanelModelTests/testWorstStatePicksMostUrgent`
Expected: FAIL — `cannot find 'worstState' in scope` / `cannot find 'CIState'`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/AutoCICore/PanelModel.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PanelModelTests`
Expected: PASS (both `worstState` tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCICore/PanelModel.swift Tests/AutoCICoreTests/PanelModelTests.swift
git commit -m "feat: CIState + worstState roll-up"
```

---

## Task 2: Core — `ProjectLiveState` + `Attempt`

**Files:**
- Modify: `Sources/AutoCICore/PanelModel.swift`
- Test: `Tests/AutoCICoreTests/PanelModelTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `PanelModelTests`:

```swift
    func testProjectLiveStateDefaults() {
        let s = ProjectLiveState()
        XCTAssertEqual(s.state, .idle)
        XCTAssertNil(s.runURL)
        XCTAssertNil(s.branch)
        XCTAssertNil(s.attempt)
        XCTAssertEqual(s.statusLine, "")
    }

    func testAttemptEquatable() {
        XCTAssertEqual(Attempt(current: 2, max: 3), Attempt(current: 2, max: 3))
        XCTAssertNotEqual(Attempt(current: 1, max: 3), Attempt(current: 2, max: 3))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PanelModelTests/testProjectLiveStateDefaults`
Expected: FAIL — `cannot find 'ProjectLiveState'` / `cannot find 'Attempt'`.

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/AutoCICore/PanelModel.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PanelModelTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCICore/PanelModel.swift Tests/AutoCICoreTests/PanelModelTests.swift
git commit -m "feat: ProjectLiveState + Attempt"
```

---

## Task 3: Core — `historyMarker`

**Files:**
- Modify: `Sources/AutoCICore/PanelModel.swift`
- Test: `Tests/AutoCICoreTests/PanelModelTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `PanelModelTests`:

```swift
    func testHistoryMarkerMapping() {
        XCTAssertEqual(historyMarker(forKind: "fixed"), "✓")
        XCTAssertEqual(historyMarker(forKind: "deferred"), "⏸")
        XCTAssertEqual(historyMarker(forKind: "stuck"), "⚠")
        XCTAssertEqual(historyMarker(forKind: "gaveUp"), "⚠")
        XCTAssertEqual(historyMarker(forKind: "error"), "⚠")
        XCTAssertEqual(historyMarker(forKind: "anything-else"), "•")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PanelModelTests/testHistoryMarkerMapping`
Expected: FAIL — `cannot find 'historyMarker'`.

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/AutoCICore/PanelModel.swift`:

```swift
/// Maps a HistoryEntry.kind string to its one-glyph marker for the detail history list.
public func historyMarker(forKind kind: String) -> String {
    switch kind {
    case "fixed": return "✓"
    case "deferred": return "⏸"
    case "stuck", "gaveUp", "error": return "⚠"
    default: return "•"
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PanelModelTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCICore/PanelModel.swift Tests/AutoCICoreTests/PanelModelTests.swift
git commit -m "feat: historyMarker mapping"
```

---

## Task 4: Core — `orderedProjectNames`

**Files:**
- Modify: `Sources/AutoCICore/PanelModel.swift`
- Test: `Tests/AutoCICoreTests/PanelModelTests.swift`

Ordering rule (from spec): attention first, then active (fixing, then watching), then fixed, then idle; within the same rank, most-recent activity first; ties broken by name ascending for stability.

- [ ] **Step 1: Write the failing test**

Add to `PanelModelTests`:

```swift
    func testOrderingByRankThenRecency() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 2_000)
        let keys = [
            ProjectOrderKey(name: "idleRepo",   state: .idle,      lastActivity: nil),
            ProjectOrderKey(name: "greenOld",   state: .fixed,     lastActivity: t0),
            ProjectOrderKey(name: "greenNew",   state: .fixed,     lastActivity: t1),
            ProjectOrderKey(name: "watch",      state: .watching,  lastActivity: t1),
            ProjectOrderKey(name: "fixing",     state: .fixing,    lastActivity: t1),
            ProjectOrderKey(name: "needsYou",   state: .attention, lastActivity: t0),
        ]
        XCTAssertEqual(orderedProjectNames(keys),
                       ["needsYou", "fixing", "watch", "greenNew", "greenOld", "idleRepo"])
    }

    func testOrderingNameTiebreak() {
        let keys = [
            ProjectOrderKey(name: "bravo", state: .idle, lastActivity: nil),
            ProjectOrderKey(name: "alpha", state: .idle, lastActivity: nil),
        ]
        XCTAssertEqual(orderedProjectNames(keys), ["alpha", "bravo"])
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PanelModelTests/testOrderingByRankThenRecency`
Expected: FAIL — `cannot find 'ProjectOrderKey'` / `cannot find 'orderedProjectNames'`.

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/AutoCICore/PanelModel.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PanelModelTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCICore/PanelModel.swift Tests/AutoCICoreTests/PanelModelTests.swift
git commit -m "feat: orderedProjectNames for grid ordering"
```

---

## Task 5: Core — `summaryRollup`

**Files:**
- Modify: `Sources/AutoCICore/PanelModel.swift`
- Test: `Tests/AutoCICoreTests/PanelModelTests.swift`

Produces the summary-bar title + subtitle from the per-project states (and whether setup issues exist).

- [ ] **Step 1: Write the failing test**

Add to `PanelModelTests`:

```swift
    func testSummarySetupIssuesWins() {
        let r = summaryRollup(states: [.watching, .fixing], hasSetupIssues: true)
        XCTAssertEqual(r.title, "Setup required")
    }

    func testSummaryAllClear() {
        let r = summaryRollup(states: [.idle, .watching], hasSetupIssues: false)
        XCTAssertEqual(r.title, "All clear")
        XCTAssertEqual(r.subtitle, "2 watched · 0 fixing · 0 need you")
    }

    func testSummaryNeedsYouAndFixing() {
        let r = summaryRollup(states: [.attention, .fixing, .fixed, .watching], hasSetupIssues: false)
        XCTAssertEqual(r.title, "1 repo needs you")
        XCTAssertEqual(r.subtitle, "4 watched · 1 fixing · 1 need you")
    }

    func testSummaryFixingOnly() {
        let r = summaryRollup(states: [.fixing, .idle], hasSetupIssues: false)
        XCTAssertEqual(r.title, "Fixing 1 repo")
    }

    func testSummaryEmpty() {
        let r = summaryRollup(states: [], hasSetupIssues: false)
        XCTAssertEqual(r.title, "No repos watched")
        XCTAssertEqual(r.subtitle, "Run `auto-ci init` in a repo")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PanelModelTests/testSummaryAllClear`
Expected: FAIL — `cannot find 'summaryRollup'`.

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/AutoCICore/PanelModel.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PanelModelTests`
Expected: PASS (all summary tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCICore/PanelModel.swift Tests/AutoCICoreTests/PanelModelTests.swift
git commit -m "feat: summaryRollup for the panel summary bar"
```

---

## Task 6: App — refactor `AppController` to per-project state

**Files:**
- Modify: `Sources/AutoCIApp/AutoCIApp.swift`

This replaces the `AppState` enum with a `CIState` UI extension and converts the controller's single global state into a per-project map with a derived global state. No test target for App — verify with `swift build`.

- [ ] **Step 1: Replace the `AppState` enum with a `CIState` UI extension**

In `Sources/AutoCIApp/AutoCIApp.swift`, delete the entire `enum AppState { … }` block (the `case idle, watching, …` through its `dotEmoji`). Replace it with:

```swift
/// UI presentation for the Core CIState. The glyph is identical in every state — only color changes.
extension CIState {
    var color: Color {
        switch self {
        case .idle: return .black   // template image → auto-tinted by the menu bar
        case .watching: return .blue
        case .fixing: return .orange
        case .fixed: return .green
        case .attention: return .red
        }
    }

    var isActive: Bool { self == .watching || self == .fixing }

    /// A colored status dot that renders reliably in color inside native UI.
    var dotEmoji: String {
        switch self {
        case .watching: return "🔵"
        case .fixing: return "🟠"
        case .fixed: return "🟢"
        case .attention: return "🔴"
        case .idle: return "⚪️"
        }
    }
}
```

- [ ] **Step 2: Convert controller state to a per-project map**

In `AppController`, replace these stored properties:

```swift
    @Published var statusLine = "Idle — watching for pushes"
    @Published var state: AppState = .idle
    @Published var currentRunURL: String?
```

with:

```swift
    /// Per-project live state — the source of truth for the grid.
    @Published var projectStates: [String: ProjectLiveState] = [:]
    /// App-level status message (setup/login errors), shown when no per-project context applies.
    @Published var statusLine = "Idle — watching for pushes"

    /// Worst state across all projects; drives the menubar glyph color + summary bar.
    var state: CIState { worstState(projectStates.values.map { $0.state }) }

    /// The live state for a project (idle default if unseen).
    func liveState(_ project: String) -> ProjectLiveState { projectStates[project] ?? ProjectLiveState() }

    /// Convenience for the currently-active run URL (first project that has one).
    var currentRunURL: String? { projectStates.values.compactMap { $0.runURL }.first }
```

- [ ] **Step 3: Rewrite the transition methods to update the map**

Replace `enterWatching`, `enterHolding`, `enterFixing`, and `returnToIdle` with per-project versions:

```swift
    private func enterWatching(project: String, branch: String) {
        projectStates[project] = ProjectLiveState(
            state: .watching, statusLine: "Watching \(project)/\(branch)…", branch: branch)
        lastError = nil; lastErrorURL = nil
    }

    /// Saw a failure but holding back during the grace period. Stays benign (watching).
    private func enterHolding(project: String, branch: String, graceSeconds: Int) {
        projectStates[project] = ProjectLiveState(
            state: .watching,
            statusLine: "CI failed on \(project)/\(branch) — waiting \(graceSeconds)s to see if it's handled…",
            branch: branch)
    }

    private func enterFixing(project: String, branch: String, runURL: String) {
        projectStates[project] = ProjectLiveState(
            state: .fixing, statusLine: "Fixing \(project)/\(branch)…",
            runURL: runURL.isEmpty ? nil : runURL, branch: branch)
    }

    private func returnToIdle(project: String) {
        if var s = projectStates[project] {
            s.state = .idle; s.statusLine = "Idle — watching for pushes"; s.runURL = nil
            projectStates[project] = s
        }
    }
```

- [ ] **Step 4: Update `notifyAsync` to write per-project state**

In `notifyAsync(_:)`, the existing switch sets `state`/`statusLine`/`lastError`. Replace each `state = …` / `statusLine = …` assignment so it writes the project's entry. After the `switch` computes `(project, branch, kind, detail)`, the per-project state is set by replacing the in-switch assignments as follows:

```swift
        case .fixed(let p, let br, let det):
            (title, body) = ("CI fixed ✓", "\(p)/\(br): \(det)")
            projectStates[p] = ProjectLiveState(state: .fixed, statusLine: "CI fixed ✓ — \(p)/\(br)",
                                                runURL: liveState(p).runURL, branch: br)
            (project, branch, kind, detail) = (p, br, "fixed", det)
            scheduleIdleReset(project: p)
        case .stuck(let p, let br):
            (title, body) = ("CI stuck — needs you", "\(p)/\(br)")
            projectStates[p] = ProjectLiveState(state: .attention,
                                                statusLine: "CI stuck — needs you: \(p)/\(br)",
                                                runURL: liveState(p).runURL, branch: br)
            (project, branch, kind, detail) = (p, br, "stuck", "stuck — needs you")
        case .gaveUp(let p, let br):
            (title, body) = ("CI fix gave up", "\(p)/\(br)")
            projectStates[p] = ProjectLiveState(state: .attention,
                                                statusLine: "CI fix gave up: \(p)/\(br)",
                                                runURL: liveState(p).runURL, branch: br)
            (project, branch, kind, detail) = (p, br, "gaveUp", "fix gave up")
        case .error(let p, let message):
            (title, body) = ("Auto-CI error", "\(p): \(message)")
            projectStates[p] = ProjectLiveState(state: .attention, statusLine: "Auto-CI error — \(p)",
                                                runURL: liveState(p).runURL, branch: liveState(p).branch)
            lastError = message
            lastErrorURL = liveState(p).runURL
            (project, branch, kind, detail) = (p, "", "error", message)
        case .deferred(let p, let br, let reason):
            (title, body) = ("Auto-CI stood down", "\(p)/\(br): \(reason)")
            projectStates[p] = ProjectLiveState(state: .idle,
                                                statusLine: "Stood down — \(p)/\(br) is being fixed elsewhere",
                                                branch: br)
            (project, branch, kind, detail) = (p, br, "deferred", reason)
```

Note: `HistoryEntry(... runURL: currentRunURL ...)` further down still works because `currentRunURL` is now a computed property. Leave that line unchanged.

- [ ] **Step 5: Update `scheduleIdleReset` and the preflight to be project-aware**

Replace `scheduleIdleReset()` with:

```swift
    private func scheduleIdleReset(project: String) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self else { return }
            if self.liveState(project).state == .fixed { self.returnToIdle(project: project) }
        }
    }
```

In `runDependencyPreflight()`, replace `self.state = .attention` with nothing (global `state` is now derived) and keep the `statusLine`/`setupIssues` assignments:

```swift
            self.statusLine = "Setup required"
            self.setupIssues = problems.map { $0.hint }
```

In `toggleLaunchAtLogin()`'s catch branch, the `statusLine = …` assignment is unchanged (still valid).

- [ ] **Step 6: Build to verify it compiles**

Run: `swift build`
Expected: Builds successfully. If the menubar label in Step references (Task 11) aren't updated yet, the `MenuBarExtra` body still compiles because `controller.state` (now `CIState`) keeps `.color`/`.dotEmoji`/`.isActive` via the extension, and `currentRunURL` is still readable.

- [ ] **Step 7: Commit**

```bash
git add Sources/AutoCIApp/AutoCIApp.swift
git commit -m "refactor: per-project live state with derived global state"
```

---

## Task 7: App — Hold/Release helpers on `AppController`

**Files:**
- Modify: `Sources/AutoCIApp/AutoCIApp.swift`

- [ ] **Step 1: Add a `LeaseStore` and helpers**

In `AppController`, near the other stores (`store`, `history`), add:

```swift
    private let leases = LeaseStore(root: ConfigStore.defaultRoot)
    /// Default UI hold duration (mirrors the CLI default).
    private static let holdMinutes = 30
```

Then add these methods (place them next to `stopWatching`):

```swift
    /// The branch a Hold/Release acts on for a project: its active/most-recent branch.
    func activeBranch(_ project: String) -> String? { liveState(project).branch }

    /// True if the project's active branch is currently held.
    func isHeld(_ project: String) -> Bool {
        guard let branch = activeBranch(project) else { return false }
        return leases.isHeld(project: project, branch: branch)
    }

    /// Claim the project's active branch so auto-ci stands down. No-op if no branch is known.
    func holdActiveBranch(_ project: String) {
        guard let branch = activeBranch(project) else { return }
        leases.hold(project: project, branch: branch, minutes: Self.holdMinutes)
        objectWillChange.send()
    }

    /// Release the hold on the project's active branch.
    func releaseActiveBranch(_ project: String) {
        guard let branch = activeBranch(project) else { return }
        leases.release(project: project, branch: branch)
        objectWillChange.send()
    }
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Builds successfully.

- [ ] **Step 3: Commit**

```bash
git add Sources/AutoCIApp/AutoCIApp.swift
git commit -m "feat: Hold/Release helpers on AppController"
```

---

## Task 8: App — `ProjectGridView` (grid, tiles, empty/setup states)

**Files:**
- Create: `Sources/AutoCIApp/ProjectGridView.swift`

- [ ] **Step 1: Create the grid view**

Create `Sources/AutoCIApp/ProjectGridView.swift`:

```swift
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
                    FixingTile(name: name, live: live).onTapGesture { onSelect(name) }
                        .gridCellColumns(2)
                } else {
                    ProjectTile(name: name, live: live, lastEntry: last).onTapGesture { onSelect(name) }
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
            Text(stateLabel).font(.system(size: 11)).foregroundStyle(.primary).lineLimit(1)
            Text(metaLine).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.06)))
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
                Circle().fill(Color.orange).frame(width: 8, height: 8)
                Text(name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Spacer()
                if let a = live.attempt {
                    Text("attempt \(a.current) of \(a.max)").font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
            Text(live.statusLine).font(.system(size: 11)).foregroundStyle(.primary).lineLimit(1)
            ProgressView().progressViewStyle(.linear).tint(.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.06)))
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Builds successfully.

- [ ] **Step 3: Commit**

```bash
git add Sources/AutoCIApp/ProjectGridView.swift
git commit -m "feat: ProjectGridView with tiles, empty + setup states"
```

---

## Task 9: App — `ProjectDetailView`

**Files:**
- Create: `Sources/AutoCIApp/ProjectDetailView.swift`

- [ ] **Step 1: Create the detail view**

Create `Sources/AutoCIApp/ProjectDetailView.swift`:

```swift
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
        HStack(spacing: 4) {
            Text(live.statusLine.isEmpty ? "Watching for pushes." : live.statusLine)
                .font(.system(size: 11.5)).foregroundStyle(.primary)
            if let urlString = live.runURL, let url = URL(string: urlString) {
                Link("View run ↗", destination: url).font(.system(size: 11.5))
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        HStack(spacing: 7) {
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
                Text("RECENT").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary).padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
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
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Builds successfully.

- [ ] **Step 3: Commit**

```bash
git add Sources/AutoCIApp/ProjectDetailView.swift
git commit -m "feat: ProjectDetailView with actions, chips, history"
```

---

## Task 10: App — `PanelView` root (summary bar, routing, footer)

**Files:**
- Create: `Sources/AutoCIApp/PanelView.swift`

- [ ] **Step 1: Create the panel root**

Create `Sources/AutoCIApp/PanelView.swift`:

```swift
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
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Builds successfully.

- [ ] **Step 3: Commit**

```bash
git add Sources/AutoCIApp/PanelView.swift
git commit -m "feat: PanelView root with summary bar, routing, footer"
```

---

## Task 11: App — switch `MenuBarExtra` to `.window` + move Start-at-Login to Settings

**Files:**
- Modify: `Sources/AutoCIApp/AutoCIApp.swift`
- Modify: `Sources/AutoCIApp/SettingsView.swift`

- [ ] **Step 1: Replace the MenuBarExtra body**

In `Sources/AutoCIApp/AutoCIApp.swift`, replace the entire `MenuBarExtra { … } label: { … } .menuBarExtraStyle(.menu)` block with:

```swift
        MenuBarExtra {
            PanelView(controller: controller)
        } label: {
            Image(nsImage: AutoCIIcon(color: controller.state.color)
                .rendered(template: controller.state == .idle))
        }
        .menuBarExtraStyle(.window)
```

- [ ] **Step 2: Remove the now-dead `entryView` helper**

Delete the `@ViewBuilder private func entryView(_ entry: HistoryEntry) -> some View { … }` method from `AutoCIApp` — its history rendering now lives in `ProjectDetailView`. (Removing dead code per project convention; verify no other reference remains.)

- [ ] **Step 3: Add Start-at-Login toggle to Settings**

In `Sources/AutoCIApp/SettingsView.swift`, add a new section to `projectForm` (before the final `Save` section):

```swift
            Section("App") {
                Toggle("Start at Login", isOn: Binding(
                    get: { controller.launchAtLogin },
                    set: { _ in controller.toggleLaunchAtLogin() }
                ))
            }
```

- [ ] **Step 4: Build the whole app**

Run: `swift build`
Expected: Builds successfully with no warnings. Fix any unused-variable / unused-import warnings in touched files (project convention: never leave warnings).

- [ ] **Step 5: Run the full test suite**

Run: `swift test`
Expected: All tests pass (the `PanelModelTests` plus all pre-existing tests).

- [ ] **Step 6: Manual smoke test**

Run: `swift run AutoCIApp` (or build + launch `AutoCI.app`). Verify:
- Menubar icon appears; clicking it opens the popover panel (not a menu).
- Summary bar shows correct roll-up; footer has Settings…/About/Quit; gear opens Settings.
- With ≥1 project: grid renders tiles; tapping a tile slides to detail; back arrow returns.
- Empty state (no projects) and setup-banner state render when applicable.
- Settings now has a working "Start at Login" toggle.

- [ ] **Step 7: Commit**

```bash
git add Sources/AutoCIApp/AutoCIApp.swift Sources/AutoCIApp/SettingsView.swift
git commit -m "feat: switch menubar to window panel; move Start-at-Login to Settings"
```

---

## Self-Review Notes

- **Spec coverage:** summary bar (T5/T10), grid + full-width fixing tile + empty/setup states (T8), slide-to-detail (T9/T10), state-adaptive actions + Hold/Release + Stop watching (T7/T9), read-only chips (T9), history markers (T3/T9), per-project state model + derived global (T1/T2/T6), `.window` switch + Start-at-Login move (T11). All covered.
- **Hold target = active/last branch** with disabled-when-nil — T7 (`holdActiveBranch` guards on `activeBranch`) + T9 (`.disabled`).
- **Type consistency:** `CIState`, `ProjectLiveState`, `Attempt`, `ProjectOrderKey`, `orderedProjectNames`, `summaryRollup`, `historyMarker` defined in T1–T5 and used with matching signatures in T6–T10. `liveState(_:)`, `activeBranch(_:)`, `isHeld(_:)`, `holdActiveBranch(_:)`, `releaseActiveBranch(_:)` defined T6/T7 and used in T8–T10.
- **No App unit tests** is intentional — the App target has no test target in `Package.swift`; App tasks are build- + manual-verified, all testable logic pushed to Core.
