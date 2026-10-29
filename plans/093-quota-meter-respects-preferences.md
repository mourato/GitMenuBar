# Plan 093: Make the sidebar quota summary respect quota preferences

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
- **Depends on**: none
- **Category**: ui (premium main-window pass)
- **Planned at**: commit e48a916, 2026-10-28
- **Integration**: main; merge and push require explicit operator authorization

## Execution profile

- **Recommended profile**: Fast/inline
- **Risk/lane**: LOW
- **Executor**: Claude Haiku 5.5
- **Parallelizable**: Yes
- **Reviewer required**: Yes (UI owner)
- **Rationale**: Small wiring of existing preferences into one view.
- **Escalate when**: the thresholds are not reachable from the summary view through the environment.

## Problem

`UsageQuotaSummaryView.swift:112` colors values with
`UsageQuotaFormatting.trafficLightColor` (fixed 40/15), ignoring
`sessionWarningThresholds`, `weeklyWarningThresholds`, `valueStyle`, and
`meterStyle` in `UsageQuotaPresentationPreferences`.

## Scope

1. Read `UsageQuotaPresentationPreferences` from the environment in
   `UsageQuotaSummaryView`.
2. Color: secondary below the first configured threshold crossing; warning
   and error colors past the configured thresholds. Remove the fixed 40/15
   path if nothing else uses it.
3. Show left or used per `valueStyle`; render bars per `meterStyle`.
4. Keep the provider icon with `brandColor`.

## Acceptance

- Test the threshold-to-color mapping with configured values.
- Preview states: normal, near limit, stale, used vs left.
- Matches the approved prototype and `docs/ui.md` hierarchy rules.

## Validation

- `make lint-changed`
- `make check-preview` (add or update previews for every changed view)
- `make build`
- Screenshots of the changed surface in Dark and Light, plus Increase
  Contrast, attached to the handoff.
- `make test-focused TEST_FILTER='GitMenuBarTests/UsageQuotaFormattingTests'` (create if missing)

## STOP conditions

- An unexpected changed path outside this scope.
- A rule in `docs/ui.md` blocks the change: report it; the UI owner decides.
