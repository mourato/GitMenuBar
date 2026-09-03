# ADR 0011: Commit workspace in the inspector

Status: Accepted
Date: 2026-09-03

## Context

The commit composer and the Staged/Unstaged file lists lived in the center
column, while commit history lived in the inspector. The center column carried
three jobs at once — repository navigation (overview), file staging, and
committing — and the stage → commit → review-history flow was split across
two surfaces.

## Decision

The Working Tree inspector selection hosts the unified commit workspace,
ordered composer → working tree → history:

- The commit composer (Commit, Commit & Push, Split into atomic commits) is
  fixed above the workspace's single scroll owner.
- Staged/Unstaged lists and the history timeline share that one scroll owner
  below the composer.
- The center column keeps only the repository overview and the branch footer;
  overview cards remain the navigation into the inspector.

The workspace stays selection-gated per ADR 0010: no selection means no
inspector. File selection inside the workspace still drills into the existing
file-detail surface, history restore keeps its destructive confirmation, and
keyboard navigation is unchanged (the render snapshot still feeds the
selectable items).

## Consequences

- One surface owns the full commit flow; the center returns to being a
  navigation surface.
- The composer exists in exactly one place, so commit-field focus and the
  whitespace/rewrite dialogs keep a single owner.
- Opening a commit from workspace history drills into the existing commit
  surface; Back returns to the standalone history surface, not the workspace.
- `docs/ui.md` composition now describes the center as toolbar → overview →
  footer with the workspace in the inspector.

## Rejected or deferred

- Keeping the composer in both center and inspector was rejected: duplicated
  focus state and two competing scroll owners for one workflow.
- A persistent (selection-independent) inspector was rejected; ADR 0010 stands
  and the workspace closes with the selection on Escape.
- Merging the standalone history/commit surfaces into the workspace is
  deferred; the workspace embeds the history list and reuses the existing
  drill-down.

## Ownership and accessibility

`InspectorCommitWorkspaceView` owns the workspace composition; its previews
live alongside (`MainMenuInspectorView+Preview.swift` covers the inspector
shell). Workbench tokens, hit targets, VoiceOver labels, and reduced-motion
behavior follow the existing workbench policies.

## References

- [`docs/ui.md`](../ui.md)
- [`ADR 0010`](0010-contextual-workbench-inspector.md)

## Affected surfaces

- `GitMenuBar/Pages/MainMenu/InspectorCommitWorkspaceView.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuInspectorView.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuInspectorView+Preview.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuContent.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuComputed.swift`
- `docs/ui.md`
