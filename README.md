# Auto-CI

A macOS menubar tool + CLI that watches GitHub Actions for your locally-pushed commits and automatically fixes failing CI using headless Claude Code — no manual intervention needed for common errors.

## What it does

When you push a branch, Auto-CI:
1. Receives the push event via a Unix socket (written by a `git pre-push` hook).
2. Polls GitHub Actions until all workflow runs for that commit reach a terminal state.
3. For every failed run, downloads the failure logs, assembles context (logs + workflow YAML + commit diff + past-fix memory), and invokes `claude --permission-mode acceptEdits` in a dedicated per-project clone.
4. Commits the fix and pushes it back to the same branch — or, if the branch is protected (`main`, `master`), opens a draft PR from an `auto-ci/fix-<branch>-<runId>` branch.
5. Re-polls CI on the fix commit. If CI is still red and the failure signature is different, it retries (up to 3 attempts). If the same signature reappears it stops and notifies you ("stuck"). If it exhausts all attempts it notifies "gave up".
6. Posts a macOS notification and updates the menubar icon for every outcome.

## Requirements

- macOS 14+
- Swift 6.2 / Xcode 26+
- `gh` CLI authenticated (`gh auth login`)
- `claude` CLI installed and authenticated

## Build

```bash
swift build -c release
```

Binaries land in `.build/release/`:
- `auto-ci` — the CLI
- `AutoCIApp` — the menubar app

## Set up a project

Inside any git repository you want watched:

```bash
auto-ci init
```

This registers the current directory with Auto-CI and chain-installs a `pre-push` hook. If a hook already exists it is backed up to `.git/hooks/pre-push.auto-ci-orig` and called from the new hook, so nothing is lost.

To remove:

```bash
auto-ci uninstall
```

To list all registered projects:

```bash
auto-ci list
```

## Launch the menubar app

```bash
open .build/release/AutoCIApp
```

Or add it to Login Items so it runs at startup. The app shows a wrench icon in the menu bar. Click it to see the last 10 events and a Quit button.

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
                                     3. FixRunner: build prompt, invoke claude headless, capture diff
                                     4. Publisher:
                                          non-protected branch → add/commit/push to same branch
                                          protected branch     → checkout auto-ci/fix-<branch>-<runId>,
                                                                  push, open draft PR via gh pr create
                                     5. Daemon re-polls CI; if green → records success in FixMemory,
                                        notifies "fixed"; if same failure signature reappears → "stuck";
                                        if maxAttempts exhausted → "gaveUp"
```

## Protected-branch behavior

If you push directly to `main` or `master` (the default protected list), Auto-CI will never push a fix commit to that branch. Instead it:
- Creates a `auto-ci/fix-main-<runId>` branch in the clone.
- Pushes that branch.
- Opens a draft PR targeting `main` with the body "Automated CI fix for run #N."

You can extend the protected list per project by editing `~/.auto-ci/config.json`.

## Known v1 limitation

After publishing a fix commit, the daemon re-polls CI using the **original push SHA's** workflow runs rather than tracking the fix commit's new SHA. In practice this means the rerun check sees the same run list as the initial failure, which is usually fine (GitHub Actions re-runs appear on the same commit URL for same-branch pushes), but for protected-branch PRs the new SHA lives on a separate branch and the check may time out. A follow-up will capture the fix commit SHA from `git rev-parse HEAD` after the push and hand it to `RunWatcher`.

## Architecture

All orchestration logic lives in the `AutoCICore` Swift package target and is fully unit-tested via `swift test`. Every external process (`git`, `gh`, `claude`) runs through an injectable `CommandRunner` protocol; tests use a deterministic `FakeCommandRunner`. The `auto-ci` CLI and `AutoCIApp` menubar app are thin shells over `AutoCICore`.

```
AutoCICore/
  CommandRunner   protocol + ProcessCommandRunner
  Models          PushEvent, WorkflowRun, RunStatus, FixContext, FixRecord, ProjectConfig, AppError
  ConfigStore     ~/.auto-ci/config.json registry
  GitClient       git operations
  GitHubClient    gh CLI wrapper
  HookInstaller   chain-install / uninstall pre-push
  ClonePool       dedicated clone per project under ~/.auto-ci/repos
  SignatureBuilder normalise logs -> stable FailureSignature hash
  FixMemory       per-project fixes.json (signature + outcome, never raw logs)
  ContextBuilder  assemble FixContext from a failed run
  FixRunner       invoke claude headless, capture diff
  Publisher       commit+push or fix-branch+PR
  RunWatcher      poll runs by head-sha until terminal
  Daemon          lifecycle state machine (maxAttempts, stuck detection)
  LiveFixEngine   wires real components into the FixEngine protocol
  PushListener    Unix domain socket server
  CLICommand      testable CLI logic (init / list / uninstall)
```
