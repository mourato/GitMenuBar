# Plan 060: Add global monitored-project cleanup

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If a
> STOP condition occurs, stop and report instead of improvising. When done,
> update the status row in `plans/README.md` unless a reviewer maintains it.
>
> **Drift check (run first)**: `git diff --stat cfd5abf..HEAD -- GitMenuBar/App GitMenuBar/Components/Projects GitMenuBar/Components/Common/MainMenuHeaderView.swift GitMenuBar/Models GitMenuBar/Pages/MainMenu GitMenuBar/Services/Git/ProjectMonitorStore.swift GitMenuBarTests`
> Plan 059 must be complete before implementation. If the cleanup-unit or
> path-scoped service contract differs from Plan 059, stop and reconcile the
> plan instead of adding a second cleanup model.

## Status

- **Priority**: P0
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: [Plan 059](059-unify-cleanup-units-path-scoped-service.md)
- **Category**: direction
- **Planned at**: commit `cfd5abf`, 2026-08-07

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `High/Full`
- **Parallelizable**: `no` — global analysis, Shared Repository grouping, destructive batch execution, route state, and row selection must share one owner
- **Reviewer required**: `yes` — this is a new destructive multi-repository surface with async state, accessibility, and partial-failure behavior
- **Rationale**: The UI is contained in the existing main window, but it coordinates several repositories and must remain independent of the selected `GitManager` while preserving the project monitor's lightweight/no-fetch contract.
- **Escalate when**: the global page needs a new window/controller, automatic fetch, persistent cleanup selection, unbounded concurrency, a second `GitManager`, or mutation of a non-monitored path.

## Why this matters

Users currently open each monitored project, enter Branch Management, inspect cleanup, and repeat the workflow. This plan adds one global Project Cleanup page that scans all Monitored Projects, shows the count of safe local branches and worktrees per project, supports project-level and batch selection, and executes Clean All without making the user coordinate branch/worktree order manually.

## Current state

- `GitMenuBar/Services/Git/ProjectMonitorStore.swift:5-29` owns persisted Monitored Project access and lightweight `ProjectStatusSnapshot` values. It currently knows nothing about branches/worktrees and automatically refreshes with a maximum of two concurrent reads at lines 112-135.
- `docs/adr/0004-multi-project-monitoring-snapshots.md` keeps `GitManager` as the selected-repository full-workflow owner. Do not put full branch/worktree snapshots into `ProjectStatusSnapshot` or instantiate one `GitManager` per project.
- `GitMenuBar/App/StatusBarController.swift:61-72` owns the singleton selected `GitManager` and `ProjectMonitorStore`; `makeRootView()` injects them at lines 339-362. A new global cleanup store must be owned here and injected as an environment object.
- `GitMenuBar/App/MainMenuPresentationModel.swift:3-7` has only `.main`, `.createRepo`, and `.historyDetail` routes. `GitMenuBar/Pages/MainMenu/MainMenuContent.swift:108-115` maps those routes to content, while `GitMenuBar/Components/Common/MainMenuHeaderView.swift:5-15` maps routes to header chrome.
- `GitMenuBar/Components/Projects/ProjectsSidebarView.swift:75-85` has a Projects header and `:169-218` renders monitored project rows. The global page should be opened from this existing project surface; keep row selection, context menus, project persistence, and sidebar collapse behavior intact.
- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift:194-209` switches the selected repository without changing the route, so a global cleanup route can continue running while the user selects another project.
- Plan 059 supplies the path-scoped cleanup service, immutable Cleanup Units, Shared Repository identity, monitored-worktree protection, ordered mutation, and per-unit outcomes. Reuse it; do not reimplement Git commands in the page or store.
- The interface system in `.interface-design/system.md` requires a dense macOS workbench, existing Workbench tokens, one focal primary action, native controls, semantic color only, visible loading/empty/error states, and reduced-motion support. Existing previews use `MainMenuPreviewHarness(showsTransparentTitlebar: true)` for main-window chrome.

## Product and domain contract

The page is a dedicated `Project Cleanup` route in the existing main window with the Projects sidebar still visible. It is not a new window and it is not a sheet nested inside each project.

The page must:

1. analyze all monitored checkout paths when opened and on explicit Refresh, with at most two concurrent read operations;
2. display every Monitored Project, including zero-candidate and unavailable rows;
3. show eligible counts as “N branches” and “M worktrees”; a paired Cleanup Unit counts once in each relevant count;
4. assign Shared Repository Cleanup Units to one canonical row: the monitored main worktree when present, otherwise the first monitored path. Other rows remain visible for navigation and monitoring but show “Shared repository,” zero actionable counts, and no duplicate Clean action;
5. protect any monitored linked worktree path and show why it is unavailable;
6. provide a row Clean button, project checkboxes, Clean Selected, and Clean All. Row Clean selects that row's units and opens the same review used by batch selection. Clean All includes every resolved canonical row with units and excludes failed/unavailable/zero-candidate rows;
7. show one global review with affected project names and branch/worktree counts, then the existing extra acknowledgement when worktree directories will be removed. Never silently delete from a row button;
8. execute one Shared Repository at a time and one Cleanup Unit at a time, revalidating immediately before each operation, continuing after skips/failures, and showing every per-project/per-unit result. If the worktree is removed but branch deletion fails, show partial completion and keep the branch;
9. use only local Git state. Do not fetch, delete remote branches, or treat the lightweight Attention State as cleanup analysis;
10. continue a running batch if the user switches the selected project. Keep the global result visible until dismissed and refresh the selected `GitManager` only when its current repository was affected.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Drift | `git diff --stat cfd5abf..HEAD -- <scope>` | Empty or understood drift only |
| Focused implementation loop | `make agent-check` | Changed Swift lint and Debug build pass |
| UI preview coverage | `make check-preview` | Changed UI candidates have previews |
| Tests | `make test` | `Tests passed` |
| Guidance | `make guidance-check` | `guidance-check: passed` |
| Merge gate | `make lint && make test` | Both commands pass |
| Whitespace | `git diff --check` | Exit 0 |

## Suggested executor toolkit

- Use `global:macos-app-engineering` plus `.agents/overlays/macos-app-engineering.md` for route ownership, main-window lifecycle, and selected-project switching.
- Use `interface-design` and `ux-writing` for row hierarchy, copy, confirmation, empty/error states, and semantic button labels; reuse Workbench tokens rather than adding a dashboard card system.
- Use `global:swiftui-accessibility-audit` plus `.agents/overlays/swiftui-accessibility-audit.md` for project checkboxes, row Clean actions, progress, partial results, VoiceOver state, keyboard focus, and reduced transparency/motion.
- Use `swift-concurrency` for bounded analysis and mutation task ownership; do not move UI state off `@MainActor` or use unstructured detached work without an invariant.
- Use `test-strategy` for coordinator tests and temporary Git fixtures.

## Scope

**In scope** (the only implementation files for this plan):

- `GitMenuBar/Models/ProjectCleanupModels.swift` (new, only if the value models do not fit the existing cleanup model file)
- `GitMenuBar/Services/Git/ProjectCleanupStore.swift` (new)
- `GitMenuBar/App/StatusBarController.swift`
- `GitMenuBar/App/MainMenuPresentationModel.swift`
- `GitMenuBar/Components/Common/MainMenuHeaderView.swift`
- `GitMenuBar/Components/Projects/ProjectsSidebarView.swift`
- `GitMenuBar/Components/Projects/ProjectCleanupPage.swift` (new)
- `GitMenuBar/Components/Projects/ProjectCleanupProjectRowView.swift` (new only if file-size/lint limits require extraction)
- `GitMenuBar/Components/Projects/ProjectCleanupConfirmationView.swift` (new)
- `GitMenuBar/Components/Projects/ProjectCleanupResultsView.swift` (new only if the results state cannot remain focused in the page)
- `GitMenuBar/Pages/MainMenu/MainMenuView.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuContent.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift`
- `GitMenuBarTests/MainMenuPresentationModelTests.swift`
- `GitMenuBarTests/ProjectCleanupStoreTests.swift` (new)
- `GitMenuBarTests/GitWorktreeIntegrationTests.swift`, only for cross-project/shared-repository integration cases
- `plans/060-global-monitored-project-cleanup.md`
- `plans/README.md`

**Out of scope**:

- Any change to `ProjectStatusSnapshot` or the 60-second compact status reader except an explicit refresh callback already exposed by `ProjectMonitorStore`.
- Automatic fetch, remote branch deletion, GitHub/PR status, status-item badge policy, command-palette entries, or Companion CLI behavior.
- Per-project cleanup preferences, remembered selections, pinning, sorting, project grouping, search, database storage, and a new dependency.
- A new window, panel controller, or second status-item owner.
- Direct Git commands, filesystem deletion, or cleanup safety logic in SwiftUI views.
- Changing the existing branch CRUD/Worktrees diagnostic surfaces beyond the Plan 059 unit contract.

## Steps

### Step 1: Add immutable project-level analysis and batch result models

Create the smallest value models needed to project Plan 059's path-scoped Cleanup Analysis into monitored project rows. Each row model must retain the `ProjectReference`, Shared Repository identity, canonical/shared state, load state, candidate counts, blocked/unavailable explanation, and the units owned by that row. Keep project path and repository identity in IDs; names are display data only.

Represent batch execution as per-project results containing every Cleanup Unit outcome, plus aggregate counts for completed, partial, skipped, failed, and excluded/unavailable projects. Keep partial completion distinct from full success. Do not store raw Git output, full credentials, or machine state in the models.

Add pure helpers for canonical-row selection and row projection so the Shared Repository rules are testable without SwiftUI or process launches.

**Verify**: `make test` → model/coordinator tests compile and existing tests remain green.

### Step 2: Add one main-actor Project Cleanup store with bounded analysis

Create `ProjectCleanupStore` as the single owner of global cleanup state. It receives the existing `ProjectMonitorStore`'s current `monitoredProjects` and the Plan 059 path-scoped repository service; it must not create or own `GitManager` instances.

On `load()`/Refresh:

- snapshot the current monitored project list;
- resolve Shared Repository identity and cleanup analysis using at most two concurrent reads;
- group paths by identity before producing project rows;
- pass every group's monitored checkout path to the analyzer as protected;
- assign units to the canonical row and mark other rows shared;
- publish progress and final rows on the main actor;
- clear stale selection and result state when a new analysis begins.

Do not allow Clean Selected/Clean All while the initial full scan is still running. After the scan finishes, resolved canonical rows can act even if another row is unavailable; Clean All must exclude and name those unavailable rows. Preserve a refresh retry path. Do not auto-fetch.

During `runCleanup`:

- capture selected project paths and their immutable units at confirmation time;
- execute groups serially and units serially through Plan 059;
- continue after individual results;
- refresh the compact monitor after affected projects complete;
- publish the full result and affected paths;
- invoke a narrow callback from the owning main view/controller to refresh the selected `GitManager` only if its current path is affected.

The store must remain independent of sidebar selection. Switching projects while the batch runs must not cancel, redirect, or replace its captured paths.

**Verify**: `make agent-check` → changed Swift lint and Debug build pass; `make test` → store tests cover bounded scan completion, unavailable exclusion, selection reset, cancellation/replace-before-run behavior if exposed, serial result aggregation, and selected-path refresh callback inputs.

### Step 3: Add the Project Cleanup route and entry point

Add a `.projectCleanup` route and a `showProjectCleanup()` method to `MainMenuPresentationModel`. Render `ProjectCleanupPage` from `MainMenuContent.routeContent`, and add a `Project Cleanup` header with a Back control in `MainMenuHeaderView`. Preserve transparent-titlebar placement and use `MainMenuPreviewHarness(showsTransparentTitlebar: true)` for any main-window route preview.

Add one visible entry point to the existing expanded Projects sidebar header/controls. Use a native button with an accessible label and hint such as “Project Cleanup” / “Review safe branch and worktree cleanup across monitored projects.” Do not add a command-palette command or a second window unless an existing route cannot host the page.

Own the new store in `StatusBarController`, inject it through `makeRootView()`, and keep the existing `ProjectMonitorStore` and selected `GitManager` environment objects unchanged. When the route appears, trigger the store load once; an explicit Refresh may repeat it. Selecting a sidebar project while the route is visible must continue changing the selected repository without dismissing the global route.

**Verify**: `make check-preview` → all changed UI candidates have previews; `make agent-check` → lint and Debug build pass; `MainMenuPresentationModelTests` proves entering/leaving `.projectCleanup` does not corrupt the selected-project route state.

### Step 4: Build the dense project-row workflow

Implement `ProjectCleanupPage` with the existing Workbench typography, spacing, palette, and native controls. Keep the hierarchy compact:

- header: `Project Cleanup`, a one-line local-only explanation, Refresh, Clean Selected, and Clean All;
- summary: total monitored projects plus aggregate safe branch/worktree counts;
- rows: project checkbox, name/path, `N branches · M worktrees`, analysis state/reason, and a row Clean button;
- canonical rows with zero candidates: visible but disabled with a concise empty-state explanation;
- shared rows: visible for monitoring/navigation but labeled “Shared repository” with no duplicate action;
- loading: progress state with actions disabled;
- unavailable: visible error state with recovery through Refresh and explicit Clean All exclusion;
- running: controls disabled and progress/result status visible;
- completed: per-project/per-unit result groups, including partial, skipped, failed, and excluded outcomes, with Dismiss and Refresh actions.

Project checkboxes select only canonical rows that have units. Clean Selected is disabled when no eligible rows are selected. A row Clean action replaces the current selection with that row and opens the shared review. Clean All selects every eligible canonical row after analysis; it does not mutate immediately.

Use `ProjectCleanupConfirmationView` for one review surface. Show project names and branch/worktree counts, explain that linked worktree directories are removed from disk, keep Cancel available, and require the existing second acknowledgement when any worktree is present. Use active imperative labels (“Clean Selected”, “Clean All”, “Review Cleanup”, “Confirm Cleanup”) and actionable error copy. Do not add a general card/grid dashboard or per-item checkboxes to the global page.

**Verify**: `make check-preview` → previews cover loading, empty, unavailable, shared, selected, paired-worktree warning, partial results, and reduced-motion states; `make agent-check` → lint and Debug build pass.

### Step 5: Verify multi-project safety and manual behavior

Add `ProjectCleanupStoreTests` using pure row/group helpers and temporary repositories where process behavior matters. Cover:

- three monitored repositories with the same branch name remain separate;
- one repository with main and linked monitored worktree produces one canonical actionable row and one protected/shared row;
- Clean Selected includes only selected canonical rows;
- Clean All excludes zero-candidate and unavailable rows and reports exclusions;
- a paired unit removes worktree then branch;
- a stale/dirty/locked/changed unit is skipped while later repositories continue;
- partial branch deletion is visible in the result;
- switching the selected repository during a batch does not change captured paths, and only an affected selected path requests GitManager refresh;
- no fetch, remote deletion, force flag, or developer-checkout mutation occurs.

Manual Debug verification:

1. Monitor three disposable local repositories, including one with a merged branch and clean linked worktree, one with dirty/unmerged state, and one unavailable after analysis.
2. Open Project Cleanup from the Projects sidebar and confirm all rows appear without opening individual project sheets.
3. Confirm counts distinguish branches and worktrees, paired rows show one action, shared monitored worktrees are protected, and Clean Selected/Clean All require review.
4. Confirm a partial/failure result leaves the branch or directory that could not be safely removed and names the next action.
5. Switch the selected project while cleanup is running; confirm the cleanup continues and the result remains visible.
6. Verify VoiceOver/keyboard labels identify project selection, counts, Clean actions, directory-removal warning, loading, exclusions, and partial results. Repeat with Reduce Motion and Reduce Transparency enabled.

**Verify**: `make test` → all tests pass; manual Debug verification records no unexpected Git mutation; `git diff --check` → exit 0.

### Step 6: Close the plan surface

Run `make guidance-check`, `make lint && make test`, and `make check-preview`. Review the final diff for route ownership, environment injection, no duplicate service/model, and no source files outside scope. Update the Plan 060 row only after all done criteria pass.

**Verify**: all three gates pass and `git status --short` lists only scoped implementation/test files and the plan index.

## Test plan

- `ProjectCleanupStoreTests.swift`: pure canonical-row/grouping/selection helpers, load states, unavailable exclusion, aggregate counts, serial result aggregation, and selected-path refresh callback behavior.
- `GitMenuBarTests/GitWorktreeIntegrationTests.swift`: extend existing temporary-repository fixtures for monitored linked worktrees, shared repository identity, paired ordering, and partial outcomes.
- `MainMenuPresentationModelTests.swift`: add route transition coverage for `.projectCleanup` and Back.
- Keep `ProjectMonitorStoreTests.swift` unchanged unless a narrow refresh callback test is required; do not expand `ProjectStatusSnapshot` for cleanup data.
- Use previews for visual states, not as a substitute for Git mutation tests.

## Done criteria

- [ ] A global Project Cleanup page lists every monitored project in one view.
- [ ] Each canonical project row shows safe branch and worktree counts, with shared/unavailable/zero states explained.
- [ ] Row Clean, Clean Selected, and Clean All use the same review and path-scoped Cleanup Unit service.
- [ ] Clean All excludes unavailable, zero-candidate, shared duplicate, protected, and unknown items without guessing.
- [ ] Analysis is bounded to two concurrent reads; mutations are serial and never fetch or delete remote branches.
- [ ] Switching the selected project cannot cancel or redirect a running global cleanup.
- [ ] Results distinguish completed, partial, skipped, failed, and excluded outcomes.
- [ ] Loading, empty, error, disabled, focus, VoiceOver, reduced-motion, and reduced-transparency states are covered.
- [ ] Every changed UI Swift file has `#Preview` coverage.
- [ ] `make agent-check`, `make check-preview`, `make guidance-check`, `make lint`, and `make test` pass.
- [ ] No files outside the scope are modified.

## STOP conditions

- The global coordinator needs `GitManager` instances per monitored project or must mutate through the selected repository's mutable context.
- Shared Repository identity cannot be resolved deterministically, or two rows would display/execute the same Cleanup Unit.
- The proposed UI requires automatic fetch, remote deletion, force operations, filesystem deletion, or a new window/controller.
- Clean All cannot produce a complete exclusion/result record for unavailable or stale projects.
- A running batch can be redirected by sidebar selection, loses its captured paths, or publishes results after a newer scan without an explicit generation check.
- Swift 6 strict-concurrency diagnostics require broad unsafe annotations rather than immutable value transfer or a narrow actor boundary.
- Preview coverage or manual accessibility behavior cannot be provided for a new UI file.

## Maintenance notes

Keep the lightweight `ProjectMonitorStore` and full Cleanup Analysis separate. If users later need remote cleanup, add a separate authorization and freshness design rather than widening Clean All. If project count grows beyond the existing two-read budget, measure before changing concurrency; Git process cost and repository locking are the relevant constraints. If the global route gains more unrelated project operations, extract a project-workbench navigation model only after a concrete second use case appears.
