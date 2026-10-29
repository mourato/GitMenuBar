# Plan 090: Turn the overview card into a status strip

> **Executor instructions**: Read this brief, `AGENTS.md`,
> [project workflow facts](../docs/agents/project-workflow.md),
> [UI contract](../docs/ui.md) (especially "Visual hierarchy rules"), and
> [ADR 0020](../docs/adr/0020-toolbar-actions-and-history-list.md) before
> editing. Work in a dedicated worktree. Use Workbench tokens only; no raw
> sizes, colors, or opacities in views. On a STOP condition, stop and report;
> do not widen scope. Leave merge and push to the operator. The UI owner
> reviews the diff and screenshots before merge.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: 089
- **Category**: ui (premium main-window pass)
- **Planned at**: commit e48a916, 2026-10-28
- **Integration**: main; merge and push require explicit operator authorization

## Execution profile

- **Recommended profile**: Fast/inline
- **Risk/lane**: LOW (view-only)
- **Executor**: Antigravity Gemini 3.8, reasoning high
- **Parallelizable**: Yes, after 089 (with 091, 092, 093)
- **Reviewer required**: Yes (UI owner)
- **Rationale**: View-only layout change on one surface with existing data.
- **Escalate when**: the strip needs data not already in the overview model.

## Problem

The overview is a heavy card with three stacked rows. Untracked files alone
show an orange `!` warning icon.

## Scope

1. In `RepositoryOverviewView.swift`, render Changes, Branches, and Stashes
   as three equal columns: caption label, then value with the qualifier in
   secondary style ("1 untracked", "1 unmerged", "None").
2. Columns that open a side panel keep that action; use the row button style
   and a hover fill from `WorkbenchPalette`.
3. Warning color only for conflicts or errors, per the hierarchy rules.
4. Use `WorkbenchMetrics.cornerRadius` and hairline separators; no shadow.

## Acceptance

- Each column is one accessibility element with label and value.
- Empty, loading, and error states covered in previews.
- Matches the approved prototype and `docs/ui.md` hierarchy rules.

## Validation

- `make lint-changed`
- `make check-preview` (add or update previews for every changed view)
- `make build`
- Screenshots of the changed surface in Dark and Light, plus Increase
  Contrast, attached to the handoff.
- None beyond the common gates.

## STOP conditions

- An unexpected changed path outside this scope.
- A rule in `docs/ui.md` blocks the change: report it; the UI owner decides.
