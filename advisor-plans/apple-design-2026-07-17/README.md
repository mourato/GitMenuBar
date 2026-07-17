# Apple Design follow-up plans

These plans were written on 2026-07-17 against commit `e9be124` after the
Apple Design review of GitMenuBar.

## Coordination rule

The repository already has an active worktree sequence in plans 016–020. These
Apple Design plans are intentionally stored outside `plans/README.md` so they
do not compete with that queue or with the agent working in
`/Users/usuario/Documents/Projects/gitmenubar-worktrees/016`.

Do not execute any plan in this directory while plans 016–020 are TODO,
IN PROGRESS, or have unreviewed changes. After plan 020 is DONE, create a new
isolated worktree and re-run each plan's drift check. Do not execute these
plans from the current `main` worktree or from the worktree for plan 016.

If the worktree sequence changes any file listed in an Apple Design plan, stop,
reconcile the plan against the new baseline, and update its `Planned at` SHA
before implementation. Do not change the status rows for plans 016–020 from
this directory.

## Recommended execution order

| Plan | Title | Priority | Effort | Depends on | Status |
|---|---|---:|---:|---|---|
| 021 | Establish shared motion and accessibility primitives | P1 | M | 016–020 DONE | DONE |
| 022 | Animate AppKit main-window presentation safely | P1 | M | 021 | DONE |
| 023 | Restore SwiftUI route and origin continuity | P1 | M | 021 | DONE |
| 024 | Complete press feedback and semantic content motion | P2 | M | 021 | DONE |
| 025 | Finish adaptive surfaces, typography, haptics, and sanitization | P2 | M | 021–024 | DONE |

Plans 022 and 023 touch separate implementation surfaces, but they are kept
serial to reduce merge and visual-regression risk. Plan 025 is last because it
removes helpers or components only after the preceding plans establish the
final ownership of those abstractions.

## Shared verification policy

- During implementation: `make agent-check`.
- Before merge/push: `make lint && make test`.
- Any change to menu-bar/window lifecycle also requires manual verification of
  status-item opening, dismissal, activation, sheets, and auto-hide behavior.
- Any UI change requires relevant previews at normal, Reduce Motion, Reduce
  Transparency, increased contrast, and accessibility text sizes where the
  platform exposes those environments.

## Status values

`TODO`, `IN PROGRESS`, `DONE`, `BLOCKED (reason)`, or `REJECTED (reason)`.
