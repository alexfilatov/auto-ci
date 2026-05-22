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

## Install

Auto-CI isn't on the App Store — install it from source with one line (clones, builds, installs `AutoCI.app` to `/Applications` and the `auto-ci` CLI to `/usr/local/bin`, then launches it):

```bash
git clone https://github.com/alexfilatov/auto-ci.git && cd auto-ci && ./scripts/install.sh
```

Then run `auto-ci doctor` to confirm `gh`/`claude` are ready, and `auto-ci init` inside any repo you want watched. (See [Build](#build) below if you'd rather build the pieces separately.)

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
auto-ci doctor      # check git / gh / claude are installed and authenticated
auto-ci init        # register the current repo + chain-install the pre-push hook
auto-ci list        # list registered projects
auto-ci fix         # manually run the full fix pipeline once for HEAD (--sha / --branch to override)
auto-ci uninstall   # remove the hook and unregister the current repo
```

`auto-ci init` chain-installs the hook: if a `pre-push` hook already exists (Husky, lefthook, custom), it is backed up to `.git/hooks/pre-push.auto-ci-orig` and called from the new hook, so nothing is lost. If the existing hook exits non-zero, the push is aborted. `auto-ci uninstall` restores the original.

## The menubar app

The 🔧 Auto-CI glyph lives in your menu bar. It's a single custom vector mark (a CI loop arrow around an auto-fix spark) whose **shape never changes** — only its color reflects state:

| State | Color |
|-------|-------|
| Idle | gray |
| Watching a run | blue |
| Fixing a failure | orange |
| Fixed | green |
| Setup required / stuck / error | red |

Clicking the icon shows:

- The current status line and, while watching/fixing, a **"View workflow run ↗"** link to the exact GitHub Actions run.
- **Recent** — persistent fix history (saved to `~/.auto-ci/history.json`, survives restarts), **grouped by repository**. Each entry links to its run. Includes a **Clear History** action.
- **About Auto-CI**.
- **Start at Login** — toggles a login item via `SMAppService`. Auto-CI registers itself once on first launch so a fresh install starts at boot; toggle off any time. (Verify in System Settings → General → Login Items.)
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
                           └─ red:  Daemon loop (up to maxAttempts=3)
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

Per-project settings live in `~/.auto-ci/config.json`:

- `protectedBranches` — branches that get the fix-branch + PR treatment instead of a direct push (default `["main", "master"]`).
- `protectTests` — refuse fixes that weaken tests (default `true`).
- `testPathPatterns` — path substrings treated as test files (default `["tests/", "_test", ".test.", "spec", "/test"]`).

State directories under `~/.auto-ci/`:

- `config.json` — registered projects.
- `daemon.sock` — Unix socket the hook pings.
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
  GitClient         git operations
  GitHubClient      gh CLI wrapper (runs by head-sha, logs, draft PRs)
  HookInstaller     chain-install / uninstall pre-push
  ClonePool         dedicated clone per project under ~/.auto-ci/repos
  SignatureBuilder  normalise logs -> stable FailureSignature hash
  FixMemory         per-project fixes.json (signature + outcome, never raw logs)
  ContextBuilder    assemble FixContext from a failed run
  FixRunner         invoke claude headless (prompt via stdin), capture diff
  TestEditGuard     detect fixes that touch test files
  Publisher         commit+push or fix-branch+PR; returns the fix commit SHA
  RunWatcher        poll runs by head-sha until terminal
  Daemon            lifecycle state machine (maxAttempts, stuck detection)
  LiveFixEngine     wires real components into the FixEngine protocol
  HistoryStore      persistent, per-repo-grouped fix history
  PushListener      Unix domain socket server
  CLICommand        testable CLI logic (doctor / init / list / fix / uninstall)
```

## Development

```bash
swift test        # run the full unit suite
swift build       # build the library + CLI
```
