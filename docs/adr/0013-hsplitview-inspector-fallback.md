# ADR 0013: HSplitView fallback for the always-open inspector

Status: Accepted
Date: 2026-09-04

## Context

The permanent SwiftUI `.inspector` attached to the workbench
`NavigationSplitView` repeatedly invalidated AppKit window constraints on
macOS 27. The application crashed in
`NSWindow._postWindowNeedsUpdateConstraints` even after the earlier geometry
feedback loop was removed. The failure reproduced with both the saved
inspector width and a safe minimum width, while the same workbench stayed
alive when the `.inspector` modifier was removed.

The workbench still needs three visible surfaces, a resizable inspector, and
the existing Projects sidebar behavior.

## Decision

Keep `NavigationSplitView` as the outer container so it continues to own the
Projects sidebar's selection, visibility, and collapse behavior. Compose the
center route and always-open inspector with a native SwiftUI `HSplitView` in
the detail column.

Use `WorkbenchMetrics.inspectorMinimumWidth` and
`WorkbenchMetrics.inspectorDefaultWidth` for the inspector's minimum and ideal
width. Read the legacy `inspectorColumnWidth` preference only for the initial
ideal width. Do not write measured geometry from SwiftUI layout back to state
or `UserDefaults`; a future persistence implementation must use an AppKit
split-view delegate or another non-layout feedback seam.

## Consequences

- The three-surface workbench remains visible on macOS.
- The inspector keeps its empty state and existing selection ownership.
- The native HSplitView divider remains resizable.
- Divider resizing is session-local until a safe persistence seam is added.
- The macOS 27 `.inspector` constraint crash is avoided by removing that
  modifier from the workbench composition.

## Rejected or deferred

- Keeping `.inspector` with a smaller or clamped ideal width was rejected: the
  crash reproduced with the minimum width as well.
- Reintroducing an `onGeometryChange` callback that updates SwiftUI state was
  rejected because it recreates the original layout feedback loop.
- An AppKit `NSSplitView` bridge was deferred; `HSplitView` supplies the
  required divider with less code.

## References

- [Apple Developer Forums: macOS inspector constraint crash](https://developer.apple.com/forums/thread/801818)
- [`docs/ui.md`](../ui.md)
- [`ADR 0012`](0012-always-open-inspector.md)

## Affected surfaces

- `GitMenuBar/Pages/MainMenu/MainMenuContent.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuView.swift`
- `GitMenuBar/App/MainWindowPreferences.swift`
