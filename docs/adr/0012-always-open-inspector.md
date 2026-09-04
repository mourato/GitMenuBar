# ADR 0012: Always-open workbench inspector

Status: Accepted
Date: 2026-09-03

## Context

The workbench inspector currently appears only after a central selection and
uses a sheet below a compact-width threshold. The main window now treats the
inspector as a primary work surface: the Working Tree entry exposes the commit
workspace and its history, while the center remains the repository overview.

## Decision

Keep the native SwiftUI `.inspector` attached to the selected-project detail
surface, but present it permanently in the main route. When there is no
selection, the inspector renders its existing empty state rather than
disappearing. Remove the compact sheet fallback and the inspector close
control; Escape clears contextual selection but does not close the column.

Use the native inspector divider for resizing. Start new windows with
`WorkbenchMetrics.inspectorDefaultWidth` large enough for the inspector to be
the largest column, while retaining the existing minimum widths for the
Projects sidebar, center, and inspector. Save the measured inspector width in
`UserDefaults.standard` under the stable
`AppPreferences.Keys.inspectorColumnWidth` key. A missing or undersized value
falls back to the default/minimum, and the key is not versioned so it survives
app updates. The existing stable `NSWindow.FrameAutosaveName` continues to
persist the window frame.

## Consequences

- The three-surface workbench is visible together on macOS.
- The inspector has a useful empty state before a repository or central item is
  selected.
- User resizing survives relaunches and app updates without a migration table.
- The native split view remains responsible for hit targets, divider behavior,
  keyboard focus, and platform appearance.

## Rejected or deferred

- A custom drag handle or AppKit split-view bridge was rejected; the native
  inspector already supplies resizable columns.
- A versioned preference namespace was rejected; the width is layout state and
  the stable app preference key should survive compatible app updates.
- A default inspector selection was deferred; an empty inspector is clearer
  when no repository or central item is selected.

## Ownership and accessibility

`MainMenuContent` owns permanent inspector presentation and records the
measured column width. `MainMenuView` owns the persisted preference,
`WorkbenchMetrics` owns the width defaults and minimums, and
`StatusBarController` owns the window's initial and minimum sizes. The empty
state remains exposed to VoiceOver, and removing the close control avoids
offering an action that cannot close the always-open surface.

## References

- [`docs/ui.md`](../ui.md)
- [`ADR 0010`](0010-contextual-workbench-inspector.md)
- [`ADR 0011`](0011-commit-workspace-in-inspector.md)

## Affected surfaces

- `GitMenuBar/App/StatusBarController.swift`
- `GitMenuBar/Components/Common/WorkbenchMetrics.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuContent.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuInspectorView.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuView.swift`
- `GitMenuBar/Services/Persistence/AppPreferences.swift`
