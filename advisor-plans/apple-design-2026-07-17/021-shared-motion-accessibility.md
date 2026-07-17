# Plan 021: Establish shared motion and accessibility primitives

> **Executor instructions**: This plan is advisory and intentionally deferred
> until plans 016–020 are complete. Follow the coordination rule in the local
> Apple Design plan index. Do not edit source from the active worktree for plan
> 016. Stop and report instead of improvising when a drift or STOP condition is
> found.
>
> **Drift check**: `git diff --stat e9be124..HEAD -- GitMenuBar/Components/Common GitMenuBar/Pages/MainMenu/MainMenuView.swift`
> If any listed file changed after this plan's baseline, compare the excerpts
> below and stop on a mismatch.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans 016–020 complete; no Apple Design plan dependency
- **Category**: dx
- **Planned at**: commit `e9be124`, 2026-07-17

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: no; this establishes the shared contract used by later UI plans
- **Reviewer required**: no; the scope is a shared SwiftUI styling primitive without persistence or destructive behavior
- **Rationale**: the change is bounded but affects every future motion decision and accessibility fallback
- **Escalate when**: the implementation needs AppKit lifecycle changes, new persisted settings, or changes to Git/worktree UI

## Why this matters

The repository has the motion values documented in
`.agents/skills/apple-design/references/gitmenubar-motion.md`, but the source
does not expose those values as shared tokens. `AdaptiveMotionModifier` also
disables animations globally under Reduce Motion instead of supplying a useful
cross-fade/static equivalent. This plan creates one source of truth before
individual surfaces are updated.

## Current state

- `GitMenuBar/Components/Common/MacChromeMetrics.swift:6-31` defines both a
  `PressableButtonStyle` and a second `pressable()` gesture modifier with the
  same spring values.
- `MacChromeMetrics.swift:36-46` sets `transaction.animation = nil` and
  `transaction.disablesAnimations = true` when Reduce Motion is enabled.
- `MainMenuView.swift:160-161` applies that modifier at the root and then adds a
  raw route spring.
- `MacPanelSurface.swift:13-35` already has a correct Reduce Transparency
  fallback and should remain the exemplar for adaptive surfaces.

## Commands

| Purpose | Command | Expected |
|---|---|---|
| Agent loop | `make agent-check` | lint and Debug build pass |
| Merge gate | `make lint && make test` | both commands pass |
| Guidance | `make guidance-check` | validation passes |

## Scope

In scope:

- `GitMenuBar/Components/Common/MacChromeMetrics.swift`
- `GitMenuBar/Components/Common/MacPanelSurface.swift` only if the shared
  adaptive-surface contract needs a small correction
- A new `GitMenuBar/Components/Common/MacChromeMotion.swift` only if keeping
  motion tokens separate improves ownership
- `GitMenuBar/Pages/MainMenu/MainMenuView.swift`
- `GitMenuBar/Pages/MainMenu/WorkingTreeSectionView.swift`
- `GitMenuBar/Pages/MainMenu/HistorySectionView.swift`
- `GitMenuBar/Components/History/HistorySectionHeaderView.swift`
- `GitMenuBar/Components/WorkingTree/WorkingTreeSectionHeaderView.swift`
- `GitMenuBarTests/MainMenuCommandPaletteResolverTests.swift` and
  `GitMenuBar/Pages/Settings/SettingsPage.swift`, limited to the existing
  SwiftFormat `wrapIfStatementBodies` violations exposed by the full merge
  gate; these changes are mechanical and have no behavior change.
- `GitMenuBar/Pages/MainMenu/ConfirmationDialogsModifier.swift`, limited to a
  local SwiftLint `function_parameter_count` suppression required by the full
  merge gate; this change is mechanical and has no behavior change.
- Relevant previews or a small pure helper test if a deterministic seam is
  introduced

Out of scope:

- AppKit window presentation; plan 022 owns it.
- Directional route design, command-palette presentation, and popover origin
  continuity; plan 023 owns those refinements. This plan only supplies the
  Reduce Motion opacity/static boundary required by existing transitions.
- Worktree/branch source files touched by plans 016–020.
- Product redesign or new animation types not present in the motion reference.

## Steps

### Step 1: Add the shared motion tokens

Expose `micro`, `arrive`, `settle`, `swap`, `press`, and `route` using the exact
defaults from the GitMenuBar motion reference. Keep ordinary UI critically
damped and reserve bounce for deliberate momentum/arrival. Name the API so
call sites cannot accidentally use the route token for a microinteraction.

**Verify**: `rg -n "micro|arrive|settle|swap|press|route" GitMenuBar/Components/Common` shows one canonical definition for each token; `make agent-check` passes.

### Step 2: Replace global animation suppression

Refactor `adaptiveMotion()` so Reduce Motion produces opacity/color/static
feedback rather than removing all feedback. Preserve the existing public
modifier name if possible, but do not set `disablesAnimations` for the entire
subtree. Add a small shared transition/animation resolver if that is the
cleanest way for later plans to choose the non-vestibular equivalent.

**Verify**: `rg -n "disablesAnimations|transaction\.animation = nil" GitMenuBar/Components/Common/MacChromeMetrics.swift` returns no global suppression path; `make agent-check` passes.

### Step 3: Consolidate press ownership

Choose one shared press-feedback implementation. If the gesture modifier is
retained for rows, document why it is separate from `PressableButtonStyle`; if
the button style is the canonical path, remove the unused duplicate only after
all call sites are migrated. Keep layout bounds stable and use the shared
`press` token.

**Verify**: `rg -n "PressableButtonStyle|pressable\(" GitMenuBar` shows intentional production call sites and no orphan helper; `make lint && make test` passes.

## Test plan

- Use existing SwiftUI previews for the shared press and panel components.
- Exercise previews with Reduce Motion and Reduce Transparency enabled.
- Confirm no state change loses status/completion feedback when Reduce Motion is
  active.
- No business-logic test is required unless a pure resolver is introduced; if
  one is introduced, place its test in `GitMenuBarTests` and keep it platform
  independent.

## Done criteria

- [x] All six project motion tokens have one canonical source.
- [x] Reduce Motion retains useful opacity/color/static feedback.
- [x] No global `disablesAnimations` suppression remains in the shared modifier.
- [x] Press feedback has one documented ownership model.
- [x] `make agent-check` passes.
- [x] `make lint && make test` passes.
- [x] No files outside the scope are modified.
- [x] The executor updates this index only after the implementation, review,
  and merge-gate evidence are complete.

## STOP conditions

- Plans 016–020 are not complete or their changes are not merged/reconciled.
- A cited excerpt no longer matches the source.
- Reduce Motion cannot be represented without changing AppKit lifecycle code.
- The implementation requires changing a branch/worktree component.

## Maintenance notes

Later plans must use these tokens instead of introducing raw durations. Any
deliberate exception must be documented at the call site with the interaction
context and accessibility behavior.
