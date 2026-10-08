# Plan 086: Move render snapshot and recent projects into an observable model

> **Executor instructions**: Read this brief, `AGENTS.md`,
> [project workflow facts](../../docs/agents/project-workflow.md), and
> [UI contract](../../docs/ui.md) before editing. Work in a dedicated worktree.
> Follow the steps in order and run each verification command. On a STOP
> condition, stop and report; do not widen scope. Leave merge and push to the
> operator.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MEDIUM
- **Depends on**: branch `mainmenu-decomposition` reviewed and merged to main
- **Category**: tech-debt (item 2 follow-up: MainMenuView decomposition)
- **Planned at**: commit 1b5408e, 2026-10-08
- **Integration**: main; merge and push require explicit operator authorization

## Execution profile

- **Recommended profile**: Standard/full
- **Risk/lane**: MEDIUM
- **Parallelizable**: No; touches `GitMenuBar/Pages/MainMenu/` core composition
- **Reviewer required**: Yes
- **Rationale**: After the first decomposition pass, `MainMenuView` still owns `renderSnapshot` and `recentProjectReferences`. Project actions and command-palette actions stay as `extension MainMenuView` only because they mutate those two values. A single owner for them unblocks moving both action groups out of the view.
- **Escalate when**: The snapshot model needs to read more than the stores it derives from; command-palette actions still need the whole view after the move; any focus, `Esc`, or presentation behavior changes.

## Problem

`MainMenuView` holds `@State var recentProjectReferences` and
`@State var renderSnapshot`. `MainMenuProjectActions` mutates recent projects,
which feeds the cached snapshot read by `MainMenuComputed` and
`MainMenuContent`. `MainMenuCommandPaletteActions` runs about ten other actions
(switch repository, add project, atomic commits, branch selector, sync,
restart). Both groups remain view extensions, so they depend on the whole view.

## Scope

1. Create `MainMenuSnapshotModel` (`@MainActor @Observable final class`) that
   owns `recentProjectReferences` and `renderSnapshot`, plus the snapshot
   rebuild currently in `MainMenuComputed`. Inputs come from the stores it
   already reads; pass them via method arguments or `init`, not a protocol.
2. Move project actions (`MainMenuProjectActions`) onto the model, or onto a
   feature type that receives the model.
3. Project actions may receive narrow closures for view-owned effects
   (`setAutoHideSuspended`, `dismissTransientPresentations`); focus stays in
   the view.

Operator decision 2026-10-08 (scope reduced): command-palette execution stays
on `MainMenuView`. A Plan 086 run hit the STOP condition: palette execution
needs workspace, branch-dialog, confirmation, error, and sync state plus
view-owned `@FocusState` (`MainMenuCommandPaletteActions.swift:71-91`,
`MainMenuActions.swift:65-71,118-185`). The palette is cross-feature
orchestration and belongs to the composition view.

Out of scope: command-palette execution, keyboard navigation (needs `@FocusState` on a view), visual
changes, StatusBarController, GitManager.

## Invariants

- Snapshot recomputes on the same triggers as today; no extra redraws of dense lists.
- Recent-project order and persistence (`RecentProjectsStore`) unchanged.
- Command palette items, enablement, and results unchanged.
- No Git operation moves into a view; no single-implementation protocol.

## Steps

1. Drift check: `git diff --stat <planned-commit>..HEAD -- GitMenuBar/Pages/MainMenu/`.
2. Record before counts: `MainMenuView.swift` lines, `@Environment`, `@State`,
   files and members in `extension MainMenuView`.
3. Introduce the model; move snapshot state and rebuild; build green.
4. Move project actions; build and test.
6. Delete orphans created by the move; record after counts.

## Verification

- `make build`, `make lint`, `make test`, `make check-preview`
- Add a focused test for `MainMenuSnapshotModel`: adding or removing a recent project updates the snapshot.
- Manual: add/remove/rename project; switch repository from sidebar and from palette; run each palette command; `Esc` closes palette; focus returns to the list.

## STOP conditions

- Snapshot model needs the whole environment to compute.
- Project actions need more than the model, `RecentProjectsStore`, the coordinators they call today, and narrow view closures.

## Outcome

DONE 2026-10-08 (reduced scope). `MainMenuSnapshotModel` owns recent projects,
the render snapshot, and its rebuild; project actions left `MainMenuView`.
`MainMenuView` 244 → 243 lines, `@State` 9 → 8, extension members 90 → 86.
Independent review: no defects; recommended keeping the model for testable
snapshot ownership. Pre-existing gap noted, not changed: loading/sync flags
have no dedicated snapshot rebuild trigger (follow up only if a stale overview
reproduces). Operator manual checks (project add/remove/rename, sidebar and
palette switching, palette commands, `Esc`/focus restoration) pending.
