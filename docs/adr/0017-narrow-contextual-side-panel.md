# ADR 0017: Narrow contextual side panel

Status: Accepted
Date: 2026-09-08

## Context

ADR 0015 replaced the permanent inspector with a contextual trailing side
panel, but its fixed 560pt width consumed more of the workbench than the
detail content requires. The Working Tree, history, and branch surfaces fit
within a 360pt panel while leaving more of the repository overview visible.

## Decision

- Keep the selection-gated trailing side panel overlay hosted on the detail
  column.
- Set the fixed width through `WorkbenchMetrics.sidePanelWidth` to 360pt.
- Keep the width non-persisted and non-resizable; the legacy
  `inspectorColumnWidth` preference remains unused.
- Preserve the existing close, Escape, outside-tap, Working Tree, motion, and
  accessibility behavior from ADR 0015.

## Consequences

The side panel uses less horizontal space while retaining one shared width
token for its content views and previews. The main window's initial width also
shrinks because it is derived from that token.

## Rejected or deferred

- A resizable or persisted panel width remains deferred; the fixed token keeps
  layout behavior predictable.

## Affected surfaces

- `GitMenuBar/Components/Common/WorkbenchMetrics.swift`
- `GitMenuBar/Components/Common/SidePanel.swift`
- `GitMenuBar/Pages/MainMenu/*SidePanel*`
- `docs/ui.md`
