# Plan 002: Side panel as a split column and window minimum width

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Planned at**: commit `fa92af4`, 2026-10-29

## Execution profile

- **Recommended profile**: `implementer`
- **Suggested executor**: Codex `gpt-5.6-luna`, reasoning `xhigh`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: yes, with 001; 003, 004, 005 wait for this plan
- **Reviewer required**: yes; check every side-panel selection, focus, `Esc`
- **Escalate when**: `NavigationSplitView` cannot host a third column without
  breaking the Projects sidebar, or the window controller must change its
  placement logic

## Contract

Read `docs/adr/0021-side-panel-split-column.md` and `docs/ui.md` first; they
already describe the target. Reference image:
`docs/design/commit-inspector-2026-10-29.png` (see `docs/design/README.md`).

## Problem

`SidePanelModifier` (`GitMenuBar/Components/Common/SidePanel.swift`) draws the
panel in a `ZStack` over the detail column. It covers the right part of the
history rows (hash and time are cut) and the overview cards. The toolbar
`Fetch` button sits over the panel close button.

## Decision

The panel becomes a trailing column. The detail column shrinks; nothing is
covered. Applies to every `MainMenuSidePanelSelection`, not only commits.

## Change

1. In `SidePanelModifier.body`, replace the `ZStack` overlay with an `HStack`:
   content (flexible, `minWidth: WorkbenchMetrics.centralMinimumWidth`) then
   the panel (`width: panelWidth`), separated by
   `WorkbenchMetrics.sectionSpacing`. Keep the slide-in transition from the
   trailing edge and the Reduce Motion fallback.
2. Remove the outside-tap dismiss layer when the panel is a column: it would
   block clicks on history rows, which must switch the open commit. Remove
   `dismissOnOutsideTap` and its plumbing
   (`MainMenuShellView.dismissSidePanelOnOutsideTap` and callers) if it becomes
   unused. Close stays on the panel close button and `Esc`.
3. Panel surface: rounded inline card, not a full-height slab.
   `clipShape`/border with `WorkbenchMetrics.largeCornerRadius`, 1pt
   `WorkbenchPalette.neutralBorder(contrast:)`, background `.background` plus
   the existing `Color.primary` tint. **No shadow** (inline surface, ADR 0021).
   Bottom inset `WorkbenchMetrics.windowPadding`. The panel top aligns with the
   top of the overview content, below the toolbar, so no toolbar item
   overlaps the panel header.
4. `WorkbenchMetrics`: update the comments; set
   `mainWindowMinimumWidth = projectsMinimumWidth + centralMinimumWidth +
   sidePanelWidth + windowPadding * 2 + splitDividerThickness +
   sectionSpacing`. Make `mainWindowInitialWidth` at least this value.
   `MainWindowController` already reads the constant.
5. A frame saved by `windowAutosaveName` can be smaller than the new minimum.
   Confirm AppKit clamps it; if not, clamp when restoring.

## Acceptance

- With the panel open, history rows show title, hash, and time at minimum
  window width, with the Projects sidebar visible.
- The toolbar does not overlap the panel header.
- Clicking another history row while the panel is open switches the commit.
- `Esc` and the close button close the panel; focus returns to the list.
- Branches, working tree, stashes panels still render correctly.

## Evidence for UI review

Follow "UI review rubric and evidence" in `README.md`. Hand off the list of
`#Preview` names and the screenshot paths.

## Validation

- `make check-preview`
- `make lint-changed`
- `make test-focused TEST_FILTER='GitMenuBarTests/MainMenu'` if such tests
  exist; otherwise report that none cover this view.
- Manual: minimum window size, sidebar shown and hidden, Reduce Motion on.
