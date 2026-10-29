# ADR 0021: Side panel as a split column

Status: Accepted
Date: 2026-10-29
Supersedes: the overlay and outside-tap parts of ADR 0017

## Context

The trailing side panel drew over the detail column. With a commit open, it
covered the history rows' short hash and time, cut the overview cards, and
sat under the toolbar's trailing actions. The open commit's row also lost its
title because the row and the panel shared one matched-geometry id while both
were visible.

## Decision

- The side panel is a trailing column beside the detail content, not an
  overlay. The detail content shrinks; nothing is covered.
- The panel keeps the fixed `WorkbenchMetrics.sidePanelWidth` (360pt) and is
  present only while a `MainMenuSidePanelSelection` exists.
- The panel is an inline surface: `WorkbenchMetrics.largeCornerRadius`, neutral
  border, quiet tint, no shadow. Its top aligns with the detail content below
  the toolbar.
- Outside tap no longer closes the panel, because clicks in the detail column
  must stay usable (for example, opening another commit). Close control and
  Escape remain.
- `WorkbenchMetrics.mainWindowMinimumWidth` becomes the three-column floor:
  Projects minimum + center minimum + side panel + window insets + divider +
  section gap.
- History rows show subject, short hash, and time. Author moves to the commit
  details.

## Consequences

The minimum window width grows to about 984pt. The history list and the open
commit are visible together, so selection works as list-to-detail navigation.

## Rejected or deferred

- Overlay with hidden row metadata while open: hides context the user needs.
- Resizable or persisted panel width: still deferred (ADR 0017).

## Affected surfaces

- `GitMenuBar/Components/Common/SidePanel.swift`
- `GitMenuBar/Components/Common/WorkbenchMetrics.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuShellView.swift`
- `GitMenuBar/Components/History/*`
- `docs/ui.md`
