# ADR 0010: Contextual workbench inspector

Status: Accepted
Date: 2026-09-03

## Context

GitMenuBar's main window already has a Projects sidebar and a selected-project
workbench, but central rows expose only compact state. The application needs a
place to expand a selected file, commit, branch, stash, or repository topic
without replacing the existing workbench or adding another window. The window
can be resized to a width where three surfaces no longer fit comfortably.

## Decision

Keep one optional `MainMenuInspectorSelection` on `MainMenuView`. A central
selection is the only way to present details; no selection means no inspector
or sheet. Attach the native SwiftUI inspector to the selected-project detail
owner and use the same selection with `.sheet(item:)` below the compact
threshold derived from `WorkbenchMetrics`.

The Projects sidebar remains the left navigation surface and the repository
workbench remains the center. The inspector is a trailing supplementary
surface, not a fourth navigation column. Plan 076 provides only the shell and
selection identity; later plans own repository-specific detail content and
actions. The existing history route remains intact until its planned
migration.

## Consequences

- File and history row selection can open one contextual detail surface while
  preserving the existing central selection and route behavior.
- Wide windows use a native, resizable inspector; compact windows use a
  native sheet bound to the same selection.
- Resizing across the threshold transfers presentation without changing the
  selected item or creating two overlays.
- Escape closes contextual details before other transient presentations or the
  window. Changing repositories or entering a non-main route clears details.
- The shell performs no Git query and introduces no second repository state
  owner, event bus, persistence setting, custom panel, or status-item change.

## Rejected or deferred

- A fourth `NavigationSplitView` column was rejected because it competes with
  the existing Projects/sidebar ownership and leaves too little central space.
- A custom AppKit panel or separate detail window was rejected because native
  SwiftUI presentation already provides the required trailing and compact
  behavior.
- A persistent inspector preference was deferred; contextual details should
  disappear when there is no current central selection.
- Full repository metrics, Git actions, stash state, and history drill-down
  are deferred to Plans 077–079.

## Ownership and accessibility

`MainMenuView` owns the optional selection and presentation bindings.
`MainMenuContent` owns attachment to the existing `NavigationSplitView` detail
surface and root-width measurement. `MainMenuInspectorView` owns only the
neutral shell, selection identity, close control, and its single scroll owner.
The project selection remains owned by `RepositorySelectionCoordinator`.

The close control has an explicit accessible label and native macOS hit area.
The shell exposes its selected title and stable identity to VoiceOver, uses
Workbench typography/material tokens, and provides an empty preview state.
Native materials fall back through the shared Workbench surface for reduced
transparency. Motion remains governed by the existing main-window and
secondary-surface policies.

## Reversal conditions

Revisit this decision if the deployment target no longer supports the native
inspector, the compact threshold cannot preserve one selection during resize,
the detail surface needs independent navigation state, or user research shows
that contextual selection is insufficient for the repository workflows. Any
replacement must preserve one presentation owner and update `docs/ui.md` plus
this ADR's historical status.

## References

- [`docs/ui.md`](../ui.md)
- [`ADR 0002`](0002-window-shell-material-and-titlebar-chrome.md)
- [`ADR 0009`](0009-path-bound-git-operations.md)

## Affected surfaces

- `GitMenuBar/Pages/MainMenu/MainMenuView.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuContent.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuInspectorView.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuInteractionModels.swift`
- `GitMenuBar/Components/Common/WorkbenchMetrics.swift`
