# Auto-CI

A macOS menubar app + CLI that watches GitHub Actions for your locally-pushed commits and automatically fixes failing CI using headless Claude Code — no manual intervention needed for common errors.

It's **local-first**: no server, no cloud, nothing public-facing. The fixing brain is `claude` running inside a per-project clone, so it inherits your project's own context (`CLAUDE.md`, config, tooling). It's **language-agnostic by construction** — there are no per-language fixers; the agent reasons about the failure like a developer would.

## What it does

When you `git push`, Auto-CI:

1. Receives the push event via a Unix socket (written by a chain-installed `git pre-push` hook).
2. Polls GitHub Actions until the workflow runs for that commit reach a terminal state.
3. For every failed run, downloads the failure logs, assembles context (logs + workflow YAML + commit diff + changed files + past-fix memory), and invokes `claude` headless in a dedicated per-project clone.
4. Commits the fix and pushes it back to the same branch — or, if the branch is protected (`main`/`master`), opens a draft PR from an `auto-ci/fix-<branch>-<runId>` branch.
5. Re-polls CI **on the fix commit's SHA**. If still red with a *different* failure signature, it retries (up to 3 attempts). If the *same* signature reappears it stops and notifies you ("stuck"). If it exhausts attempts it notifies "gave up".
6. Posts a macOS notification and updates the menubar glyph color for every outcome.

### It won't cheat your tests

A naive auto-fixer will happily make CI green by *weakening the test that caught the bug*. Auto-CI guards against this:

- The fix prompt explicitly forbids modifying, weakening, deleting, or skipping tests.
- A `TestEditGuard` inspects the resulting diff. If the fix touched test files (configurable via `testPathPatterns`, default on), it discards the change, re-prompts once with a stern correction to fix the *source* instead, and refuses the fix entirely if it still insists on editing tests.

### It stays out of your way (auto-ci is a *secondary* fixer)

If you (or your own interactive Claude session) are already fixing a failure, auto-ci must not race you. It yields:

1. **Grace period.** When CI fails, auto-ci waits `graceSeconds` (default 180; `0` = immediate) before touching anything, showing *"CI failed — waiting Ns to see if it's handled…"*.
2. **Activity detection.** During that window, if the branch advances (someone pushed a fix) or a hold is active, auto-ci **stands down** — it never clones, runs Claude, or pushes. The outcome is logged as ⏸ *Deferred*.
3. **Explicit hold.** Claim a branch deterministically so auto-ci won't touch it:
   ```bash
   auto-ci hold       # "I'm fixing this — back off" (default 30 min, auto-expires)
   auto-ci release    # resume
   ```
   Tell your interactive Claude (or your repo's `CLAUDE.md`) to `auto-ci hold` before fixing and `auto-ci release` after.
4. **Push referee.** If two fixes still collide, the non-force push that arrives second is rejected by git, so nothing is silently overwritten.

Priority order: **your session (primary) → explicit `hold` → grace-period detection → git push referee.** auto-ci only fixes when the field is clear.

## Install

Auto-CI isn't on the App Store. Install it with one line — **no Xcode required**. This downloads the prebuilt universal (Apple Silicon + Intel) release, installs `AutoCI.app` to `/Applications` and the `auto-ci` CLI to your `PATH`, and launches it:

```bash
curl -fsSL https://raw.githubusercontent.com/alexfilatov/auto-ci/main/install.sh | bash
```

The installer strips the Gatekeeper quarantine flag so the app opens without a warning. If no prebuilt release is available, it automatically falls back to building from source (which then needs Xcode/Swift).

> Releases are signed ad-hoc today. When built with a Developer ID + notary profile, `scripts/release.sh` automatically signs and notarizes the app so it opens with no Gatekeeper prompt at all — see the script header for the one-time setup.

Then run `auto-ci doctor` to confirm `gh`/`claude` are ready, and `auto-ci init` inside any repo you want watched.

## Requirements

- macOS 14+
- Swift 6.2 / Xcode 26+ (to build)
- `git` (ships with Xcode Command Line Tools)
- `gh` CLI, authenticated (`gh auth login`)
- `claude` CLI, installed and authenticated

Run `auto-ci doctor` to check all of the above at once (see below). The menubar app also runs this preflight on launch and shows a "Setup required" state listing anything missing.

## Build

### The CLI

```bash
swift build -c release
```

The `auto-ci` binary lands in `.build/release/`. Optionally copy it onto your `PATH`.

### The menubar app

```bash
./scripts/build-app.sh
```

This produces `AutoCI.app` — a proper menubar agent bundle (`LSUIElement`, ad-hoc signed) with `git`/`gh`/`claude` paths baked into `LSEnvironment`. **Building a bundle is required** because macOS notifications need a bundle identifier and GUI apps launched from Finder don't inherit your shell `PATH`. Launch it with:

```bash
open ./AutoCI.app
```

For a rock-solid setup, copy `AutoCI.app` into `/Applications` first (login-item launches reference the app's path).

## CLI

```bash
auto-ci help                  # show all commands
auto-ci doctor                # check git / gh / claude are installed and authenticated
auto-ci init                  # register the current repo + chain-install the pre-push hook
auto-ci list                  # list registered projects
auto-ci fix [--sha] [--branch]# manually run the full fix pipeline once (defaults to HEAD)
auto-ci hold [--minutes N]    # claim the current branch so auto-ci won't auto-fix it
auto-ci release               # release the hold
auto-ci uninstall [--purge]   # remove the hook + unregister (--purge also deletes clone, memory, history)
```

### Hook installation is safe and non-invasive

- **Chained, never overwritten.** If a `pre-push` hook already exists (Husky, lefthook, custom), it's backed up to `pre-push.auto-ci-orig` and called from ours, so nothing is lost. If it exits non-zero, the push aborts.
- **`core.hooksPath` aware.** If the repo uses a custom hooks dir (Husky v9, lefthook, a tracked `.githooks/`), auto-ci installs there instead of `.git/hooks` so the hook actually fires — and warns when that dir is tracked (visible to git).
- **Never committed.** Hooks live outside the tracked tree, so they're never pushed and teammates never receive them.
- **Uninstall never destroys your work.** If you edited the managed hook, your version is saved to `pre-push.auto-ci-modified.<timestamp>`; if you replaced it entirely, it's left untouched; otherwise the original is restored.

## The menubar app

The Auto-CI glyph lives in your menu bar — a single custom vector mark (a CI loop arrow around an auto-fix spark) whose **shape never changes**, only its color. Idle renders as a template image (auto-tinted to match light/dark menu bars, always visible); active states use color: **blue** watching, **orange** fixing, **green** fixed, **red** needs-you.

Clicking it shows a header with a colored status dot — 🔵 watching · 🟠 fixing · 🟢 fixed · 🔴 needs you · ⚪️ idle — and:

- While watching/fixing, a **"View workflow run ↗"** link to the exact GitHub Actions run.
- **Projects** — each watched repo, with a **Stop watching** action (uninstall without the CLI).
- **Recent** — persistent fix history (`~/.auto-ci/history.json`, survives restarts), **grouped by repository**; each entry links to its run (✓ fixed, ⏸ deferred, ⚠ needs attention). Includes **Clear History**.
- **Settings…** — a per-project preferences window: grace period, protect-tests, protected branches, test path patterns.
- **Start at Login** — toggles a login item via `SMAppService`. Auto-CI registers itself once on first launch so a fresh install starts at boot; toggle off any time.
- **About** — opens a native About popup.
- **Quit**.

## How it works in detail

```
git push
  └─ pre-push hook fires
       └─ writes JSON payload to Unix socket at ~/.auto-ci/daemon.sock
            └─ PushListener (in AutoCIApp) receives the event
                 └─ RunWatcher polls `gh run list --commit <sha>`
                      └─ when all runs are terminal:
                           ├─ green: notifies "nothing to do"
                           └─ red:  GraceGate.evaluate (wait graceSeconds, watch for
                                    branch-advance / active hold)
                                     ├─ deferred: stand down (⏸), notify, STOP
                                     └─ proceed: Daemon loop (up to maxAttempts=3)
                                └─ LiveFixEngine:
                                     1. ClonePool: clone or fetch ~/.auto-ci/repos/<project>, checkout sha
                                     2. ContextBuilder: fetch failure logs (gh run view --log-failed),
                                        git show for commit diff, git diff-tree for changed files,
                                        FixMemory for past fixes on the same failure signature
                                     3. FixRunner: build prompt, pipe it to claude on stdin, capture diff;
                                        TestEditGuard rejects/retries fixes that touch test files
                                     4. Publisher:
                                          non-protected branch → add/commit/push to same branch
                                          protected branch     → checkout auto-ci/fix-<branch>-<runId>,
                                                                  push, open draft PR via gh pr create
                                          (returns the fix commit SHA)
                                     5. Daemon re-polls CI on the FIX commit SHA; if green → records
                                        success in FixMemory, notifies "fixed"; if same failure signature
                                        reappears → "stuck"; if maxAttempts exhausted → "gaveUp"
```

## Protected-branch behavior

If you push directly to `main` or `master` (the default protected list), Auto-CI never pushes a fix commit to that branch. Instead it creates an `auto-ci/fix-<branch>-<runId>` branch in the clone, pushes it, and opens a draft PR targeting the protected branch. Extend the protected list per project via `protectedBranches` in `~/.auto-ci/config.json`.

## Configuration

Per-project settings (edit in the **Settings…** window or directly in `~/.auto-ci/config.json`):

- `graceSeconds` — how long to wait before auto-fixing, so you/another agent can take it first (default `180`; `0` = immediate).
- `protectedBranches` — branches that get the fix-branch + PR treatment instead of a direct push (default `["main", "master"]`).
- `protectTests` — refuse fixes that weaken tests (default `true`).
- `testPathPatterns` — path substrings treated as test files (default `["tests/", "_test", ".test.", "spec", "/test"]`).

State under `~/.auto-ci/`:

- `config.json` — registered projects.
- `daemon.sock` — Unix socket the hook pings.
- `holds.json` — active `hold` leases.
- `repos/<project>/` — the dedicated clone per project.
- `projects/<project>/fixes.json` — per-project fix memory (failure signature + outcome only — **raw logs are never persisted**).
- `history.json` — menubar Recent history.

## Known limitations

- **Push-rejection retry not implemented.** If the fix push is rejected because the branch moved, Auto-CI surfaces an error rather than rebasing the fix onto the new tip and retrying.
- **Signature granularity.** The failure signature uses the workflow run name for both the "job" and "step" fields, since the run-level API doesn't expose per-step names without extra calls.
- **`claude` auth can't be prechecked.** `auto-ci doctor` confirms `claude` is installed but cannot verify it's logged in without an interactive/networked call.

## Architecture

All orchestration logic lives in the `AutoCICore` Swift package target and is fully unit-tested via `swift test`. Every external process (`git`, `gh`, `claude`) runs through an injectable `CommandRunner` protocol; tests use a deterministic `FakeCommandRunner`. The `auto-ci` CLI and `AutoCIApp` menubar app are thin shells over `AutoCICore`.

```
AutoCICore/
  CommandRunner     protocol + ProcessCommandRunner
  Models            PushEvent, WorkflowRun, RunStatus, FixContext, FixRecord, ProjectConfig, AppError
  ConfigStore       ~/.auto-ci/config.json registry
  DependencyChecker preflight for git / gh (+auth) / claude
  GitClient         git operations (incl. remoteSHA via ls-remote)
  GitHubClient      gh CLI wrapper (runs by head-sha, logs, draft PRs)
  HookInstaller     chain-install / uninstall pre-push; honors core.hooksPath
  ClonePool         dedicated clone per project under ~/.auto-ci/repos
  SignatureBuilder  normalise logs -> stable FailureSignature hash
  FixMemory         per-project fixes.json (signature + outcome, never raw logs)
  ContextBuilder    assemble FixContext from a failed run
  FixRunner         invoke claude headless (prompt via stdin), capture diff
  TestEditGuard     detect fixes that touch test files
  Publisher         commit+push or fix-branch+PR; returns the fix commit SHA
  RunWatcher        poll runs by head-sha until terminal
  LeaseStore        hold/release leases (~/.auto-ci/holds.json)
  GraceGate         defer to a human/other agent (grace period + branch-advance + holds)
  Daemon            lifecycle state machine (maxAttempts, stuck detection)
  LiveFixEngine     wires real components into the FixEngine protocol
  HistoryStore      persistent, per-repo-grouped fix history
  PushListener      Unix domain socket server
  CLICommand        testable CLI logic (help/doctor/init/list/fix/hold/release/uninstall)
```

## Development

```bash
swift test        # run the full unit suite
swift build       # build the library + CLI
```
