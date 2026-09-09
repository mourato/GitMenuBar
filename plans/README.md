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

## Archive notes

- Plans `001`–`072`, `076`–`081`, and withdrawn Companion CLI briefs
  (`036`–`038`, `068`, `072`) are under [`archive/`](archive/).
- Stub `029` (never authored) was dropped from the index; it had no file.
- Historical consolidate/optimize notes from 2026-07 lived only in the old
  README; Git history retains them.
