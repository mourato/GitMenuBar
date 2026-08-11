# Plan 070: Guard pull-to-refresh publication against repository switches

> **Executor instructions**: Read this plan completely before editing. Use one
> isolated worktree, preserve unrelated changes, and keep the fix limited to
> the selected-repository refresh path. Root-session review is required after
> implementation. Reconcile Plan 057's Swift 6.4 toolchain baseline before
> starting.
>
> **Drift check (run first)**: `git diff --stat 11a88dd..HEAD --
> GitMenuBar/Services/Git/GitManager.swift
> GitMenuBar/Pages/MainMenu/MainMenuContent.swift
> GitMenuBar/Pages/MainMenu/MainMenuActions.swift
> GitMenuBarTests/GitManagerRefreshTests.swift plans`

## Status

- Priority: P1
- Effort: M
- Risk: HIGH
- Depends on: Plan 057 (Swift 6.4 toolchain baseline); Plans 066–067 are DONE
- Category: correctness / concurrency / selected repository state
- Planned at: commit `11a88dd`, 2026-08-11

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: High / Full
- **Parallelizable**: Yes after Plan 057; the selected-refresh slice is
  independent of CLI and monitor-store work, but final integration is serial.
- **Reviewer required**: Yes — root-session review of MainActor/session
  admission, cancellation, and stale publication behavior.
- **Rationale**: The existing selected-refresh session/generation guard is
  already correct; pull-to-refresh bypasses it by calling the ungated public
  `refreshAsync` with `session: nil`. The smallest safe fix is to route only
  that user action through the existing selected path.
- **Escalate when**: the change requires rewriting refresh callers globally,
  changing selection ownership, or weakening the existing cancellation guard.

## Why it matters

Pull-to-refresh can start a slow refresh for repository A. If the user then
selects repository B, the selected refresh path cancels A and admits only B's
publication, but the pull-to-refresh task is still running through
`refreshAsync(session: nil)`. Its files, branch, remote, and history can arrive
after the switch and overwrite B's state.

This is a stale-publication bug, not a missing refresh. The app already has the
correct session/generation mechanism; the UI caller must use it.

## Current state

- `GitMenuBar/Pages/MainMenu/MainMenuContent.swift:160-162` uses
  `.refreshable { await gitManager.refreshAsync(includeReflogHistory: false) }`.
- `GitMenuBar/Services/Git/GitManager.swift:161-183` routes the public async
  method to the private refresh with `session: nil`; every
  `GitExecution.publishOnMainActor(ifCurrent: session)` call is therefore
  ungated.
- `GitManager.swift:199-259` already owns `refreshSelectedRepository`,
  `startSelectedRefresh`, `selectedRefreshTask`, generation incrementing, and
  session admission. Superseded tasks are cancelled and stale writes are
  rejected.
- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift:194-222` already routes
  repository switching through `refreshSelectedRepository`, so selection logic
  does not need to move into the view.
- `GitMenuBarTests/GitManagerRefreshTests.swift:10-46` proves a superseded
  selected refresh cannot publish or finish; `:48-77` proves fast completion
  ordering. There is no pull-to-refresh overlap regression.
- The public ungated `refreshAsync` has other callers for mutation/background
  refresh behavior. Do not replace all callers without tracing their ownership
  and intentional semantics.

## Commands and evidence

| Check | Command | Expected result |
|---|---|---|
| Caller audit | `rg -n 'refreshAsync\(|refreshSelectedRepository' GitMenuBar GitMenuBarTests` | Only the selected UI pull path changes to the gated API |
| Focused tests | `make test TEST_FILTER=GitManagerRefreshTests` | Overlap regression and existing ordering tests pass |
| Focused gate | `make agent-check` | Changed lint and build pass |
| UI preview gate | `make check-preview` | Changed UI candidate preview check passes or known baseline is recorded |
| Full tests/lint | `make test && make lint` | Existing behavior remains green |
| Guidance/hygiene | `make guidance-check && git diff --check` | Exit 0 |

If the Makefile does not support `TEST_FILTER`, use its documented focused-test
argument or the smallest existing `xcodebuild ... -only-testing` equivalent.

## Suggested executor toolkit

- Use `swift-concurrency`, `swiftui-expert-skill`, `macos-app-engineering`,
  `swiftui-accessibility-audit`, and `delivery-workflow` as applicable to the
  touched native UI/concurrency boundary.
- Reuse `GitRefreshSession`, `startSelectedRefresh`,
  `selectedRefreshOperation`, and `GitExecution.publishOnMainActor(ifCurrent:)`.
- Do not add a new event bus, repository manager, cache, or refresh framework.

## Scope

In scope:

- Add the smallest async bridge needed for a UI pull-to-refresh operation to
  start and await the existing selected-refresh task/session.
- Route `MainMenuContent`'s `.refreshable` call through that selected bridge,
  preserving `includeReflogHistory: false` and existing selection lifecycle.
- Keep cancellation and supersession fail-closed: a stale A task may finish
  internally, but it must not publish or complete UI state after B is current.
- Add a deterministic overlap regression using the existing
  `selectedRefreshOperation` seam.

Out of scope:

- Rewriting `refreshAsync` or changing mutation/background callers without a
  separate contract.
- Changing repository selection, fast-loading presentation, commit history,
  Git command ordering, or refresh data shape.
- Adding a new refresh coordinator or making every refresh call awaitable.

## Git workflow

Use `fix/selected-refresh-session-admission` in an isolated worktree. Use a
scoped Conventional Commit such as `fix(refresh): gate pull-to-refresh state`;
do not push, reset, or rewrite history.

## Ordered implementation steps

### 1. Audit every refresh caller

Trace all public and private `refreshAsync` callers, including mutation
completion and startup paths. Confirm which calls operate on the selected
repository and which intentionally use the current manager state without a
selection session. Record the exact UI path to change.

**Verify:** only pull-to-refresh is identified as the un-gated selected UI
caller; no sibling caller is changed by assumption.

### 2. Reuse the selected-refresh task/session

Expose a minimal `@MainActor` async entry point or return the existing selected
refresh task from the existing starter so the caller can await it. Keep task
replacement, generation incrementing, session path capture, cancellation, and
`ifCurrent` publication in one place. If a cancellation path can leave an
awaiting continuation unresolved, do not ship the bridge; use the existing task
value or a similarly completion-safe mechanism and stop for review if needed.

**Verify:** a selected async refresh resolves for normal completion and for a
superseded task without admitting stale completion callbacks.

### 3. Route the pull-to-refresh UI

Replace only the `MainMenuContent` pull-to-refresh call with the selected async
entry point, preserving the current path and reflog choice. Keep the view's
existing scroll ownership, refresh modifier, focus behavior, and accessibility
semantics unchanged.

**Verify:** source inspection shows no direct ungated selected refresh remains
in `.refreshable`; `make check-preview` covers the changed native UI candidate.

### 4. Add the overlap regression

Extend `GitManagerRefreshTests` with a delayed generation-1 operation that
starts for repository A, switch to B, and complete B with distinct state. Let A
attempt a late publication and assert that B's state remains. Also assert that
the awaiting pull-refresh task terminates and that existing fast/final
completion ordering still passes.

**Verify:** the regression fails when `.refreshable` uses the ungated method and
passes when it uses the selected session path; tests contain no sleeps or real
Git/network operations.

### 5. Validate the handoff

Run the Commands and evidence table, inspect the diff for accidental changes to
ungated callers, and obtain the required root-session review. Update this plan
and the ledger only after focused/full gates pass.

**Verify:** the diff is limited to `GitManager`, the main-menu content, and
focused refresh tests unless a compiler-required companion edit is documented.

## Test plan

- Pull-refresh A superseded by selection of B: A cannot publish files, branch,
  remote, history, or completion state.
- Normal selected refresh still reaches completion.
- Fast completion remains before final completion and preserves detail state.
- Existing non-selected mutation/background refresh callers retain their current
  behavior.
- `make agent-check`, `make check-preview`, `make test`, `make lint`,
  `make guidance-check`, and `git diff --check`.

## Done criteria

- Pull-to-refresh is admitted through the selected repository's existing
  session/generation guard.
- A stale refresh cannot overwrite the newly selected repository or signal its
  completion as current.
- Existing refresh and selection semantics remain unchanged outside this UI
  path.
- Deterministic overlap coverage and all required native UI/concurrency gates
  pass; root review accepts the lifecycle.

## STOP conditions

- The fix requires changing all `refreshAsync` callers or selection ownership.
- A continuation/task bridge can hang on supersession or cancellation.
- A test needs sleeps, network, real Git repositories, or timing luck.
- The change weakens `GitExecution.publishOnMainActor(ifCurrent:)` or bypasses
  the selected generation/session.
- The UI change alters locked design/accessibility decisions; record and route a
  separate UI decision instead of hiding it in this correctness fix.

## Maintenance notes

Any new selected-repository UI refresh must use the session-aware API. Keep the
ungated refresh API only for callers whose ownership is intentionally broader
than the current selected session, and add a race test when that boundary is
introduced.
