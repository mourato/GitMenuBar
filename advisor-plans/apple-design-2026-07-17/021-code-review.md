# Code review — Plan 021

## Scope

Reviewed the complete Plan 021 diff, including the new
`MacChromeMotion.swift`, the Reduce Motion call sites, and the plan-scope
adjustment. The review followed the GitMenuBar thermo review profile and the
Apple Design motion reference.

## Findings and resolution

### [MEDIUM] Reduce Motion must not retain moving transitions

- **Location**: `MacChromeMetrics.swift`, `MainMenuView.swift`,
  `HistorySectionView.swift`, `WorkingTreeSectionView.swift`.
- **Issue**: Replacing global animation suppression with a short easing curve
  alone would still allow existing `.move` transitions to slide under Reduce
  Motion.
- **Resolution**: Added explicit `.opacity` transitions for the existing route
  and section boundaries when Reduce Motion is enabled, and routed press/collapse
  animations through the adaptive motion helper.

## Validation

- `make agent-check` — passed.
- `make lint && make test` — passed after applying the two pre-existing
  `wrapIfStatementBodies` formatting violations and the local
  `function_parameter_count` suppression reported by the full merge gate in
  `MainMenuCommandPaletteResolverTests.swift`, `SettingsPage.swift`, and
  `ConfirmationDialogsModifier.swift`. These are baseline gate-hygiene edits,
  with no behavior change.
- `git diff --check` — passed.
- Targeted Swift lint — 0 serious violations; two existing line-length
  warnings remain in `ConfirmationDialogsModifier.swift`.
- Debug build — passed.

## Verdict

Approved for merge. No unresolved changed-path findings remain. Broader route
direction, command-palette materialization, and semantic content transitions
remain intentionally assigned to Plans 023 and 024.
