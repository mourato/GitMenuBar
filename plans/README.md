# Implementation Plans

Active local execution briefs only. Completed and withdrawn plans live in
[`archive/`](archive/) (recoverable via Git history).

## Governance

- `global:improve` owns read-only audits and plan authoring.
- `delivery-workflow` owns risk lanes, validation, gates, and Git.
- Every plan has an individual `Execution profile`. Reclassify it immediately
  before execution against the live diff.
- `implementer-fast` is reserved for deterministic `Low/Fast` plans. Use
  `implementer` for ambiguous, `Medium`, or `High` plans.

## Active

| Plan | Title | Priority | Status |
|------|-------|----------|--------|
| [073](073-measure-commit-push-switch-latency.md) | Establish the commit/push and project-switch latency baseline | P1 | IMPLEMENTED — baseline pending |
| [074](074-de-duplicate-commit-push-refresh-work.md) | De-duplicate the Commit & Push critical path | P1 | IMPLEMENTED — measurement pending |
| [075](075-switch-projects-during-path-bound-git-actions.md) | Switch projects while path-bound Git actions finish safely | P0 | IMPLEMENTED — manual/Instruments pending |
| [087](087-preview-state-coverage.md) | Close preview gaps and cover key UI states | P3 | READY |
| [089](089-toolbar-repository-actions.md) | Move repository actions and branch picker into the toolbar | P1 | READY |
| [090](090-overview-status-strip.md) | Turn the overview card into a status strip | P2 | READY |
| [091](091-history-plain-list.md) | Rebuild history rows as a plain list | P1 | READY |
| [092](092-sidebar-signal-cleanup.md) | Reduce noise and add severity to the Projects sidebar | P2 | READY |
| [093](093-quota-meter-respects-preferences.md) | Make the sidebar quota summary respect quota preferences | P2 | READY |
| [094](094-typography-and-finish.md) | Typography and spacing finish for the main window | P3 | READY |

## Archive notes

- Plans `001`–`072`, `076`–`086`, `088`, and withdrawn Companion CLI briefs
  (`036`–`038`, `068`, `072`) are under [`archive/`](archive/).
- Stub `029` (never authored) was dropped from the index; it had no file.
- Historical consolidate/optimize notes from 2026-07 lived only in the old
  README; Git history retains them.
