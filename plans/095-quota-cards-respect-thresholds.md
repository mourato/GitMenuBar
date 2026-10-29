# Plan 095: Make quota cards respect configured warning thresholds

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
- **Depends on**: 093
- **Category**: ui (premium main-window pass)
- **Planned at**: branch ui-premium-integration, 2026-10-28
- **Integration**: main; merge and push require explicit operator authorization

## Execution profile

- **Recommended profile**: Fast/inline
- **Risk/lane**: LOW
- **Executor**: Claude Haiku 5.5
- **Parallelizable**: Yes (with 094)
- **Reviewer required**: Yes (UI owner)
- **Rationale**: Reuse the threshold mapping added by plan 093 in the quota cards.
- **Escalate when**: the cards cannot reach `UsageQuotaPresentationPreferences` without a signature change outside `Components/UsageQuota`.

## Problem

`UsageQuotaDotsCard.swift` (the status-item submenu and the strip popover)
still colors values through `UsageQuotaTrafficLightColor.swiftUI(for:)`, which
uses the fixed 40/15 rule in `UsageQuotaFormatting.trafficLightColor`. This
violates the rule in `docs/ui.md` that quota meters follow the configured
warning thresholds.

## Scope

1. Color the dots and the percent in `UsageQuotaDotsCard` with
   `UsageQuotaFormatting.alertLevel(remainingPercent:thresholds:)` from plan
   093. Use the session thresholds for the session row and the weekly
   thresholds for weekly and model rows. Pass the thresholds in through
   `RowData` or the environment; do not read `UserDefaults` in the view.
2. Share one level-to-color mapping with `UsageQuotaSummaryView`; do not
   duplicate the switch.
3. When nothing still calls `UsageQuotaFormatting.trafficLightColor`,
   `UsageQuotaTrafficLight`, or `UsageQuotaTrafficLightColor`, delete them
   and their tests.

## Acceptance

- With thresholds `[50, 80]`, a row at 45% used is secondary, 60% used is
  warning, 85% used is error, in both the submenu and the popover.
- Existing quota tests pass; tests for removed symbols are removed or
  rewritten against `alertLevel`.
- Matches `docs/ui.md` hierarchy rules.

## Validation

- `make lint-changed`
- `make check-preview`
- `make build`
- `make test-focused TEST_FILTER='GitMenuBarTests/UsageQuotaFormattingTests'`
- `make test-focused TEST_FILTER='GitMenuBarTests/UsageQuotaDotsCardTests'` (if present)

## STOP conditions

- An unexpected changed path outside `Components/UsageQuota`, `Models/UsageQuotaModels.swift`, and their tests.
- A rule in `docs/ui.md` blocks the change: report it; the UI owner decides.
