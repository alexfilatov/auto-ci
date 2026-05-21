# Auto-CI Local Fixer — Design

**Date:** 2026-05-21
**Status:** Approved design, pre-implementation

## Summary

A native macOS menubar app that watches GitHub Actions for registered local
repositories and, when a CI job fails, automatically generates and pushes a fix
using local Claude Code (headless). It is **local-first**: no server, no cloud,
nothing public-facing. The fixing brain is Claude Code running inside a
per-project clone, so it inherits the project's own context (`CLAUDE.md`,
config, tooling). It is **language-agnostic by construction** — there are no
per-language fixers; the agent reasons about the failure like a developer.

This is the first sub-project of a larger ambition (AI pipeline builder,
enterprise fix-failing-pipeline, observability layer). Those are explicitly out
of scope here and will each get their own design cycle.

## Goals

- Detect when a CI run for a locally-pushed commit fails.
- Automatically produce a fix and get the branch back to green with minimal
  human involvement.
- Never touch the user's live working tree.
- Get sharper on a specific project over time (memory of past fixes).
- Work for any language/stack.

## Non-goals (v1)

- Auto-generating CI pipelines for new projects.
- Cloud/CI-side execution or running when the laptop is off.
- Cross-platform (macOS only for v1).
- Fixing failures from teammates' or scheduled runs (only fixes runs triggered
  by the local user's pushes).

## Key decisions

| Decision | Choice |
|---|---|
| Where the agent runs | Local-first; drives local Claude Code |
| Failure detection | `pre-push` hook → daemon polls runs by head-SHA |
| Where fixes land | Commit straight onto the failing branch |
| Protected branches | Configurable (default `master`/`main`); never pushed to directly — fall back to fix branch + draft PR |
| Retry behavior | Iterate up to 3 attempts; stop early on repeated failure signature ("stuck") and notify |
| Workspace | One dedicated clone per project under `~/.auto-ci/repos/<project>` |
| Context fed to agent | Logs + failed job/step + workflow YAML + commit diff + changed files + memory of past fixes |
| Interface | macOS menubar app (Swift) that also hosts the daemon |
| Hook installation | Chain, never overwrite an existing `pre-push` |

## Architecture

A single native macOS **menubar app (Swift)** hosting a long-running **daemon**.
It orchestrates three external CLIs as subprocesses:

- `git` — clone/fetch/checkout/commit/push
- `gh` — GitHub auth, run status, logs, PR creation
- `claude` — Claude Code headless, the fixing brain

```
┌─────────────────────────────────────────────┐
│  Menubar app (Swift)                          │
│  ┌─────────────┐   ┌──────────────────────┐  │
│  │ Menubar UI  │◄──┤  Daemon (orchestrator)│  │
│  │ status/notif│   └───────┬──────────────┘  │
│  └─────────────┘           │                  │
│         subprocess calls ──┼──────────────┐   │
└────────────────────────────┼──────────────┼───┘
                  git ◄───────┘   gh ◄───┐   └──► claude (headless)
                  (clone in              │
                   ~/.auto-ci/repos)   GitHub API
                                       (runs, logs)
```

State and clones live under `~/.auto-ci/`.

## Lifecycle (per registered project)

```
  git push  ──fires──►  pre-push hook  ──pings──►  daemon
                                                     │
                                          poll THIS run's status
                                                     │
                              ┌──────── green? ──────┴───── failed?
                              │                              │
                            stop                   prepare clone in ~/.auto-ci/repos
                                                   (fetch, checkout failed commit)
                                                              │
                                                   gather context (logs + job/step
                                                   + workflow YAML + commit diff
                                                   + past-fix memory)
                                                              │
                                                   run claude headless in clone
                                                              │
                                              protected branch?  ──yes──► fix branch + draft PR
                                                              │ no
                                                   commit onto same branch, push
                                                              │
                                                   poll re-run ──green?──► record fix → notify ✓ → stop
                                                              │ still red
                                                   same failure signature twice?
                                                       │yes              │no, attempts<3
                                                   notify "stuck"      iterate
                                                       stop
```

The daemon is idle until a push fires the hook. It polls only while a run is in
flight, and returns to sleep when the run is green or otherwise resolved.

### SHA as the join key

The `pre-push` hook cannot provide a CI run ID — at push time GitHub has not yet
created the run. The hook provides the **commit SHA** being pushed; the daemon
polls the GitHub Actions API for runs matching that head SHA
(`gh run list --commit <sha>` / `head_sha` filter). The SHA is the join between
"the user pushed" and "this run failed."

## Components

| Component | Responsibility | Depends on |
|---|---|---|
| **MenubarUI** | Status icon, run list, notifications, "Add project" | Daemon (in-process) |
| **Daemon** | Owns the lifecycle state machine per project | everything below |
| **HookInstaller** | Chain-install/uninstall `pre-push`, register project | `git` |
| **PushListener** | Local socket the hook pings (SHA + branch + remote) | — |
| **RunWatcher** | Poll GitHub for runs by head-SHA, track status until terminal | `gh` |
| **ContextBuilder** | Assemble logs + failed job/step + workflow YAML + commit diff + past-fix memory | `gh`, `git`, FixMemory |
| **ClonePool** | Maintain one clone per project, fetch/checkout failed commit | `git` |
| **FixRunner** | Invoke Claude Code headless in the clone, capture result | `claude` |
| **Publisher** | Commit+push to branch, or fix-branch+draft-PR for protected branches | `git`, `gh` |
| **FixMemory** | Per-project store: failure signature → attempted fix → outcome | local file/db |

Each unit is independently testable through a narrow interface
(e.g. `ContextBuilder` takes a run ID, returns a context bundle; `FixRunner`
takes a bundle + clone path, returns a diff/result).

## Hook installation (chain, never overwrite)

`auto-ci init` (CLI) or "Add project…" (menubar) performs a one-time per-project
setup: register the project in `~/.auto-ci/config` (path, remote URL,
protected-branch list) and install the `pre-push` hook.

If a `pre-push` hook already exists (Husky, lefthook, custom), ours installs as a
wrapper that calls through to the existing one. If the existing hook exits
non-zero, we respect that and abort the push. Uninstalling restores the original
hook.

The hook does one thing and exits 0 instantly so it never slows a push: read
git's stdin (`<local-ref> <local-sha> <remote-ref> <remote-sha>`) and ping the
daemon's local socket with branch + SHA + remote.

## The Claude invocation

`FixRunner` runs `claude` headless (`claude -p`) **inside the project's clone**,
so it inherits the repo's `CLAUDE.md`, config, and tooling. The prompt is the
context bundle:

> CI job `<job>` step `<step>` failed. Here are the logs, the workflow YAML, the
> diff of the commit that failed, the changed files, and notes from past fixes on
> this project. Diagnose and fix it. Don't touch unrelated code.

It works in the clone, so it can edit freely; the resulting git diff is captured
as the fix. Permissions are scoped to the clone directory.

## FixMemory & failure signatures

A **failure signature** is a normalized fingerprint of the failure: job name +
step + a hash of the key error lines, with volatile bits (timestamps, absolute
paths, run IDs) stripped. Used two ways:

1. **Loop detection** — same signature twice in a row → "stuck", stop and notify.
2. **Memory recall** — on a new failure, look up past fixes for a matching or
   similar signature and feed them in as hints.

Stored per-project under `~/.auto-ci/<project>/fixes.json` (migrate to SQLite if
it grows). **Raw logs are never persisted** — only the normalized signature —
to avoid storing secrets that may appear in logs.

## Error handling / edge cases

- **Push aborted / no run created** → RunWatcher times out (~2 min, no matching
  run) and gives up quietly.
- **Multiple workflows on one SHA** → watch all; trigger a fix per failed run.
- **Force-push / amend during a fix** → fix targets a specific SHA; if that SHA
  is gone from the branch, abandon and notify.
- **Clone push rejected** (branch moved) → re-fetch, rebase the fix onto the new
  tip, retry once, else fall back to fix-branch + PR.
- **`claude` makes no changes** → treat as "stuck", notify.
- **Secrets in logs** → never persist raw logs to FixMemory; store only the
  normalized signature.

## Testing strategy

- Unit-test each component against its interface with faked subprocess output
  (canned `gh`/`git` responses, recorded failure logs).
- Signature normalization: table-driven tests over real log samples to confirm
  volatile bits are stripped and equivalent failures hash equally.
- Lifecycle state machine: drive it with simulated events
  (push → run failed → fix → green / stuck / protected-branch) and assert
  transitions, attempt caps, and fallbacks.
- Hook chaining: install over a pre-existing `pre-push`, assert both run and that
  a non-zero existing hook aborts the push; assert uninstall restores the
  original.
```
