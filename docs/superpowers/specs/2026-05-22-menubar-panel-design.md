# Auto-CI menubar panel — design

**Date:** 2026-05-22
**Status:** Approved (design), pending implementation plan

## Goal

Replace the current `MenuBarExtra(.menu)` dropdown with a rich SwiftUI popover panel: a per-project status grid the user can scan at a glance, with slide-to-detail drill-in per repo. The menubar glyph itself is unchanged (single Auto-CI icon, color = worst overall state).

## Non-goals (YAGNI)

- No editing of project config from the panel (config chips are read-only; editing stays in `SettingsView`).
- No live CI log streaming in the panel.
- No search/filter across projects or history.
- No change to notifications, the fixing engine, the daemon, or the CLI surface (beyond reusing `LeaseStore` for Hold/Release).

## Technical shape

- Change `MenuBarExtra` from `.menuBarExtraStyle(.menu)` to `.menuBarExtraStyle(.window)`, with content being a new SwiftUI root view (`PanelView`) ~320pt wide.
- `AppController` remains the single source of truth. The panel renders its `@Published` state; it does not own logic.
- The Settings scene and the menubar icon/label code are unchanged.
- Visual style: translucent dark popover (system material), rounded 16pt, matching the approved mockups in `.superpowers/brainstorm/`.

## State model change: per-project live state

Today `AppController` holds a single global `state: AppState`, `statusLine: String`, and `currentRunURL: String?`. The grid needs each repo's own current state.

**Change:** introduce a per-project live-state map.

```
struct ProjectLiveState: Equatable {
    var state: AppState          // idle | watching | fixing | fixed | attention
    var statusLine: String
    var runURL: String?
    var branch: String?          // the active/most-recent branch (for Hold target + meta line)
    var attempt: (Int, Int)?     // (current, max) — drives the progress label on the fixing tile
}

@Published var projectStates: [String: ProjectLiveState]   // keyed by project name
```

- The existing transition methods (`enterWatching`, `enterFixing`, `enterHolding`, and the `notifyAsync` switch) are rekeyed to update `projectStates[project]` instead of (or in addition to) the global fields.
- The **global** menubar state is derived: `state = worst(across projectStates)` using priority **attention(red) > fixing(orange) > fixed(green) > watching(blue) > idle(grey)**. This drives the menubar glyph color and the summary bar.
- `setupIssues` continue to live globally (they are app-level, not per-repo).
- Projects with no live activity yet default to `.idle` (or derive a soft state from their newest history entry, but live transitions always win).

## Three zones (PanelView)

Navigation is a simple enum held in `PanelView`:

```
enum PanelRoute: Equatable { case grid, detail(String) }   // String = project name
```

A horizontal slide transition animates between `.grid` and `.detail`.

### Summary bar (always visible, top)
- Health dot colored by the derived global state.
- Title: human roll-up — e.g. "1 repo needs you", "Fixing gymbile…", "All clear".
- Sub: counts — "4 watched · 1 fixing · 2 green".
- Gear button → opens Settings (`SettingsLink`).

### Project grid (`.grid` route)
- 2-column grid of tiles, one per watched project, ordered: attention first, then active (fixing/watching), then by most-recent activity.
- **Tile** shows: state dot (color), project name (truncated), a state label, and a meta line (branch · relative time, or "no pushes yet").
- The repo that is **actively fixing** renders as a **full-width tile** with an animated progress bar and the attempt label ("attempt 2 of 3").
- **Empty state** (no projects): replace grid with a prompt to run `auto-ci init` in a repo.
- **Setup issues** present (missing/unauthenticated `gh`/`claude`): replace grid with a warning banner listing the issues (current `setupIssues` content).

### Footer toolbar (always visible, bottom)
- Three items: **Settings… · About · Quit**.
- "Start at Login" moves out of the footer into `SettingsView` (a toggle there).

## Tile detail (`.detail(project)` route)

Reached by tapping a tile; slides in with a back arrow returning to `.grid`.

- **Header:** back arrow, state dot, project name, short state word ("Needs you" / "Healthy" / "Fixing").
- **Status line:** the project's live `statusLine`, with an inline clickable run link when `runURL` is set.
- **Action row (state-adaptive):**
  - "View run ↗" — shown only when a `runURL` exists (leads for stuck/fixing repos).
  - "Hold" / "Release" — toggles based on current lease (see below).
  - "Stop watching" — danger style; calls existing `stopWatching(project)`.
- **Config chips (read-only):** protected branches, test-guard on/off, grace seconds — from `ProjectConfig`.
- **Recent history:** that project's entries (most-recent first) from `HistoryStore.grouped()`, each row with a kind marker and a clickable run link where present. Markers map 1:1 from the existing `HistoryEntry.kind` strings — no derived/synthetic kinds:
  - `fixed` → ✓ · `stuck` → ⚠ · `gaveUp` → ⚠ · `error` → ⚠ · `deferred` → ⏸ · `↗` appended when `runURL` is present.

## Hold / Release from the UI

Currently CLI-only. Expose in the detail action row, reusing `LeaseStore` (same path the CLI uses) at `ConfigStore.defaultRoot`.

- **Hold target = the active/last branch.** Hold acts on `projectStates[project]?.branch`. If no branch is known yet (idle repo, no activity), the Hold button is disabled with a tooltip ("nothing to hold yet").
- **Hold** → `LeaseStore.hold(project:branch:minutes:)` with the CLI's default duration (30 min). **Release** → `LeaseStore.release(project:branch:)`.
- The button reflects current state via `LeaseStore.isHeld(project:branch:)`; held state can also surface as a small chip/indicator in the detail header.
- No new lease scope is introduced — per-branch leasing is unchanged.

## Data flow summary

1. Daemon/engine events arrive at `AppController` (unchanged transport).
2. Transition methods update `projectStates[project]` and record `HistoryEntry` (unchanged store).
3. Global derived state recomputes → menubar glyph color + summary bar.
4. `PanelView` observes `projectStates`, `projects`, `groupedHistory`, `setupIssues` and renders grid/detail.
5. Detail actions call existing `AppController`/`LeaseStore`/`stopWatching` paths.

## Error handling

- Missing dependencies → setup banner replaces grid (existing preflight feeds `setupIssues`).
- `runURL` absent → no link rendered (no broken links).
- Hold with unknown branch → action disabled, not errored.
- Lease/store write failures are best-effort (consistent with existing `try?` persistence); UI reflects last known state on next 2s reload tick.

## Testing

- **State derivation:** unit test the worst-across-projects roll-up for every combination of states.
- **Per-project transitions:** simulate `enterWatching/enterFixing/notifyAsync(.fixed/.stuck/.deferred/.error)` and assert `projectStates[project]` and the derived global state.
- **History markers:** assert `HistoryEntry.kind` → marker mapping.
- **Hold target:** assert Hold uses the active branch and is disabled when branch is nil; assert Hold/Release call `LeaseStore` with expected args (inject a `LeaseStore` over a temp root).
- **Existing tests** for `LeaseStore`, `HistoryStore`, `ConfigStore` continue to pass unchanged.
- Manual: `MenuBarExtra(.window)` renders, slide transition, empty state, setup-banner state.
