# Plan 050: Show an immediate, single refresh state when switching projects

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat b2beedd..HEAD -- GitMenuBar/App/MainMenuPresentationModel.swift GitMenuBar/App/StatusBarController.swift GitMenuBar/Pages/MainMenu/MainMenuActions.swift GitMenuBar/Pages/MainMenu/MainMenuProjectActions.swift GitMenuBar/Pages/MainMenu/MainMenuContent.swift GitMenuBar/Services/Git/GitManager.swift`
> If any in-scope source file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P0
- **Effort**: M
- **Risk**: MED
- **Depends on**: Plan 049 is recommended but not technically required
- **Category**: perf
- **Planned at**: commit `b2beedd`, 2026-08-04

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: no — selection state, refresh state, and window-open
  orchestration must be changed as one flow
- **Reviewer required**: no — this slice changes presentation state and removes
  duplicate work, but does not yet introduce cancellation or cross-repository
  concurrency; escalate if that boundary changes
- **Rationale**: The fix is a contained state-flow correction: clear stale
  selected-repository data, start one visible refresh, and remove the known
  duplicate working-tree query. It prepares the seam that Plan 051 will make
  generation-safe.
- **Escalate when**: implementing this requires changing Git command parsing,
  adding a new coordinator/actor, changing mutation semantics, or solving
  stale results from overlapping refreshes; those belong to Plan 051.

## Why this matters

Project switching currently changes the displayed path but does not enter the
same visible refresh state used when opening the window. Old files/history can
therefore remain visible while a long refresh runs, and the window-open path
executes `updateUncommittedFiles` once before `refresh`, even though `refresh`
starts with the same operation again. This plan makes the first paint honest
and removes that duplicate process group; it does not claim to cancel an old
refresh yet.

## Current state

- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift:184-193` switches the path,
  adds it to recents, and immediately calls `gitManager.refresh`:

  ```swift
  func switchRepository(path: String) {
      if !gitManager.isGitRepository(at: path), githubAuthManager.isAuthenticated {
          presentationModel.showCreateRepo(path: path)
          return
      }

      setCurrentRepositoryPath(path)
      addToRecents(path)
      gitManager.refresh(includeReflogHistory: false)
  }
  ```

  It does not call `presentationModel.startRefresh()` or clear selected data.
- `GitMenuBar/Pages/MainMenu/MainMenuProjectActions.swift:44-47` only writes
  UserDefaults and the local `currentRepositoryPath` state.
- `GitMenuBar/App/StatusBarController.swift:1025-1038` currently does two
  working-tree refreshes on window open:

  ```swift
  presentationModel.startRefresh()
  gitManager.updateUncommittedFiles { [weak self] in
      self?.gitManager.refresh {
          self?.presentationModel.finishRefresh()
      }
  }
  ```

  `GitManager.refreshAsync` also begins with
  `updateUncommittedFilesAsync()` at `GitManager.swift:129-140`.
- `GitMenuBar/App/StatusBarController.swift:124-130` calls
  `gitManager.updateUncommittedFiles()` during controller initialization,
  while `GitManager.init` at `GitManager.swift:79-84` starts the same initial
  operation. Keep only one owner for this bootstrap work.
- `GitMenuBar/Pages/MainMenu/MainMenuContent.swift:42-44` shows the loading
  view only when refreshing and there are no working-tree changes. If old
  `stagedFiles`/`changedFiles` survive a project switch, the spinner can be
  hidden by stale content.
- `GitMenuBar/App/MainMenuPresentationModel.swift:45-61` already owns the
  `idle`/`refreshing`/`failed` state; reuse it instead of adding another
  loading flag.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Refresh call-site audit | `rg -n 'updateUncommittedFiles|refresh\(' GitMenuBar/App/StatusBarController.swift GitMenuBar/Pages/MainMenu GitMenuBar/Services/Git/GitManager.swift` | the window-open path has one managed refresh entrypoint, and no nested duplicate working-tree preflight remains |
| State-flow tests | `make test` | XCTest suite passes, including the focused presentation/reset tests |
| Preview coverage | `make check-preview` | exit 0 |
| Scoped validation | `make agent-check` | changed Swift lint passes and the Debug build succeeds |
| Guidance validation | `make guidance-check` | exit 0 |
| Merge gate | `make lint && make test` | both commands exit 0 |

## Suggested executor toolkit

- Use `global:macos-app-engineering` plus
  `.agents/overlays/macos-app-engineering.md` for main-window lifecycle and
  presentation timing.
- Use `global:swiftui-expert-skill` for the loading-state invalidation.
- Use `global:swift-conventions` and `test-strategy` for the focused state
  tests.

## Scope

**In scope** (the only source files to modify):

- `GitMenuBar/App/MainMenuPresentationModel.swift`
- `GitMenuBar/App/StatusBarController.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuProjectActions.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuContent.swift`
- `GitMenuBar/Services/Git/GitManager.swift`
- `GitMenuBarTests/MainMenuPresentationModelTests.swift`
- `GitMenuBarTests/GitManagerRefreshStateTests.swift` (create if needed)

Plan metadata files:

- `plans/050-single-project-refresh-entrypoint.md`
- `plans/README.md`

**Out of scope** (do not touch):

- `GitMenuBar/Services/Git/GitRepositoryContext.swift` and branch/history
  service internals — path identity and stale-result cancellation are Plan 051.
- `GitMenuBar/Services/Git/ProjectMonitorStore.swift` — monitor query cost is
  Plan 052; keep its existing independent snapshot contract.
- Git command arguments, porcelain parsers, branch N+1 queries, remote fetch
  policy, GitHub visibility validation, and network caching.
- A new refresh coordinator, actor, global event bus, or persistence key.

## Git workflow

- Branch: `advisor/050-single-project-refresh-entrypoint` (or the repository's
  current branch convention if the operator already supplied an isolated
  implementation branch).
- Keep the implementation to one logical commit if committing is requested;
  use the repository's Conventional Commit style, e.g.
  `perf(ui): avoid duplicate project refresh work`.
- Do not push or open a PR unless the operator explicitly instructs it.

## Steps

### Step 1: Add one selected-repository reset operation

Add the smallest method on `GitManager` that clears the data displayed for the
currently selected repository in one operation. It must clear working-tree
files, commit history, branch/hash/remote state, ahead/behind counters,
available branch rows, branch details, worktree snapshot, visibility, and
commit count. Preserve the configured repository path, commit-history page
limit, service wiring, and authentication providers. Do not reset unrelated
commit/mutation flags unless the live state flow proves they are also owned by
the selected repository.

Call this reset synchronously when `switchRepository(path:)` accepts a new
Git repository, before the new refresh starts. Keep the existing create-repo
route for non-Git folders. The reset must cause `MainMenuRenderSnapshot` to
stop producing rows from the previous repository, so the existing loading
state can appear immediately.

**Verify**: add focused assertions in
`GitMenuBarTests/GitManagerRefreshStateTests.swift` (or the closest existing
GitManager state test) that seeded staged files, changed files, history,
branches, and remote flags are empty/default after the reset while the
repository path is unchanged. `make test` passes.

### Step 2: Make project selection enter the existing refresh state

Update `switchRepository(path:)` so the accepted selection follows this order:

1. dismiss transient project/branch overlays if they are open;
2. start `presentationModel`'s existing refresh state;
3. clear the previous selected-repository state;
4. persist/update the selected path and recents;
5. invoke the managed Git refresh exactly once.

Do not add an animation, delay, sleep, or placeholder repository data. If the
selected path is already current, preserve the existing behavior unless a
test demonstrates that a no-op click should avoid refresh work; do not silently
change refresh semantics in this slice.

Finish the refresh state from the managed refresh completion. If the existing
refresh API has no failure channel, keep the current success/idle behavior and
leave failure reporting to the later refresh-session plan; do not invent an
error policy here.

**Verify**: `rg -n 'startRefresh|clear.*Repository|gitManager\.refresh' GitMenuBar/Pages/MainMenu/MainMenuActions.swift GitMenuBar/Services/Git/GitManager.swift` → the switch path starts the existing state, clears selected data, and has one refresh call. Run the focused state tests and `make check-preview` → exit 0.

### Step 3: Remove the known duplicate working-tree refresh

Simplify `StatusBarController.refreshMainWindowData(trace:)` to start the
existing presentation refresh and call the single managed `gitManager.refresh`
entrypoint. Its completion should finish the presentation refresh, flush
queued shortcuts, and log completion exactly once. Remove the preceding
`gitManager.updateUncommittedFiles` callback chain.

Remove the redundant `gitManager.updateUncommittedFiles()` from
`StatusBarController.init` because `GitManager.init` already starts the
bootstrap call in the current design. Do not remove the initial monitor seed,
status-item badge observation, or any explicit refresh after a Git mutation.

**Verify**:

- `rg -n 'gitManager\.updateUncommittedFiles' GitMenuBar/App/StatusBarController.swift` → no match remains in the initializer or window-open method.
- `rg -n 'refreshMainWindowData|gitManager\.refresh' GitMenuBar/App/StatusBarController.swift` → one refresh call remains in the window-open path, with one completion.
- `make agent-check` → exit 0.

### Step 4: Validate first paint and regressions

Run `make guidance-check`, then `make lint && make test`. In the Debug app,
switch between two monitored repositories with and without changes. The old
project's file/history rows must disappear immediately, a refresh indicator
must be visible while the new data is loading, and the new project's rows must
appear after completion. Open the window from the status item as a separate
check; it must not execute two visible working-tree refreshes.

Do not use this plan to judge rapid A→B→A switching. Plan 051 owns cancellation
and stale-result safety; if it is observed here, record it and stop at the
boundary instead of adding an ad-hoc guard.

**Verify**: all commands exit 0 and the manual flow shows one refresh state per
selection, no stale rows after the synchronous reset, and no duplicate
working-tree work on window open.

## Test plan

- Add focused state coverage for `GitManager`'s selected-repository reset:
  staged/unstaged files, history, branch/hash, remote flags, branch lists,
  and worktree state clear; the configured path remains intact.
- Extend `MainMenuPresentationModelTests.swift` only if a refresh-state
  transition is not already covered; use its existing XCTest style.
- No Git porcelain or integration test is required in this plan; command
  reduction and repository identity are explicitly deferred to Plans 051–052.
- Run `make check-preview`, `make agent-check`, and the final lint/test gate.

## Done criteria

- [ ] A project switch clears old selected-repository rows synchronously.
- [ ] A project switch enters the existing `RefreshState.refreshing` state.
- [ ] The accepted switch path invokes one managed Git refresh.
- [ ] The window-open path no longer pre-runs `updateUncommittedFiles` before
      calling `refresh`.
- [ ] The redundant initializer call is removed without changing monitor
      seeding or explicit mutation refreshes.
- [ ] Focused state tests cover the reset behavior and pass.
- [ ] `make check-preview`, `make agent-check`, `make guidance-check`,
      `make lint`, and `make test` exit 0.
- [ ] No files outside the in-scope list are modified.
- [ ] `plans/README.md` status row for Plan 050 is updated only after done.

## STOP conditions

Stop and report instead of improvising if:

- The live `GitManager` state list differs enough that clearing it could erase
  a mutation in progress or data belonging to a non-selected workflow.
- A refresh completion can arrive after a later selection and the executor
  needs a generation/token guard to prevent stale data; record it for Plan 051
  rather than adding an unreviewed concurrency mechanism here.
- Removing the duplicate call breaks status-item badge updates, explicit
  mutation refreshes, or shortcut readiness.
- The loading state requires changing the AppKit window lifecycle or adding a
  second presentation model.
- Any change needs `GitRepositoryContext`, Git command arguments, monitor
  scheduling, or network policy.
- `make agent-check`, `make check-preview`, or the final lint/test gate fails
  twice after a reasonable scoped correction.

## Maintenance notes

- `GitManager` remains the owner of the selected repository's full working
  state; `ProjectMonitorStore` remains the owner of compact attention
  snapshots, as required by ADR 0004.
- The reset intentionally trades a brief empty/loading state for truthful
  project identity. Do not preserve old rows merely to avoid the spinner.
- Plan 051 must build on this single-entrypoint flow to cancel obsolete work
  and reject stale results; do not reintroduce a second switch-specific
  refresh path.
