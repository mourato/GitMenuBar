# Plan 082: Extract MainWindowController from StatusBarController

> **Executor instructions**: Read this brief, `AGENTS.md`, and
> [project workflow facts](../../docs/agents/project-workflow.md) before editing.
> Work in a dedicated worktree. Follow the steps in order and run each
> verification command. On a STOP condition, stop and report; do not widen
> scope. Leave merge and push to the operator.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MEDIUM
- **Depends on**: Observable migration + MainMenuView decomposition (branch `observable-migration`) merged to main
- **Category**: tech-debt (item 3: god-object decomposition)
- **Planned at**: commit 9084297, 2026-10-07
- **Integration**: main; merge and push require explicit operator authorization

## Execution profile

- **Recommended profile**: Standard/full
- **Risk/lane**: MEDIUM
- **Parallelizable**: No; touches the same file as Plans 083
- **Reviewer required**: Yes
- **Rationale**: StatusBarController.swift is 1201 lines mixing status item, window lifecycle, placement, persistence, shortcuts, and command routing; window lifecycle is a cohesive AppKit responsibility with a native owner type (NSWindowController).
- **Escalate when**: Placement, dismissal, focus, or frame-restore behavior changes; a second status item or window controller appears; extraction needs a new protocol.

## Problem

`GitMenuBar/App/StatusBarController.swift` owns the `NSStatusItem` and also
the whole main-window lifecycle. Window code dominates the file and hides the
status-item and command responsibilities.

## Scope

Move into a new `MainWindowController: NSWindowController` in `GitMenuBar/App/`:

- `setupMainWindow`, `configureMainWindowAppearance`, `makeRootView`
- placement: `positionMainWindowRelativeToStatusItem`, `screenContainingMousePointer`,
  `positionMainWindow`, `fitMainWindowWidthToVisibleFrame`,
  `clampMainWindowOriginToVisibleFrame`, `normalizeMainWindowSize`,
  `WindowPlacementStrategy`
- persistence: `persistMainWindowFrame*`, `restoreMainWindowFrameIfAvailable`,
  `Constants.windowAutosaveName` (value unchanged)
- show/hide/toggle, auto-hide suspension, `handleMainWindowDidResignKey`,
  `MainWindowLifecycleDelegate`, `WindowOpenTrace` logging

Stays in `StatusBarController`: status item, context menu, shortcut handlers,
command routing, observation of stores for the status-item image. The toolbar
stays with `MainWindowToolbarController`.

Out of scope: behavior changes, SwiftUI scene migration (`Window`/`MenuBarExtra`).

## Invariants

- Exactly one `NSStatusItem` owner and one main window instance.
- Window anchors to status item, or to the screen under the pointer for shortcut opens.
- Outside-click, focus-change, and `Esc` dismissal unchanged; auto-hide suspension unchanged.
- Same `NSWindow.FrameAutosaveName`; existing saved frames restore.
- Activation policy (Dock icon preference) unchanged.

## Steps

1. Drift check: `git diff --stat <planned-commit>..HEAD -- GitMenuBar/App/StatusBarController.swift GitMenuBar/App/MainWindowToolbarController.swift`. Confirm Observable migration is merged.
2. Create `MainWindowController`; move members listed above; keep signatures `private` where possible.
3. `StatusBarController` holds one `MainWindowController` and calls `toggle`/`open`/`hide`.
4. Remove orphans created by the move only.

## Verification

- `make build`, `make lint`, `make test`
- Manual: left-click open/close; shortcut open on second monitor; resize then relaunch (frame restores); click outside dismisses; `Esc` dismisses; Settings opens; Dock-icon preference respected.

## STOP conditions

- Any invariant needs a behavior change to hold.
- Extraction requires a protocol with one implementation.

## Outcome

DONE 2026-10-08. Merged as `ea71f5f`. `StatusBarController.swift` 1251 → 897
lines; `MainWindowController` owns window lifecycle, placement, and frame
autosave. Independent review: no findings. Operator manual checks (status-item
toggle, second-monitor placement, frame restore, outside-click/`Esc`, Settings
and Dock preference) pending.
