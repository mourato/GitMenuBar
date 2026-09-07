# ADR 0014: Compact inspector sheet and bounded workbench columns

Status: Superseded by ADR 0015
Date: 2026-09-05

## Context

The three-surface workbench (ADR 0012, ADR 0013) clips the Projects sidebar
when the window is narrow: the window minimum undercounts split dividers, the
sidebar is fixed at 220pt, and the center/inspector minimums win the
constraint fight. Requirements now bound every column: a resizable sidebar
(max 360pt), a center pane (min 360pt, max 500pt), and a usable inspector when
the window cannot fit three columns.

## Decision

- Sidebar: `NavigationSplitView` range `min: 220, ideal: 220, max: 360`.
  Always visible while uncollapsed; only the toolbar toggle and sidebar hide
  action collapse it. Width stays session-local, like the inspector divider.
- Center: single `HSplitView` pane frame, `minWidth: 360, maxWidth: 500`
  (pane, padding included). Extra window width flows to the inspector.
- Inspector: inline `HSplitView` column while the window content width is at
  or above `compactInspectorThresholdWidth` (= three-column minimum, 940pt);
  the same `MainMenuInspectorSelection` renders in a `.sheet` below it. The
  sheet exists only while a selection exists; dismissing clears the selection.
- Mode ownership: `MainMenuPresentationModel.isInspectorCompact`, driven by
  `NSWindow` content width in `StatusBarController` (setup, frame restore,
  move/resize) with 40pt of hysteresis. SwiftUI layout never feeds this state,
  preserving the ADR 0013 no-write-back rule.
- Window minimum swaps with the mode: three-column floor normally,
  two-column floor (`mainWindowCompactMinimumWidth`, 612pt) in compact mode.
- Divider budget is honest: `splitDividerThickness` (8pt) times the two live
  dividers, folded into the minimum and initial widths.

## Consequences

- No sidebar clipping at any allowed window size; narrow windows keep sidebar
  plus center, with the inspector one click/selection away in a sheet.
- Wide windows grow the inspector, not the center (capped at 500pt).
- Resizing across the threshold never duplicates the inspector: inline column
  and sheet are mutually exclusive owners of one selection value.
- The ADR 0012 "no compact sheet fallback" rule is superseded for narrow
  windows only; the always-open inline inspector remains the wide-window
  behavior.

## Rejected or deferred

- Measuring SwiftUI layout width (`GeometryReader`/`onGeometryChange`) to
  drive the mode was rejected: toggling the column changes detail width and
  risks the layout feedback loop ADR 0013 removed.
- Persisting sidebar/center widths was deferred; both stay session-local until
  a safe AppKit-delegate seam is added, as already decided for the inspector.
- Capping center content instead of the pane was rejected per product call:
  the pane cap is what pushes wide-window space into the inspector.

## References

- [`docs/ui.md`](../ui.md)
- [`ADR 0012`](0012-always-open-inspector.md)
- [`ADR 0013`](0013-hsplitview-inspector-fallback.md)

## Affected surfaces

- `GitMenuBar/Components/Common/WorkbenchMetrics.swift`
- `GitMenuBar/App/MainMenuPresentationModel.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuContent.swift`
- `GitMenuBar/App/StatusBarController.swift`
