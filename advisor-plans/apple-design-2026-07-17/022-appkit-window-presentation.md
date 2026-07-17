# Plan 022: Animate AppKit main-window presentation safely

> **Executor instructions**: Execute only after plans 016–020 are complete and
> plan 021 has landed or been explicitly rejected. Work in a new isolated
> worktree, never in `/Users/usuario/Documents/Projects/gitmenubar-worktrees/016`.
> Stop on drift or any lifecycle regression.
>
> **Drift check**: `git diff --stat e9be124..HEAD -- GitMenuBar/App/StatusBarController.swift GitMenuBarTests`

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: 021; plans 016–020 complete
- **Category**: bug
- **Planned at**: commit `e9be124`, 2026-07-17

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: no; presentation and dismissal must remain one interruptible lifecycle
- **Reviewer required**: yes; this changes menu-bar activation, auto-hide, and window dismissal behavior
- **Rationale**: the implementation is localized but lifecycle regressions can strand or reveal the window unexpectedly
- **Escalate when**: a new window controller, status-item ownership change, persistence change, or custom event monitor is required

## Why this matters

The motion reference requires AppKit panels to fade in and to order out only
after the fade completes. GitMenuBar currently calls `makeKeyAndOrderFront` and
`orderOut` immediately, so the main surface appears/disappears as a hard cut and
does not preserve continuity from the status item.

## Current state

- `StatusBarController.swift:519-545` positions the main window, activates the
  app, and calls `makeKeyAndOrderFront(nil)` without a presentation animation.
- `StatusBarController.swift:594-598` persists the frame and calls
  `mainWindow.orderOut(nil)` immediately.
- `windowShouldClose` delegates to `hideMainWindow`, so close-button, blur, and
  status-item dismissal share this path.
- `StatusBarController` is `@MainActor`; preserve that isolation and existing
  status-item ownership.

## Commands

| Purpose | Command | Expected |
|---|---|---|
| Agent loop | `make agent-check` | lint and Debug build pass |
| Merge gate | `make lint && make test` | both commands pass |

## Scope

In scope:

- `GitMenuBar/App/StatusBarController.swift`
- `GitMenuBarTests` only if a deterministic lifecycle seam can be tested without
  launching a real desktop window
- `plans` index only in the executor's isolated branch, not this advisor index

Out of scope:

- Status-item click routing or ownership.
- Settings-window presentation.
- SwiftUI route and command-palette transitions; plan 023 owns them.
- Changing auto-hide preferences or repository refresh timing.

## Steps

### Step 1: Introduce an interruptible presentation state

Add the smallest private state needed to distinguish opening, visible, and
closing. Opening must position the window first, then activate and animate its
alpha to `1`. Closing must animate from the current visible alpha and call
`orderOut` only in the completion callback. Reset alpha to the opening value
after the window is ordered out.

Use AppKit animation APIs and keep repeated toggles safe: a new open/close must
not queue a stale completion that orders out a newly reopened window.

**Verify**: `make agent-check` passes; repeated open/close calls do not leave `mainWindow.isVisible` inconsistent in any added seam test.

### Step 2: Add the Reduce Motion path

Read the platform accessibility setting through the supported AppKit API. When
Reduce Motion is enabled, use an immediate or very short opacity change with
the same lifecycle ordering; do not expose the desktop between transitions.
If the SDK API differs from the assumption, stop and report rather than adding
machine-specific state or polling.

**Verify**: `rg -n "reduce|alphaValue|orderOut" GitMenuBar/App/StatusBarController.swift` shows both normal and reduced-motion paths; `make agent-check` passes.

### Step 3: Preserve existing dismissal semantics

Manually verify status-item toggle, close button, auto-hide-on-blur, attached
sheets, keyboard shortcuts, and programmatic action feedback. A sheet must not
be ordered out or detached by the fade implementation.

**Verify**: `make lint && make test` passes and the manual sign-off checklist is recorded in the task.

## Test plan

- Add pure state/completion tests only if the animation lifecycle is extracted
  behind a deterministic seam.
- Otherwise rely on the existing test suite plus manual AppKit verification;
  do not create flaky timing tests based on real animation sleeps.
- Verify normal motion, Reduce Motion, reopening during fade, and dismissal with
  an attached sheet.

## Done criteria

- [ ] Main window fades in after positioning.
- [ ] Main window orders out only after the close fade completes.
- [ ] Reopening during a close cannot be invalidated by a stale completion.
- [ ] Reduce Motion has a non-vestibular path.
- [ ] Existing auto-hide, sheet, shortcut, and status-item behavior is preserved.
- [ ] `make agent-check` passes.
- [ ] `make lint && make test` passes.
- [ ] No unrelated files are modified.

## STOP conditions

- A fade causes a sheet to disappear, a new window to be ordered out, or the
  status item to stop responding.
- AppKit does not expose the required accessibility signal in the deployment
  SDK without introducing polling.
- The fix requires changing status-item event routing.

## Maintenance notes

Keep capture/overlay synchronization paths unanimated if they are introduced
later. Any new AppKit panel should reuse this lifecycle contract rather than
calling `orderOut` from an animation-independent callback.

