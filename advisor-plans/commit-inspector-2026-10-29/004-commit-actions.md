# Plan 004: Commit detail actions and overflow menu

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: 003
- **Planned at**: commit `fa92af4`, 2026-10-29

## Execution profile

- **Recommended profile**: `implementer-fast`
- **Suggested executor**: Antigravity Gemini Flash 3.8, `high`
- **Risk/lane**: `Low/Fast`
- **Parallelizable**: with 005; not with 003
- **Reviewer required**: yes, light; destructive action placement
- **Escalate when**: an action needs new logic in `HistoryActionSet`

## Problem

`CommitDetailPageView.statsSection` mixes four button styles. "Generate
Message with AI" and "Edit Message Manually" look disabled. "Reset to Here"
has the same weight as safe actions.

## Target

One row, spacing `WorkbenchMetrics.compactSpacing`: `Open on GitHub`
(`.workbenchSecondary()`; accent is reserved for Commit and selection), `Copy`
menu (`.workbenchGhost()`), overflow menu (`ellipsis.circle` icon in the
shared Icon style, 28 × 28 pt hit area, accessibility label "More commit
actions", `.help("More commit actions")`).

- Copy menu: "Copy Hash", "Copy Short Hash", "Copy Message".
- Overflow menu: "Generate Message with AI", "Edit Message", divider,
  "Reset to Here" with `role: .destructive`.
- Keep disabled states from `HistoryActionSet`. Hide message actions for
  merge commits instead of the caption, or keep the caption as `.help`.
- "Reset to Here" keeps the existing confirmation (`sidePanelResetAlert`).
- No visible label ends with an ellipsis.

## Evidence for UI review

Follow "UI review rubric and evidence" in `README.md`. Hand off the list of
`#Preview` names and the screenshot paths.

## Validation

- `make check-preview`, `make lint-changed`
- Manual: actions on a pushed commit, an unpushed commit, a merge commit.
