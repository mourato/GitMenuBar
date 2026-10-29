# Plan 094: Typography and spacing finish for the main window

> **Executor instructions**: Read this brief, `AGENTS.md`,
> [project workflow facts](../docs/agents/project-workflow.md),
> [UI contract](../docs/ui.md) (especially "Visual hierarchy rules"), and
> [ADR 0020](../docs/adr/0020-toolbar-actions-and-history-list.md) before
> editing. Work in a dedicated worktree. Use Workbench tokens only; no raw
> sizes, colors, or opacities in views. On a STOP condition, stop and report;
> do not widen scope. Leave merge and push to the operator. The UI owner
> reviews the diff and screenshots before merge.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: 089, 090, 091, 092
- **Category**: ui (premium main-window pass)
- **Planned at**: commit e48a916, 2026-10-28
- **Integration**: main; merge and push require explicit operator authorization

## Execution profile

- **Recommended profile**: Fast/inline
- **Risk/lane**: LOW
- **Executor**: Claude Haiku 5.5
- **Parallelizable**: No; last unit
- **Reviewer required**: Yes (UI owner)
- **Rationale**: Mechanical token and spacing cleanup after structural units land.
- **Escalate when**: a change needs a new token that is not listed here.

## Problem

After the structural units land, date headers sit tight against the History
title and the settings button is misaligned in the sidebar footer.

## Scope

1. History date headers: `WorkbenchTypography.captionStrong`, secondary,
   `WorkbenchMetrics.sectionSpacing` above; pinned section headers.
2. Align the sidebar footer settings button to the quota row baseline with a
   `WorkbenchMetrics.iconHitTarget` hit area.
3. Remove any token or view left orphaned by plans 089–092.

## Acceptance

- No visual regression elsewhere; previews updated.
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
