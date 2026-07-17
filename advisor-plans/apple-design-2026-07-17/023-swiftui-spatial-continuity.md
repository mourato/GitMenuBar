# Plan 023: Restore SwiftUI route and origin continuity

> **Executor instructions**: Execute only after plans 016–020 are complete and
> plan 021 is stable. This plan changes shared menu presentation behavior; use a
> new isolated worktree and stop on drift.
>
> **Drift check**: `git diff --stat e9be124..HEAD -- GitMenuBar/Pages/MainMenu GitMenuBar/Components/Common/MainMenuHeaderView.swift GitMenuBar/Components/Projects/ProjectSelectorPopover.swift GitMenuBar/Components/Common/RepositoryOptionsPopoverView.swift GitMenuBar/Components/History`

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: 021; plans 016–020 complete
- **Category**: dx
- **Planned at**: commit `e9be124`, 2026-07-17

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: no; route, overlay, and origin transitions must be evaluated together
- **Reviewer required**: yes; visual continuity and accessibility behavior require manual inspection
- **Rationale**: the state changes are local, but incorrect transition pairing can make navigation feel directional in the wrong way or trap focus
- **Escalate when**: a new navigation architecture, custom popover controller, or persistent route state is proposed

## Why this matters

The route switch uses different insertion transitions for create-repository,
main, and history-detail views without an explicit reversible mapping. The
project button has a `matchedGeometryEffect`, but the popover destination does
not participate. The command palette also appears as a conditional overlay
without materialized entry/exit behavior or a Reduce Transparency fallback.

## Current state

- `MainMenuView.swift:128-157` applies bottom, opacity-only, and trailing
  transitions directly to route cases.
- `MainMenuView.swift:160-161` applies one raw spring to the route container.
- `MainMenuHeaderView.swift:60` is the only side of the
  `projectSelector` matched-geometry pair.
- `ProjectSelectorPopover.swift:48-49` uses `macPanelSurface` but has no
  namespace or matching ID.
- `MainMenuOverlays.swift:34-57` conditionally inserts the command palette and
  uses `.ultraThinMaterial` for the scrim without checking Reduce Transparency.
- `CommitDetailPageView.swift:128` and
  `HistoryTimelineSectionView.swift:114` already form a working commit-title
  matched-geometry pair; preserve it.

## Commands

| Purpose | Command | Expected |
|---|---|---|
| Agent loop | `make agent-check` | lint and Debug build pass |
| Merge gate | `make lint && make test` | both commands pass |
| Guidance | `make guidance-check` | validation passes |

## Scope

In scope:

- `GitMenuBar/Pages/MainMenu/MainMenuView.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift`
- `GitMenuBar/Components/Common/MainMenuHeaderView.swift`
- `GitMenuBar/Components/Projects/ProjectSelectorPopover.swift`
- `GitMenuBar/Components/Common/RepositoryOptionsPopoverView.swift`
- `GitMenuBar/Components/History/CommitDetailPageView.swift` and
  `HistoryTimelineSectionView.swift` only for continuity validation or a
  minimal correction to the existing pair

Out of scope:

- Branch/worktree management UI from plans 016–020.
- AppKit `NSWindow` alpha lifecycle; plan 022 owns it.
- New navigation architecture or persistent animation state.

## Steps

### Step 1: Define reversible route transitions

Create a small route-transition mapping that uses the shared `route` token and
has a deliberate insertion/removal direction for each route. The path from
main to history detail and back must be spatially coherent; the create-repo
flow must return through the same edge it entered. Under Reduce Motion, use an
opacity/static equivalent.

Keep the container slot stable and animate compositor-friendly properties. Do
not animate frame size and internal controls at the same time without a
preview demonstrating the relationship.

**Verify**: `rg -n "transition|animation" GitMenuBar/Pages/MainMenu/MainMenuView.swift` shows the shared route mapping; `make agent-check` passes.

### Step 2: Materialize the command palette overlay

Add symmetric entry/removal behavior for the palette and scrim. Respect Reduce
Transparency with an opaque system background fallback. Respect Reduce Motion
with opacity/static feedback. Keep the palette modal trait, outside-tap close,
keyboard monitor, and focus behavior unchanged.

**Verify**: `make agent-check` passes; preview/runtime inspection confirms the palette never reveals the live desktop between transitions.

### Step 3: Resolve popover origin continuity honestly

Either pass a stable namespace and matching ID into the project-selector
destination, or remove the source-only `matchedGeometryEffect` and use the
native popover anchor plus a consistent pressed/hover state. Do not add a
cross-host matched-geometry effect without verifying that the actual AppKit
popover host animates it. Apply the same decision to repository options.

**Verify**: relevant previews and manual popover inspection show an anchored,
non-jumping presentation in Light/Dark and Reduce Motion; `make lint && make test` passes.

## Test plan

- Exercise main → history detail → main.
- Exercise main → create repository → main.
- Open/close command palette with mouse, Escape, and keyboard shortcut.
- Open project and repository-options popovers repeatedly while moving the
  pointer; verify focus and dismissal remain native.
- Verify VoiceOver/keyboard focus remains clear without motion.

## Done criteria

- [ ] Every route has a documented reversible path.
- [ ] Command palette entry/exit is symmetric and adaptive.
- [ ] Command palette has a Reduce Transparency fallback.
- [ ] Project/repository popover origin treatment is anchored and verified.
- [ ] Existing commit timeline/detail matched geometry remains intact.
- [ ] `make agent-check` and `make lint && make test` pass.
- [ ] No worktree/branch files are modified.

## STOP conditions

- The source excerpts no longer match after plans 016–020.
- A matched-geometry effect crosses an AppKit host boundary and visibly jumps.
- Keyboard focus, Escape dismissal, or VoiceOver order regresses.
- A route transition requires changing `MainMenuPresentationModel` semantics.

## Maintenance notes

Future routes must specify their origin, insertion edge, removal edge, Reduce
Motion equivalent, and whether the transition is interruptible before adding a
new `.transition` call.

