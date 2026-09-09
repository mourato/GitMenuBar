# Plan 076: Add the hidden trailing inspector shell

> **Executor instructions**: Read this brief and the linked project documents
> before editing. Follow the steps in order and run each verification command.
> If a STOP condition occurs, stop and report it; do not widen the scope.
> When complete, update the Plan 076 row in plans/README.md with implementation,
> review, integration, and main-validation evidence separately. Leave merge and
> push to the operator.
>
> **Drift check (run first)**: git diff --stat 2118aad..HEAD -- GitMenuBar/Components/Common/WorkbenchMetrics.swift GitMenuBar/Pages/MainMenu/MainMenuInteractionModels.swift GitMenuBar/Pages/MainMenu/MainMenuView.swift GitMenuBar/Pages/MainMenu/MainMenuContent.swift GitMenuBar/Pages/MainMenu/MainMenuKeyboardNavigation.swift GitMenuBar/Pages/MainMenu/MainMenuInspectorView.swift GitMenuBarTests/MainMenuInspectorSelectionTests.swift docs/ui.md docs/adr/0010-contextual-workbench-inspector.md
>
> Files changed by an earlier execution of this plan are expected only after
> the executor has started. Before editing, unexplained changes in the listed
> paths are a STOP condition.

## Status

- **Priority**: P0
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: direction
- **Planned at**: commit 2118aad, 2026-09-03
- **Finding ID**: contextual-workbench-inspector-shell
- **Publication**: local
- **Parent issue**: none
- **Issue**: none
- **Integration**: main; merge and push require explicit operator authorization

## Execution profile

- **Recommended profile**: implementer
- **Risk/lane**: Medium/Full
- **Parallelizable**: no — this establishes the shared selection and presentation owner used by Plans 077–079
- **Reviewer required**: yes — it changes the main macOS window shell, selection semantics, focus dismissal, and durable UI documentation
- **Rationale**: The implementation is mostly native SwiftUI composition, but an incorrect modifier owner can produce duplicate sheets, a fourth column, or lost selection when the window resizes. A single implementer should reconcile the existing NavigationSplitView, AppKit titlebar, keyboard monitor, and inspector lifecycle.
- **Escalate when**: the SDK does not provide a usable macOS inspector/sheet transition, the minimum window must be changed, a second presentation coordinator is proposed, or the change needs StatusBarController lifecycle changes beyond the existing main-window route.

## Why this matters

GitMenuBar currently has a Projects sidebar and one selected-project content
column. The existing selection state highlights files and commits, but it has
no contextual detail surface, so a user must leave the main workbench or infer
state from compact counts. This plan establishes one trailing inspector that
is absent until a central item is selected, remains alongside the central
content on a wide window, and uses a native sheet presentation when the three
surfaces cannot fit.

This is the shell and ownership contract only. It must not duplicate Git
queries, add a second project manager, or turn the main window into a dashboard.
Plans [077](077-project-state-overview.md), [078](078-contextual-git-detail-actions.md),
and [079](079-history-inspector-drilldown.md) fill the inspector with the
approved repository views.

## Current state

- GitMenuBar/Pages/MainMenu/MainMenuContent.swift:216-241 builds the two-column
  main workbench with NavigationSplitView. Its sidebar is ProjectsSidebarView;
  its detail is routeContent with the existing main route, history route, and
  cleanup route.
- GitMenuBar/Pages/MainMenu/MainMenuView.swift:48 owns
  selectedMainItemID: MainMenuSelectableItem? and :120-149 switches the
  top-level route. The same view already owns transient presentations and
  .onExitCommand dismissal.
- GitMenuBar/Pages/MainMenu/MainMenuKeyboardNavigation.swift:68-103 owns
  keyboard selection and currently activates a history item by calling
  MainMenuPresentationModel.showHistoryDetail. Do not remove that route in this
  plan; Plan 079 owns its migration.
- GitMenuBar/Pages/MainMenu/MainMenuInteractionModels.swift:54-58 defines the
  stable staged-file, unstaged-file, and history-commit selection IDs. Add the
  inspector selection vocabulary beside this model rather than creating a
  second unrelated selection store.
- GitMenuBar/Components/Common/WorkbenchMetrics.swift:25-40 owns spacing,
  radii, and hit targets. The existing UI contract requires Workbench tokens
  and native controls; do not add per-view magic numbers.
- GitMenuBar/App/StatusBarController.swift creates MainMenuView in the
  transparent titled window. The current minimum window size is 900 by 640,
  so the narrow presentation must fit that window without changing the status
  item lifecycle or toolbar ownership.
- The deployment target is macOS 15.5. SwiftUI .inspector and
  .inspectorColumnWidth are available; use the native modifier. Do not add a
  split-view dependency or custom AppKit panel.
- docs/ui.md is the active visual contract. It requires the existing calm,
  dense workbench, native materials, one scroll owner per surface, preserved
  selection/focus/VoiceOver behavior, and Reduce Motion/Reduce Transparency
  support. The three-column inspector rule is new and must be recorded there
  in the same implementation.
- Every new UI-rendering Swift file under GitMenuBar/Pages or Components needs
  a local #Preview or a same-directory preview companion. Preview data must
  be in-memory and must not run Git commands.

The intended state shape is one optional value on MainMenuView:

- nil means no inspector is presented;
- a section selection identifies a top-level repository topic;
- an item selection identifies a file, branch, stash, or commit;
- the left project selection and the inspector selection are separate, so
  changing repositories clears the inspector but does not change the selected
  project.

Use one enum, named MainMenuInspectorSelection, with these stable cases:
workingTree, branches, unpushedCommits, stashes, history, stagedFile(path),
unstagedFile(path), branch(name), stash(id), and commit(id). The item cases
are defined now so later plans extend the view without changing the selection
owner or inventing another binding. IDs must use normalized/stable values:
file paths for files, branch names for branches, stash commit hashes for
stashes, and commit hashes for commits. Do not use stash list indexes because
Git reindexes them after a drop.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Drift | git diff --stat 2118aad..HEAD -- [the paths in the drift check] | Empty or explained changes from this plan only |
| Focused implementation check | make agent-check | Changed Swift lint and Debug build pass |
| Preview coverage | ./scripts/check-preview.sh GitMenuBar/Pages/MainMenu/MainMenuInspectorView.swift | Preview coverage passes for the new inspector view |
| UI gate | make check-preview | Passes, or reports the documented clean-tree empty-file baseline; if that baseline appears, run the explicit candidate command above |
| Guidance | make guidance-check | Guidance and all local plan profiles pass |
| Hygiene | git diff --check | No whitespace errors |

## Suggested executor toolkit

- Read [docs/ui.md](../docs/ui.md) before changing native UI.
- Use apple-design for materials, hierarchy, motion, and native macOS surface
  decisions.
- Use macos-app-engineering for main-window/presentation ownership.
- Use swiftui-expert-skill for inspector, sheet, state, preview, and scroll
  ownership.
- Use swiftui-accessibility-audit for labels, focus, Escape, reduced motion,
  and reduced transparency.
- Use swift-conventions for formatting and source placement.
- Use test-hygiene before creating or running tests; keep tests nonvisual.
- Use delivery-workflow before build, test, lint, preview, or guidance gates.

## Scope

**In scope — the only product/document files this plan may modify:**

- GitMenuBar/Components/Common/WorkbenchMetrics.swift
- GitMenuBar/Pages/MainMenu/MainMenuInteractionModels.swift
- GitMenuBar/Pages/MainMenu/MainMenuView.swift
- GitMenuBar/Pages/MainMenu/MainMenuContent.swift
- GitMenuBar/Pages/MainMenu/MainMenuKeyboardNavigation.swift
- GitMenuBar/Pages/MainMenu/MainMenuInspectorView.swift (create)
- GitMenuBarTests/MainMenuInspectorSelectionTests.swift (create)
- docs/ui.md
- docs/adr/0010-contextual-workbench-inspector.md (create)
- plans/README.md — only the Plan 076 bookkeeping row

**Out of scope:**

- Git queries, GitManager, ProjectMonitorStore, GitBranchService, stash
  persistence, or any new Git command
- detailed overview cards and repository metrics (Plan 077)
- branch, push, file mutation, or stash actions (Plan 078)
- moving or redesigning history (Plan 079)
- a fourth column, a new window, a persistent inspector preference, a custom
  AppKit panel, a dashboard chart, or a new event bus
- changing the status-item click/dismissal flow or the existing toolbar

## Git workflow

- Implement on the isolated worktree and branch assigned by the operator,
  following core/policies/worktrees.md.
- The plan-authoring base is 2118aad. Reclassify the live implementation
  against the actual post-plan base before editing.
- Keep commits small enough to review: shell/model, documentation, then tests
  and validation is a reasonable grouping.
- Do not merge, push, amend, or clean up worktrees without authorization.

## Steps

### Step 1: Define the shared selection and width contract

Add MainMenuInspectorSelection and its stable Identifiable ID in
MainMenuInteractionModels.swift. Add only the named width metrics needed for
the three surfaces: the existing Projects minimum width, a minimum central
content width, a minimum inspector width, and a derived compact threshold.
Replace the current literal Projects minimum width with the token if that
keeps behavior identical.

Do not put GitManager, SwiftUI bindings, or action closures in the selection
enum. It is a value model, not a coordinator. Add pure tests for every case's
ID and for the mapping from existing MainMenuSelectableItem values to staged,
unstaged, and commit inspector selections.

**Verify**: make agent-check and the focused test command
make test-focused TEST_FILTER='GitMenuBarTests/MainMenuInspectorSelectionTests'
both pass.

### Step 2: Add the native hidden inspector host

Create MainMenuInspectorView.swift with a real, compact shell:

- a native-style header with the current project identity, selection title,
  and an accessible Close Details button;
- a single scroll owner for any shell content;
- a neutral selection identity body, not a fake Git detail result;
- Workbench typography, spacing, palette, and native control hit targets;
- previews for no-data/file/commit selection using only sample values.

Attach .inspector to the selected-project detail owner, not to a second
NavigationSplitView. Set the native inspector column width with
.inspectorColumnWidth using the new Workbench metrics. The inspector is
presented only when MainMenuInspectorSelection is non-nil.

Use the same optional selection to drive the narrow presentation with
.sheet(item:). Derive a compact mode from the actual root window width and the
named column minimums; do not persist the threshold or expose it as a
preference. The wide binding must present .inspector and the compact binding
must present .sheet, never both. If a resize crosses the threshold while
details are open, preserve the selection and transfer the presentation once;
do not create a duplicate overlay or flash an empty panel.

Keep the existing MainMenuRoute history detail route intact for now. The shell
must not add a toolbar toggle because the accepted behavior is hidden-until-
selected. The existing .onExitCommand order must close the inspector first,
then other transient presentations, then the window.

**Verify**: ./scripts/check-preview.sh GitMenuBar/Pages/MainMenu/MainMenuInspectorView.swift
passes; make check-preview passes or is reduced to the explicit candidate
result documented in the handoff; no new toolbar item or fourth
NavigationSplitView column appears in the preview.

### Step 3: Connect existing central selection without changing Git behavior

When an existing working-tree row is selected, set both the current
MainMenuSelectableItem and the matching inspector item. When an existing
history row is selected, set the commit inspector item while retaining the
current route activation behavior for Return/double-click; Plan 079 will
replace that route. Clear inspector selection when the repository path changes
or a non-main route is entered.

Update keyboard handling so Return on an existing history item still follows
the current route until Plan 079, while Escape/.onExitCommand closes the
inspector before closing the window. Preserve the custom arrow/delete monitor,
text-input guard, command-palette guard, and VoiceOver selection labels.

The inspector body in this plan may show only selection identity. It must not
run a Git process or add a second copy of the working-tree/history renderer.

**Verify**: the existing MainMenuSelectionNavigator tests still pass; a
preview/manual check confirms that one central row selection opens one
trailing inspector, changing the project clears it, and Escape closes it
without changing the project selection.

### Step 4: Record the durable UI decision

Update docs/ui.md with the active three-surface rule:

- Projects remains the left compact navigation/attention surface;
- the center remains the selected repository workbench;
- the trailing inspector is hidden until a central selection exists;
- wide windows use a resizable native inspector; narrow windows use a sheet
  bound to the same selection;
- the inspector has one scroll owner, preserves selection/focus, and closes
  predictably with Escape;
- no automatic fetch, duplicated status query, fourth column, or persistent
  inspector preference is part of this rule.

Create docs/adr/0010-contextual-workbench-inspector.md with Status Accepted,
the date 2026-09-03, context, decision, consequences, rejected alternatives,
ownership, accessibility, and reversal conditions. Link the ADR from the
relevant docs/ui section. Keep ADR 0002's titlebar/material decision and ADR
0009's path-bound Git-action decision unchanged.

**Verify**: make guidance-check and git diff --check pass. The new ADR and
docs/ui links resolve.

## Test plan

- Add MainMenuInspectorSelectionTests.swift for stable IDs, item-to-inspector
  mapping, repository-change clearing rules if represented as pure state, and
  the compact/wide presentation decision if it has a pure helper.
- Do not launch a real window, preview, or AppKit panel from XCTest. Follow
  the quiet test boundary in test-hygiene.
- Use the existing MainMenuRenderSnapshotTests and
  MainMenuPresentationModelTests only as regression checks; do not rewrite
  route tests until Plan 079 removes historyDetail.
- Manual handoff: wide window with inspector hidden, file selected, history
  selected, project switched, Escape dismissal, resize across compact
  threshold, Light/Dark, increased contrast, Reduce Transparency, and Reduce
  Motion.

Focused verification:

    make test-focused TEST_FILTER='GitMenuBarTests/MainMenuInspectorSelectionTests'

## Done criteria

- [ ] MainMenuInspectorSelection is one stable value model; no second selection
      store or generic action bus exists.
- [ ] No selection produces no inspector or sheet.
- [ ] A selected existing central file/commit produces one trailing inspector
      on a wide window and the same detail shell as one native sheet below the
      named compact threshold.
- [ ] The existing left Projects sidebar, main route, status-item lifecycle,
      and historyDetail route still behave as before.
- [ ] Escape closes the inspector first; repository changes clear contextual
      selection; focus and VoiceOver labels remain usable.
- [ ] New UI source has preview coverage and uses Workbench tokens.
- [ ] Focused tests, make agent-check, preview coverage, make guidance-check,
      and git diff --check pass.
- [ ] No files outside the Scope list are modified; plans/README.md has the
      Plan 076 status/evidence row only.

## STOP conditions

Stop and report if:

- the live code at a referenced symbol no longer matches and the difference
  is not an expected change from this plan;
- .inspector is unavailable or cannot be attached without replacing the
  existing NavigationSplitView;
- the implementation needs a second observable selection/presentation owner,
  a new AppKit window/panel, or a persisted preference;
- compact mode would present both .inspector and .sheet or lose the selected
  item during a resize;
- the new shell needs GitManager or ProjectMonitorStore queries to render;
- a new UI file cannot receive a self-contained preview without real
  credentials, a live repository, or a visible window;
- a verification command fails twice after a reasonable, scoped fix; or
- an out-of-scope path must be modified.

## Maintenance notes

- Plans 077–079 must extend MainMenuInspectorView through the existing
  MainMenuInspectorSelection cases instead of adding one view/panel per
  metric. Keep the selection owner in MainMenuView unless a concrete
  ownership bug requires moving it.
- If the compact threshold needs calibration, change the named Workbench
  metrics and the UI documentation together. Do not add a user setting.
- Reviewers should inspect modifier ownership, resize transitions, Escape/focus
  behavior, preview isolation, and accidental nested scroll views.
- Deferred: full contextual content, mutations, stash identity, and history
  navigation are intentionally owned by the dependent plans.
