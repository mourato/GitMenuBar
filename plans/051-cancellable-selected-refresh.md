# Plan 051: Make selected-project refreshes cancellable and identity-safe

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat b2beedd..HEAD -- GitMenuBar/Services/Git/GitManager.swift GitMenuBar/Services/Git/GitRepositoryContext.swift GitMenuBar/Services/Git/GitExecution.swift GitMenuBar/Services/Git/GitBranchService+State.swift GitMenuBar/Services/Git/GitBranchService+Queries.swift GitMenuBar/Services/Git/GitCommitHistoryService.swift GitMenuBar/Pages/MainMenu/MainMenuActions.swift GitMenuBar/App/StatusBarController.swift GitMenuBarTests/GitManagerRefreshTests.swift GitMenuBarTests/GitRepositoryContextTests.swift`
> If any in-scope source file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P0
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: Plan 050
- **Category**: perf
- **Planned at**: commit `b2beedd`, 2026-08-04

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `High/Full`
- **Parallelizable**: no — repository identity, cancellation, service
  publication, and refresh completion form one concurrency contract
- **Reviewer required**: yes — this changes shared Git state and must be
  reviewed for stale results, cancellation, and mutation safety
- **Rationale**: The current manager is a selected-repository facade backed by
  a mutable context, so rapid project switching can let old asynchronous work
  publish into the new project. A small generation/path gate and one owned
  refresh task address the root race without introducing one GitManager per
  monitored project or a new global coordinator.
- **Escalate when**: the implementation requires making the whole app
  `@MainActor`, changing every Git mutation to an actor, changing the public
  GitManager API consumed by CLI/AI/branch workflows, or adding a second
  repository manager. Stop and request a narrower follow-up.

## Why this matters

`GitManager.refresh` creates an unowned `Task`, while the services read the
current path from a mutable `UserDefaults`-backed context. A slow refresh from
project A can finish after the user selects project B and publish A's files,
branch, or history into B; a second refresh can also continue consuming CPU
after it is no longer relevant. The selected-project contract in ADR 0004
requires one full GitManager owner, so the safe optimization is to cancel and
gate refresh sessions, not to instantiate one manager per project.

## Current state

- `GitMenuBar/Services/Git/GitManager.swift:108-153` resolves the repository
  path dynamically, starts a fresh `Task` for every `refresh`, and has no task
  handle or session identity:

  ```swift
  private var storedRepoPath: String {
      get { repositoryContext.repositoryPath }
      set { repositoryContext.repositoryPath = newValue }
  }

  func refresh(...) {
      Task { [weak self] in
          await self?.refreshAsync(...)
      }
  }
  ```

- `GitMenuBar/Services/Git/GitRepositoryContext.swift:15-27` reads the path
  from `UserDefaults` on every getter unless an override was supplied. This is
  convenient for the current facade but unsafe as the identity of an already
  running asynchronous read.
- `GitMenuBar/Services/Git/GitManager.swift:129-140` awaits ten operations in
  sequence. Each operation publishes partial state independently, and the
  current refresh has no cancellation checks between phases.
- `GitMenuBar/Services/Git/GitBranchService+State.swift:79-147`,
  `GitBranchService+Queries.swift:84-140`, and
  `GitCommitHistoryService.swift:83-107` capture some paths locally but publish
  without checking whether that path/session is still selected.
- `GitMenuBar/App/StatusBarController.swift:1025-1038` and the Plan 050 switch
  path are the main managed refresh entrypoints. Explicit Git mutation refresh
  calls must continue to work.
- `GitMenuBar/Services/Git/GitExecution.swift:13-23` runs synchronous Process
  work on a global queue. Cancelling the Swift `Task` does not automatically
  kill a running Process; the contract must therefore also ignore results that
  are no longer current.
- `docs/adr/0004-multi-project-monitoring-snapshots.md` requires the existing
  `GitManager` to own only the selected repository's full state. The compact
  `ProjectMonitorStore` remains separate.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Refresh-path audit | `rg -n 'Task \{|refreshAsync|publishOnMainActor|storedRepoPath|repositoryPath' GitMenuBar/Services/Git/GitManager.swift GitMenuBar/Services/Git/GitRepositoryContext.swift GitMenuBar/Services/Git/GitBranchService+State.swift GitMenuBar/Services/Git/GitBranchService+Queries.swift GitMenuBar/Services/Git/GitCommitHistoryService.swift` | every selected refresh publication has a visible path/session guard, and only one managed task owns selection refresh |
| Targeted source tests | `rg -n 'refresh|repository|generation|stale|cancel' GitMenuBarTests --glob '*.swift'` | existing and new tests identify the selected-refresh regression seam |
| Preview coverage | `make check-preview` | exit 0 |
| Scoped validation | `make agent-check` | changed Swift lint passes and the Debug build succeeds |
| Guidance validation | `make guidance-check` | exit 0 |
| Merge gate | `make lint && make test` | both commands exit 0 |

## Suggested executor toolkit

- Use the local `swift-concurrency` skill for cancellation, task ownership,
  and publication ordering.
- Use `global:macos-app-engineering` for the selected-project UI lifecycle.
- Use `test-strategy` for deterministic async tests and avoid sleep-based
  timing assertions where a controllable seam is available.
- Use `global:swift-conventions` for the final lint/format pass.

## Scope

**In scope** (the only source files to modify):

- `GitMenuBar/Services/Git/GitManager.swift`
- `GitMenuBar/Services/Git/GitRepositoryContext.swift`
- `GitMenuBar/Services/Git/GitExecution.swift`
- `GitMenuBar/Services/Git/GitBranchService+State.swift`
- `GitMenuBar/Services/Git/GitBranchService+Queries.swift`
- `GitMenuBar/Services/Git/GitCommitHistoryService.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift`
- `GitMenuBar/App/StatusBarController.swift`
- `GitMenuBarTests/GitManagerRefreshTests.swift` (create)
- `GitMenuBarTests/GitRepositoryContextTests.swift` (create only if the
  context identity contract has no existing test seam)

Plan metadata files:

- `plans/051-cancellable-selected-refresh.md`
- `plans/README.md`

**Out of scope** (do not touch):

- `GitMenuBar/Services/Git/ProjectMonitorStore.swift` and
  `ProjectStatusReader` — Plan 052 owns compact monitor performance.
- A second `GitManager` per project, a general repository service protocol,
  full Swift 6 actor isolation, or a new global refresh coordinator.
- Git mutation methods such as commit, push, pull, discard, branch checkout,
  merge, cleanup, or wipe, except for a compile-safe call-site adjustment if
  a shared refresh wrapper requires it. Do not make mutation work silently
  cancellable in this slice.
- Git command batching, branch N+1 removal, untracked-file diff strategy,
  network fetch policy, and deferred branch-detail loading — Plan 052.

## Git workflow

- Branch: `advisor/051-cancellable-selected-refresh` (or the repository's
  current branch convention if the operator already supplied an isolated
  implementation branch).
- Keep the implementation to one logical commit if committing is requested;
  use the repository's Conventional Commit style, e.g.
  `perf(git): cancel stale selected repository refreshes`.
- Do not push or open a PR unless the operator explicitly instructs it.

## Steps

### Step 1: Define one refresh-session identity

Introduce the smallest identity mechanism that can answer both questions:

1. Is this result for the currently selected normalized repository path?
2. Is it from the current refresh after the most recent selection, rather than
   an older refresh for the same path?

Prefer an integer generation plus the captured normalized path owned by the
existing `GitManager`/`GitRepositoryContext` seam. Do not introduce a
repository-wide event bus, a protocol with one implementation, or a new
per-project manager. Ensure every managed selection refresh captures its
`(path, generation)` before launching Git work.

The context/manager API must make path changes explicit for the UI selection
route. Keep the existing `repositoryPathOverride` test behavior. Direct
readers must not observe a partially changed path while a refresh session is
being created.

**Verify**:

- `rg -n 'generation|refresh.*Task|cancel\(' GitMenuBar/Services/Git/GitManager.swift GitMenuBar/Services/Git/GitRepositoryContext.swift` → the identity and task ownership exist in the existing facade/context, not in a new parallel coordinator.
- Add a deterministic test that starts two sessions for A then B and proves
  the first session is no longer current; the test must not use a fixed sleep.

### Step 2: Own and cancel the managed selection refresh Task

Store the active selection-refresh `Task` in `GitManager` (or the existing
selection owner if Plan 050 has a better live seam). Starting a new managed
refresh must cancel the previous task, increment the generation, and capture
the new path before work begins. Check `Task.isCancelled` between each
refresh phase and before invoking the completion that finishes the UI refresh.

Cancellation is an optimization and correctness aid, not a guarantee that a
already-running `Process` stops. If `GitExecution.runOnBackground` remains
Process-backed and non-cancellable, let the Process finish off the main actor
but do not publish its result or finish the newer refresh. Do not add a
blocking wait on the main actor.

Keep direct `refreshAsync` callers used by explicit Git workflows compatible;
the managed selection wrapper may own cancellation while explicit mutation
refreshes continue to await their existing API.

**Verify**:

- `rg -n 'active.*Task|refreshTask|Task\.isCancelled|\.cancel\(\)' GitMenuBar/Services/Git/GitManager.swift` → the managed path cancels and checks without blocking the main actor.
- A test starts a managed refresh, starts a second one, and verifies only the
  second session can complete the managed completion callback.

### Step 3: Gate every selected-refresh publication

For each async read used by the selected refresh, capture the repository path
and session generation at the beginning and check the gate immediately before
publishing state. Apply this to the working-tree, branch, branch-list,
remote-url, commit-history, default-branch, and branch-detail publications in
the files listed in Scope. A final check only at the end is insufficient:
partial state from an old session must not leak into the new project.

Fix helpers that currently read `storedRepoPath` again inside a background
operation after a captured path exists. The refresh path must use the captured
path consistently. Do not alter mutation methods that intentionally use the
current context; if a shared helper cannot distinguish reads from mutations,
stop and report rather than applying a broad rewrite.

When the gate rejects a result, leave the newer session's cleared/loading
state intact and do not emit an error for the obsolete session.

**Verify**:

- `rg -n 'publishOnMainActor|DispatchQueue\.main\.async' GitMenuBar/Services/Git/GitManager.swift GitMenuBar/Services/Git/GitBranchService+State.swift GitMenuBar/Services/Git/GitBranchService+Queries.swift GitMenuBar/Services/Git/GitCommitHistoryService.swift` → every selected-refresh publication has a nearby current-session check.
- Add a test using two temporary repositories and a controllable command seam
  (or the smallest existing runner seam) that proves late A data cannot appear
  after B is selected. Do not make the test depend on wall-clock scheduling.

### Step 4: Finish state only for the current session

Update the managed refresh completion path in
`StatusBarController.refreshMainWindowData(trace:)` and
`MainMenuActions.switchRepository(path:)` so `finishRefresh()` is called only
for the current session. If a session is cancelled or superseded, the newer
selection owns the loading state. Preserve shortcut flushing only after the
current session has produced its first valid selected snapshot.

Do not add a second spinner, a timer-based minimum duration, or an arbitrary
debounce. The user should see the reset/loading state immediately, as Plan 050
established.

**Verify**: manual Debug run with two repositories (one deliberately slowed by
many untracked files or history) and rapid A→B→A selection shows only the last
selection's data, no old completion hides its spinner, and no main-thread
hang. `make check-preview` and `make agent-check` exit 0.

### Step 5: Review the concurrency boundary and run gates

Run `make guidance-check`, then `make lint && make test`. Before marking the
plan done, review the diff specifically for:

- Process work never running synchronously on the main actor;
- no `UserDefaults` path read inside a selected-refresh closure after the
  captured session begins;
- no publication from a superseded generation;
- explicit fetch/mutation workflows still completing normally;
- no leaked task retaining `GitManager` after deallocation.

**Verify**: all commands exit 0; reviewer sign-off records the concurrency
boundary and the manual rapid-switch check passes.

## Test plan

- Add unit coverage for the refresh identity/generation gate and cancellation
  behavior without fixed sleeps.
- Add a temporary-repository regression for late results from one project
  being ignored after another project is selected.
- Keep existing `GitWorkingTreeStateTests`, branch operation tests, and commit
  history tests green; their public GitManager behavior must not change.
- Run `make check-preview`, `make agent-check`, and `make lint && make test`.

## Done criteria

- [ ] Only one managed selected-project refresh Task is active at a time.
- [ ] Starting a new selection cancels the previous managed refresh and
      advances its session identity.
- [ ] Late results from an old path or generation never publish into the new
      selected repository.
- [ ] The refresh completion cannot hide a newer session's loading state.
- [ ] Captured refresh paths are used consistently inside background reads.
- [ ] Explicit commit/push/pull/branch workflows remain functional.
- [ ] Focused concurrency tests are deterministic and pass.
- [ ] `make check-preview`, `make agent-check`, `make guidance-check`,
      `make lint`, and `make test` exit 0.
- [ ] Reviewer has inspected cancellation, publication, and mutation safety.
- [ ] No files outside the in-scope list are modified.
- [ ] `plans/README.md` status row for Plan 051 is updated only after done.

## STOP conditions

Stop and report instead of improvising if:

- A service publishes state without a viable path/session gate and fixing it
  requires changing its public API across unrelated callers.
- Cancelling a refresh would cancel or corrupt a Git mutation, fetch, push,
  pull, checkout, merge, cleanup, or wipe operation.
- The only apparent fix is to make the entire app actor-isolated or to create
  one GitManager per monitored project.
- A test can pass only by adding arbitrary sleeps, retries, or timing margins.
- A late result can still finish a newer UI refresh, or a superseded session
  can clear data belonging to the new path.
- `make agent-check`, `make check-preview`, or the final lint/test gate fails
  twice after a reasonable scoped correction.

## Maintenance notes

- The refresh gate is for read-side selected-project snapshots. Keep Git
  mutations serialized by their existing operation paths and do not broaden
  cancellation casually.
- `GitExecution.runOnBackground` may still let a cancelled Process finish;
  correctness comes from ignoring its result. A future Process cancellation
  optimization needs its own measured plan and must handle askpass cleanup.
- Plan 052 can reduce the number of commands in a valid refresh after this
  identity contract is stable. It must not bypass the gate when it batches or
  parallels local reads.
