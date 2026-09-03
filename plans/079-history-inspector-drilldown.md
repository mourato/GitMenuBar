# Plan 079: Move history into the contextual inspector

> **Executor instructions**: Read this brief and Plans 076–078 before editing.
> This is the final UI migration for the inspector batch. Preserve the current
> history data/action semantics unless this brief explicitly changes them.
> Run the drift check first, stop on unexplained drift, and update only the
> Plan 079 bookkeeping row when complete.
>
> **Drift check (run first)**: git diff --stat 2118aad..HEAD -- GitMenuBar/App/MainMenuPresentationModel.swift GitMenuBar/App/StatusBarController.swift GitMenuBar/Pages/MainMenu/MainMenuView.swift GitMenuBar/Pages/MainMenu/MainMenuContent.swift GitMenuBar/Pages/MainMenu/MainMenuKeyboardNavigation.swift GitMenuBar/Pages/MainMenu/MainMenuInspectorView.swift GitMenuBar/Pages/MainMenu/HistorySectionView.swift GitMenuBar/Pages/MainMenu/HistoryInspectorView.swift GitMenuBar/Components/History/CommitDetailPageView.swift GitMenuBarTests/MainMenuPresentationModelTests.swift GitMenuBarTests/HistoryActionSetTests.swift GitMenuBarTests/HistoryInspectorNavigationTests.swift

## Status

- **Priority**: P0
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: [Plan 076](076-workbench-inspector-shell.md), [Plan 077](077-project-state-overview.md), and [Plan 078](078-contextual-git-detail-actions.md)
- **Category**: direction
- **Planned at**: commit 2118aad, 2026-09-03
- **Finding ID**: history-inspector-drilldown
- **Publication**: local
- **Parent issue**: none
- **Issue**: none
- **Integration**: main; merge and push require explicit operator authorization

## Execution profile

- **Recommended profile**: implementer
- **Risk/lane**: High/Full
- **Parallelizable**: no — it removes a top-level route, changes toolbar behavior, moves the history scroll owner, and reuses the contextual selection/action contract
- **Reviewer required**: yes — this changes navigation, destructive reset presentation, keyboard activation, and the main window's back affordance
- **Rationale**: The history renderer and commit detail view already exist, so the smallest safe migration is to move those views behind the Plan 076 inspector selection and remove only the duplicate route. A serial implementer can preserve row actions, pagination, previews, and accessibility while avoiding a fourth navigation surface.
- **Escalate when**: history needs a separate window, a fourth column, a new history store, duplicate Git history fetching, persisted navigation state, or a rewrite of CommitDetailPageView rather than a scroll-owner/layout adaptation.

## Why this matters

History is currently rendered in the central scroll view and activated as a
replacement route, which makes the user lose the repository workbench while
inspecting one commit. The accepted interaction is a central overview/list
selection that expands in the trailing inspector: history list first, then the
selected commit detail in that same panel.

This plan makes the inspector the single history detail surface. It keeps the
center's repository overview and working-tree context visible, removes the
obsolete history route/back-toolbar state, and preserves the existing
pagination, GitHub, copy, edit, generate, changed-file, and reset capabilities
with an explicit confirmation for reset.

## External-state addendum

- **Authority**: local commit refs, selected branch, working tree, and existing
  remote metadata remain authoritative. The history list is a read model.
- **Identity**: commit actions capture the selected repository path, current
  branch/ref, and commit hash before an async operation. A commit hash is not
  a substitute for repository identity.
- **Scope**: Reset to Here may mutate only the captured repository and selected
  commit. It must not retarget after a project switch or a branch change.
- **Preflight**: at confirmation/execution time, verify the selected commit is
  still available and the repository context is still valid. If not, fail
  closed and refresh; never reset to a newly selected repository.
- **Destructive action**: Reset to Here remains a destructive secondary action
  with a native confirmation. Do not add force reset, automatic rollback, or
  silent discard of working changes.
- **Failure**: show the existing Git error and retain the inspector selection.
  Refresh only after a successful or failed operation has a known captured
  path; do not claim a reset succeeded before Git returns success.
- **Concurrency**: use the Plan 078/MainMenuActionCoordinator admission seam
  for reset if it is available. If the existing reset API remains unbound,
  block repository switching for its full operation and document the
  limitation; do not create a second coordinator.

## Current state

- MainMenuPresentationModel.swift:5-9 defines MainMenuRoute with main,
  createRepo, historyDetail(commitID), and projectCleanup. :68-70 exposes
  showHistoryDetail.
- MainMenuContent.swift:111-120 switches .historyDetail to a detail route.
  :176-207 builds CommitDetailPageView, while :281-313 renders the full
  HistorySectionView in the main scroll and activates historyDetail.
- MainMenuKeyboardNavigation.swift:97-102 activates a history selection by
  calling showHistoryDetail. This must become inspector commit selection.
- StatusBarController.swift:436-459 adds a toolbar back item for
  historyDetail/projectCleanup and changes the title to Commit Details.
  :1211-1212 includes historyDetail in route diagnostics.
- HistorySectionView.swift is a reusable history list wrapper around
  HistoryTimelineSectionView. It has no outer ScrollView and already supports
  selection, activation, restore, edit, generate, and load-more callbacks.
- CommitDetailPageView.swift:34-57 owns its own vertical ScrollView and
  currently caps it at 520 points. It already renders metadata, stats, changed
  files, copy/Open on GitHub, edit/generate, and Reset to Here.
- CommitDetailPageView+Preview.swift is the existing self-contained preview
  companion. Any changed UI file still needs direct or same-directory preview
  coverage.
- MainMenuRenderSnapshot.historySections and historyRowAdapters must remain
  available to the inspector. Do not fetch history again when opening the
  inspector.
- Plan 078 owns the contextual action safety seam and Plan 076 owns the one
  optional inspector selection. Do not introduce a second NavigationStack at
  the root or a fourth column.

The target navigation shape is:

    center History overview button
        -> inspector History list
        -> inspector commit detail
        -> inspector Back to History

Use a type-safe local inspector destination, such as a small
HistoryInspectorDestination enum with commit(hash), rather than a stringly
typed global route. The root MainMenuInspectorSelection remains the only
cross-surface selection value.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Drift | git diff --stat 2118aad..HEAD -- [the paths in the drift check] | Empty or explained Plan 076–079 changes only |
| Presentation tests | make test-focused TEST_FILTER='GitMenuBarTests/MainMenuPresentationModelTests' | Route tests pass after historyDetail removal |
| History action tests | make test-focused TEST_FILTER='GitMenuBarTests/HistoryActionSetTests' | Existing action semantics pass |
| History inspector tests | make test-focused TEST_FILTER='GitMenuBarTests/HistoryInspectorNavigationTests' | Selection/destination/reset-confirmation model tests pass |
| Changed-surface check | make agent-check | Changed Swift lint and Debug build pass |
| Preview coverage | ./scripts/check-preview.sh GitMenuBar/Pages/MainMenu/HistoryInspectorView.swift GitMenuBar/Pages/MainMenu/MainMenuInspectorView.swift GitMenuBar/Components/History/CommitDetailPageView.swift | All UI candidates have previews |
| Full merge gate | make lint && make test | Lint and all XCTest tests pass |
| Hygiene | git diff --check | No whitespace errors |

## Suggested executor toolkit

- Use swiftui-expert-skill for NavigationStack destinations, selection,
  scroll ownership, stable identities, and preview isolation.
- Use macos-app-engineering for toolbar/back-route ownership.
- Use apple-design and swiftui-accessibility-audit for panel continuity,
  focus/Escape, destructive confirmation, contrast, and reduced motion.
- Use ux-writing for History, Back to History, Reset to Here, and failure copy.
- Use swift-concurrency, codebase-design, and test-strategy for the reset
  operation context and quiet async tests.
- Use delivery-workflow before all validation commands.

## Scope

**In scope:**

- GitMenuBar/App/MainMenuPresentationModel.swift
- GitMenuBar/App/StatusBarController.swift
- GitMenuBar/Pages/MainMenu/MainMenuView.swift
- GitMenuBar/Pages/MainMenu/MainMenuContent.swift
- GitMenuBar/Pages/MainMenu/MainMenuKeyboardNavigation.swift
- GitMenuBar/Pages/MainMenu/MainMenuInspectorView.swift
- GitMenuBar/Pages/MainMenu/HistorySectionView.swift
- GitMenuBar/Pages/MainMenu/HistoryInspectorView.swift (create)
- GitMenuBar/Components/History/CommitDetailPageView.swift
- GitMenuBarTests/MainMenuPresentationModelTests.swift
- GitMenuBarTests/HistoryActionSetTests.swift
- GitMenuBarTests/HistoryInspectorNavigationTests.swift (create)
- plans/README.md — only the Plan 079 bookkeeping row

**Out of scope:**

- changing Git history parsing, pagination batch size, GitHub API behavior, or
  commit model shape
- redesigning changed-file tree visuals, author avatars, commit editing, or
  branch/worktree management
- a new history cache/store, automatic fetch, new window, fourth column, or
  persistent inspector navigation
- removing the existing MainMenuRenderSnapshot history data
- unrelated route migration for createRepo or projectCleanup
- rewriting completed ADRs or historical plans

## Git workflow

- Use the assigned isolated worktree and branch from
  core/policies/worktrees.md.
- Reclassify the live diff as High/Full if reset or route ownership is broader
  than this brief.
- Review before commit, then run the full merge gate. Keep integration and
  main validation separate.
- Do not merge, push, amend, or clean up worktrees without authorization.

## Steps

### Step 1: Add the history inspector list/detail container

Create HistoryInspectorView.swift with a local NavigationStack or equivalent
type-safe list/detail state. The root list must reuse the existing
HistorySectionView/HistoryTimelineSectionView data and callbacks. Pass the
already-built sections from MainMenuRenderSnapshot; opening the inspector must
not call fetchCommitHistory again.

The list view owns one vertical ScrollView for the history list. The commit
detail destination uses CommitDetailPageView as its own sole scroll owner; do
not wrap it in another ScrollView. Add a Back to History toolbar/header button
inside the inspector destination and preserve selected commit identity when
the user returns to the list.

Connect existing callbacks:

- row selection updates root MainMenuInspectorSelection.commit when appropriate;
- activation pushes the local commit destination;
- load-more calls the existing GitManager pagination method;
- Open on GitHub, copy, edit, generate, and changed-file open reuse the
  existing callbacks and coordinators;
- restore requests confirmation rather than mutating immediately.

Add a self-contained preview with an in-memory list, selected commit, empty
history, loading, and unavailable commit states. Do not invoke real GitHub,
Keychain, or Git services in the preview.

**Verify**: ./scripts/check-preview.sh
GitMenuBar/Pages/MainMenu/HistoryInspectorView.swift passes, and a manual
preview shows list-to-detail-to-back navigation without a nested scrollbar.

### Step 2: Replace the center history list with the overview entry point

Remove the full HistorySectionView from mainScrollContent after confirming
Plan 077's History overview button is present. Keep the central workbench
scroll owner and the existing history render snapshot data for the inspector.
Do not leave two full history lists visible.

Change history selection/activation in MainMenuContent and
MainMenuKeyboardNavigation to select MainMenuInspectorSelection.history or
commit rather than calling showHistoryDetail. Preserve arrow/delete/text-input
guards and native keyboard focus. If the current HistorySectionView wrapper is
still needed by the inspector, keep it reusable and remove only the center
call site or add the smallest explicit presentation mode.

**Verify**: a manual preview has one History entry in the center and one list
in the inspector; Return/activation opens the inspector destination, and the
old center route is not presented.

### Step 3: Remove the obsolete history route and toolbar affordance

After all callers are migrated, remove historyDetail from
MainMenuRoute/showHistoryDetail and update MainMenuView's route switch and
transition. Keep createRepo and projectCleanup behavior unchanged.

Remove only the history-specific toolbar back item/title/route diagnostic from
StatusBarController. The project-cleanup back behavior and current native
titlebar/settings/sidebar controls must remain. Update presentation model tests
to assert main/createRepo/projectCleanup behavior without historyDetail.

Do not keep a dead route solely for compatibility. If an external caller still
needs history navigation, route it to MainMenuInspectorSelection.commit through
the existing main-window owner instead of adding a second navigation mechanism.

**Verify**: rg -n 'historyDetail|showHistoryDetail' GitMenuBar
returns no live callers except historical plan text, or every remaining
occurrence is a justified non-route compatibility symbol documented in the
handoff. MainMenuPresentationModelTests pass.

### Step 4: Adapt commit detail and reset confirmation

Make the minimum layout change needed for CommitDetailPageView to work in the
inspector's available height while preserving its standalone content and
preview. Keep it as the only scroll owner in its destination. Do not create a
second commit detail renderer.

Route Reset to Here through a native confirmation owned by
HistoryInspectorView or the Plan 078 contextual action owner. The confirmation
must identify the commit subject/hash, offer Cancel and a destructive Reset
action, and leave the inspector selection intact on cancellation/failure.
Capture repository context at confirmation/execution time and use the
path-bound API or the documented unbound-operation switch block. A reset must
not run if the commit is current, missing, stale, or the repository changed.

Preserve existing HistoryActionSet rules for GitHub/edit/generate/restore.
Only make the confirmation and scroll-owner changes required by this plan.

**Verify**: HistoryActionSetTests and HistoryInspectorNavigationTests pass for
current/future/unavailable commits, valid/invalid reset actions, cancellation,
and stale context. No reset test touches the user's actual repository.

### Step 5: Run UI and full validation

Run focused presentation/history tests, make agent-check, explicit preview
coverage, make lint && make test, and git diff --check. Review the final diff
for duplicate history reads, duplicate scroll owners, lost focus, route
references, and stale toolbar titles.

**Verify**: all commands pass. Record any native VoiceOver or resize check
that cannot run in this environment as an operator handoff.

## Test plan

- Update MainMenuPresentationModelTests.swift to remove historyDetail route
  expectations and preserve all remaining route transitions.
- Keep HistoryActionSetTests.swift green and add only reset eligibility cases
  if needed.
- Add HistoryInspectorNavigationTests.swift for local destination mapping,
  list/detail/back behavior as pure state where possible, and reset
  confirmation gating. Do not launch a visible NavigationStack in XCTest.
- Reuse existing CommitHistoryParserTests and pagination tests for data
  behavior; do not add duplicate Git history fixtures.
- Manual checks: wide inspector, compact sheet, history list pagination,
  commit detail, Back to History, Return/keyboard activation, VoiceOver,
  Escape, Reduce Motion, increased contrast, Reduce Transparency, and reset
  cancellation/failure.

Focused verification:

    make test-focused TEST_FILTER='GitMenuBarTests/MainMenuPresentationModelTests'
    make test-focused TEST_FILTER='GitMenuBarTests/HistoryActionSetTests'
    make test-focused TEST_FILTER='GitMenuBarTests/HistoryInspectorNavigationTests'
    make lint && make test

## Done criteria

- [ ] The center no longer renders a duplicate full history list; its History
      overview entry opens the trailing inspector.
- [ ] The inspector provides history list → commit detail → Back to History
      in one contextual surface, with no fourth column or new window.
- [ ] Commit detail uses one scroll owner, preserves existing actions and
      previews, and does not fetch history twice.
- [ ] historyDetail/showHistoryDetail route and its toolbar affordance are
      removed without changing createRepo/projectCleanup behavior.
- [ ] Reset to Here is explicitly confirmed, path-safe, and reports failure
      without losing selection.
- [ ] Focused tests, make agent-check, explicit preview coverage,
      make lint && make test, and git diff --check pass.
- [ ] No files outside Scope are modified; plans/README.md has the Plan 079
      status/evidence row only.

## STOP conditions

Stop and report if:

- the full history list cannot be moved without a second history fetch/store;
- removing historyDetail would alter createRepo/projectCleanup or status-item
  toolbar behavior;
- CommitDetailPageView would need a second ScrollView or a duplicated detail
  renderer;
- reset cannot capture repository/branch/commit identity or would run after a
  project switch without the Plan 078 safety boundary;
- an old route caller remains unexplained after the migration;
- a new window, fourth column, persistent navigation state, or broad history
  redesign is proposed;
- preview coverage requires a live repository, credentials, or visible app
  window;
- the live code differs from the Current state in an unexplained way;
- a verification command fails twice after a scoped fix; or
- an out-of-scope path must be modified.

## Maintenance notes

- Keep history selection in the root MainMenuInspectorSelection, but keep
  list/detail navigation local to HistoryInspectorView.
- If future history filtering/search is needed, add it inside the inspector
  after measuring the existing list; do not restore a second center list.
- Reviewers should inspect route removal completeness, toolbar ownership,
  scroll ownership, reset confirmation/context, pagination reuse, focus/Escape,
  and compact-sheet continuity.
- The current history data model and history action set remain the source of
  truth; this plan changes placement and navigation, not Git semantics.
