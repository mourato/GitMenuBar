# Plan 001: Selected history row keeps its title

## Status

- **Priority**: P1 (visible bug)
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Planned at**: commit `fa92af4`, 2026-10-29

## Execution profile

- **Recommended profile**: `implementer-fast`
- **Suggested executor**: OpenCode free model
- **Risk/lane**: `Low/Fast`
- **Parallelizable**: yes, with 002
- **Reviewer required**: no; author diff review is enough
- **Escalate when**: the fix needs changes outside the two files below

## Problem

When a commit is open in the side panel, its history row shows only the dot.
The title disappears.

Root cause: two views use the same `matchedGeometryEffect` id
`"commit-\(commit.id)"` in the same namespace, and both are on screen at once:

- `GitMenuBar/Components/History/HistoryTimelineSectionView.swift:270` (row title)
- `GitMenuBar/Components/History/CommitDetailPageView.swift:108` (detail title)

Both default to `isSource: true`. SwiftUI keeps one and hides the other.

## Change

1. Remove `.matchedGeometryEffect` from the detail title in
   `CommitDetailPageView.titleSection`. The row and the panel are visible at
   the same time, so there is no hero transition to keep.
2. Keep the row modifier only if other code still animates with it. If no
   other view uses the id, remove it from the row too, and remove the
   `animationNamespace` parameter only where it becomes unused. Do not widen
   the change beyond orphans this edit creates.
3. Selected row style: keep `WorkbenchPalette.selectedFill()`. The title must
   stay readable in light, dark, and Increase Contrast.

## Acceptance

- Open any commit: its row still shows title, hash, and time.
- Switching commits updates the selection without flicker.
- No `matchedGeometryEffect` id is used by two visible views.

## Evidence for UI review

Follow "UI review rubric and evidence" in `README.md`. Hand off the list of
`#Preview` names and the screenshot paths.

## Validation

- `make check-preview`
- `make lint-changed`
- Manual: open 3 commits in a row, with Reduce Motion on and off.
