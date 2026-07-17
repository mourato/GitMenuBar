# Plan 025: Finish adaptive surfaces, typography, haptics, and sanitization

> **Executor instructions**: Execute last, after plans 021–024 and the active
> worktree sequence 016–020 are complete. Use a new isolated worktree. This is
> a cleanup plan only after the preceding plans establish final ownership; do
> not use it to redesign unrelated screens.
>
> **Drift check**: `git diff --stat e9be124..HEAD -- GitMenuBar/Components/Common GitMenuBar/Components/History GitMenuBar/Components/AI GitMenuBar/Components/Projects GitMenuBar/Pages/Settings GitMenuBar/Pages/MainMenu GitMenuBar/App`

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: 021, 022, 023, 024; plans 016–020 complete
- **Category**: tech-debt
- **Planned at**: commit `e9be124`, 2026-07-17

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: no; surface, typography, haptic, and dead-code decisions affect shared visual ownership
- **Reviewer required**: yes; final review must inspect accessibility, material hierarchy, and removal evidence
- **Rationale**: each individual edit is small, but the plan removes orphaned UI and standardizes several cross-cutting visual contracts
- **Escalate when**: a component is discovered to be used by the worktree feature, a public API changes, or a haptic requires new persistence/device state

## Why this matters

The code has adaptive materials in some shared surfaces but several direct
materials and opaque backgrounds ignore Reduce Transparency. Typography uses
system styles in many places, but tracking and scaled spacing are not actually
adopted. Haptic semantics are inconsistent, and the review found orphaned
helpers/components that make the design system appear more complete than its
runtime wiring.

## Current state

- `MacPanelSurface.swift:13-35` is the correct Reduce Transparency pattern, but
  no caller passes an explicit `.thin` or `.thick` material weight.
- `InlineStatusBannerView.swift:48-52`, `MainMenuHeaderView.swift:107`, and
  `CommitHoverCardView.swift:22-30` use materials outside the shared fallback.
- `MacChromeMetrics.swift:100-112` defines tracking but no production call site
  uses it; there is no `@ScaledMetric` or `.dynamicTypeSize` usage.
- `MainMenuActions.swift:55-60` uses generic haptic feedback for failure,
  while `AppCommandCenter.swift:216-220` still uses `NSSound.beep()` for a
  disabled command.
- `CommitHoverCardView` has only its declaration and preview as call sites.
  Confirm this with `rg -n "CommitHoverCardView" GitMenuBar` before removing it.

## Commands

| Purpose | Command | Expected |
|---|---|---|
| Search/adoption evidence | `rg -n "CommitHoverCardView|MacChromeTypography\.tracking|material:" GitMenuBar` | results match intentional runtime usage |
| Agent loop | `make agent-check` | lint and Debug build pass |
| Merge gate | `make lint && make test` | both commands pass |
| Guidance | `make guidance-check` | validation passes |

## Scope

In scope:

- `GitMenuBar/Components/Common/MacPanelSurface.swift`
- `GitMenuBar/Components/Common/InlineStatusBannerView.swift`
- `GitMenuBar/Components/Common/HapticFeedback.swift`
- `GitMenuBar/Components/History/CommitHoverCardView.swift` only if it is
  confirmed unused, otherwise wire it through its real hover path
- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift`
- `GitMenuBar/App/AppCommandCenter.swift` only for consistent disabled-command
  feedback
- Current UI call sites that use fixed typography/spacing, with previews
  updated for accessibility text sizes

Out of scope:

- New product features or a full visual redesign.
- Credential, Git, worktree, or network behavior.
- Removing UI based only on a name search; every removal needs target-wiring
  evidence and a successful build.

## Steps

### Step 1: Complete adaptive surface ownership

Route translucent surfaces through the shared adaptive fallback. Choose material
weight by hierarchy: lighter for small interactive chrome, regular for normal
panels, and thick only for raised/dense cards. Add contrast-aware borders where
the surface would otherwise rely only on blur. Avoid stacking light materials
over one another.

**Verify**: every production `thinMaterial`, `regularMaterial`, or
`thickMaterial` call in scope either uses the shared fallback or documents its
platform reason; `make agent-check` passes.

### Step 2: Adopt Dynamic Type and tracking deliberately

Keep system text styles, replace any remaining fixed-size UI typography in the
scope, and apply tracking only where the typography context justifies it. Use
`@ScaledMetric` for spacing/icon sizes coupled to text. Add preview variants at
large accessibility text sizes and ensure long paths/messages wrap or truncate
without clipping controls.

**Verify**: `rg -n "\.system\(size:|ScaledMetric|dynamicTypeSize|\.tracking\(" GitMenuBar/Components GitMenuBar/Pages` shows no unreviewed fixed-size text and shows exercised adaptive paths; `make lint && make test` passes.

### Step 3: Align haptic and sound semantics

Make the haptic helper safe on unsupported hardware. Use success/level-change
feedback only for meaningful completion, warning feedback for meaningful
failure, and no feedback for routine state churn. For disabled commands,
choose a consistent keyboard-appropriate fallback and document why sound or
haptic is used; do not fire both for the same event. Fire feedback in the same
causal callback as the visual state change.

**Verify**: `rg -n "HapticFeedback|NSSound\.beep" GitMenuBar` shows intentional
call sites with no duplicate feedback path; `make agent-check` passes.

### Step 4: Sanitize orphaned UI and helpers

For `CommitHoverCardView`, first prove whether production wiring exists. If it
is unused, remove the orphan source and preview safely; if it is intended,
wire it through the actual hover path and add its adaptive surface behavior.
Apply the same evidence-driven decision to unused typography/material helpers.
Do not remove any component referenced by plans 016–020 without reconciling
those plans first.

**Verify**: `rg -n "CommitHoverCardView|PressableButtonStyle|MacChromeTypography\.tracking" GitMenuBar` returns only intentional definitions/usages; `make lint && make test` passes.

## Test plan

- Preview Light/Dark, increased contrast, Reduce Transparency, Reduce Motion,
  and large accessibility text sizes.
- Verify status banner, project/header surfaces, commit detail/history, and
  settings panes for contrast, wrapping, and focus order.
- Verify successful commit/sync, failed sync, stage/unstage, and disabled
  commands for feedback causality and non-duplication.
- If an orphan component is removed, confirm the full build has no missing
  target references.

## Done criteria

- [ ] All translucent production surfaces have an explicit adaptive fallback.
- [ ] Material weights reflect hierarchy and are actually exercised.
- [ ] Typography adapts to large text without clipping or fixed-size regressions.
- [ ] Tracking/scaled metrics are either used intentionally or removed.
- [ ] Haptic/sound feedback is semantic, causal, and non-duplicated.
- [ ] Orphaned components/helpers are removed only with `rg`/target evidence.
- [ ] `make agent-check`, `make lint && make test`, and `make guidance-check` pass.
- [ ] No files from the active worktree sequence are modified unexpectedly.

## STOP conditions

- A surface belongs to the worktree feature and its ownership is unclear.
- A typography change clips a control at accessibility text sizes.
- A haptic API behaves differently on supported hardware than expected.
- Removal evidence is incomplete or the build target still references the file.

## Maintenance notes

Every new material surface must state its Reduce Transparency fallback. Every
new haptic must name the causal event and why it deserves feedback. Keep dead
code cleanup in the same change as the abstraction that made it obsolete.

