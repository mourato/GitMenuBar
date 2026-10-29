# Plan 089: Move repository actions and branch picker into the toolbar

> **Executor instructions**: Read this brief, `AGENTS.md`,
> [project workflow facts](../docs/agents/project-workflow.md),
> [UI contract](../docs/ui.md) (especially "Visual hierarchy rules"), and
> [ADR 0020](../docs/adr/0020-toolbar-actions-and-history-list.md) before
> editing. Work in a dedicated worktree. Use Workbench tokens only; no raw
> sizes, colors, or opacities in views. On a STOP condition, stop and report;
> do not widen scope. Leave merge and push to the operator. The UI owner
> reviews the diff and screenshots before merge.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MEDIUM
- **Depends on**: none
- **Category**: ui (premium main-window pass)
- **Planned at**: commit e48a916, 2026-10-28
- **Integration**: main; merge and push require explicit operator authorization

## Execution profile

- **Recommended profile**: Standard/full
- **Risk/lane**: MEDIUM (AppKit toolbar state, action routing)
- **Executor**: Codex GPT 5.6 Luna, reasoning xhigh
- **Parallelizable**: No; plans 090 and 094 depend on it
- **Reviewer required**: Yes
- **Rationale**: Toolbar items need live repository state and action routing through AppKit; mistakes break primary Git actions.
- **Escalate when**: an action needs a new Git service call, or toolbar state needs a second source of truth beside the selected repository snapshot.

## UI-owner review amendments

- Keep toolbar labels short and use the long repository-specific sentences only
  for accessibility descriptions and tooltips. Use icon-only display mode unless
  a native item genuinely needs its title.
- Configure Fetch, Sync, Commit, and the branch picker as native bordered
  `NSToolbarItem`s. Keep only the busy spinner and ahead/behind status text as
  custom views. Commit uses the native count badge where the deployment OS
  provides it; its visible title remains `Commit`.
- Keep Sync in the toolbar whenever it is represented by repository state, but
  disable it when working-tree changes exist and explain that state with the
  tooltip `Commit changes before syncing`.
- Present the existing branch selector content from an `NSPopover` anchored to
  the branch `NSToolbarItem`; do not attach it to the root window content or
  duplicate the selector UI.
- Delete the now-unused `MainMenuFooterSection.swift`.

## Problem

Commit and Sync sit inside the Working Tree card, the branch picker sits in a
footer, and the toolbar holds only the sidebar toggle and Back. Sync shows as a
disabled button when there is nothing to sync.

## Scope

1. Extend `GitMenuBar/App/MainWindowToolbarController.swift` with native items
   for branch picker, ahead/behind indicator, Fetch, Sync, and Commit. Keep the
   pure state mapping in `MainWindowToolbarRepositoryState.swift`. Feed the
   items from the existing selected-repository state through `update(...)`; do
   not query Git from the controller.
2. Commit shows the change count and selects the Working Tree side panel
   (existing `MainMenuSidePanelSelection`). Sync appears only when ahead or
   behind. Fetch is always enabled while no operation runs.
3. Branch picker opens the existing `MainMenuBranchSelectorOverlay` in an
   `NSPopover` anchored to the branch toolbar item. `MainWindowController` owns
   the shared presentation state; `MainMenuView` and the toolbar share the
   existing selector content rather than maintaining duplicate UI.
4. Remove Commit/Sync from the Working Tree card
   (`RepositoryOverviewView.swift`), remove `MainMenuFooterSection` usage, and
   delete `MainMenuFooterSection.swift`.
5. Hide repository items on non-repository routes.
6. Keep command palette and keyboard shortcuts for these actions working.

## Acceptance

- Native toolbar items use short visible labels/titles (Fetch, Sync, Commit,
  and the branch name); repository-specific sentences remain in accessibility
  descriptions and tooltips (for example, "Commit 1 change in NetNewsWire").
- Commit uses a native count badge for the working-tree change count when the
  running macOS version supports `NSToolbarItem` badges.
- Sync remains visible and disabled when working-tree changes exist, with the
  tooltip "Commit changes before syncing".
- Busy state disables Fetch/Sync/Commit and shows progress in place.
- The branch selector popover is anchored to the branch toolbar item and uses
  the existing selector content.
- `MainMenuFooterSection.swift` is absent and has no remaining users.
- Focused tests for the toolbar state mapping (counts, Sync visibility).
- Matches the approved prototype and `docs/ui.md` hierarchy rules.

## Validation

- `make lint-changed`
- `make check-preview` (add or update previews for every changed view)
- `make build`
- `make test-focused TEST_FILTER='GitMenuBarTests/ToolbarStateMappingTests'`
- `git diff --check`

## STOP conditions

- An unexpected changed path outside this scope.
- A rule in `docs/ui.md` blocks the change: report it; the UI owner decides.
