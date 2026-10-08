# Plan 083: Extract app command routing from StatusBarController

> **Executor instructions**: Read this brief, `AGENTS.md`, and
> [project workflow facts](../docs/agents/project-workflow.md) before editing.
> Work in a dedicated worktree. Follow the steps in order and run each
> verification command. On a STOP condition, stop and report; do not widen
> scope. Leave merge and push to the operator.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: Plan 082
- **Category**: tech-debt (item 3: god-object decomposition)
- **Planned at**: commit 9084297, 2026-10-07
- **Integration**: main; merge and push require explicit operator authorization

## Execution profile

- **Recommended profile**: Fast/inline
- **Risk/lane**: LOW
- **Parallelizable**: No; same file as Plan 082
- **Reviewer required**: No
- **Rationale**: After Plan 082, command routing (performAppCommand*, perform*Command, repository selection/reveal/open) is the remaining non-status-item responsibility in StatusBarController. Only worth extracting if it is still large.
- **Escalate when**: Routing after Plan 082 is under ~150 lines (then skip this plan and record why); extraction needs new shared state.

## Problem

`StatusBarController` routes `AppCommandInvocation` to coordinators. This is
independent of the status item and is easier to test in isolation.

## Gate (run first)

Measure routing code size after Plan 082. Under ~150 lines: mark this plan
skipped with the measured size. Do not extract.

## Scope

Move into `AppCommandRouter` (`@MainActor final class`, dependencies injected
via `init`): `performAppCommand(_:)` (both overloads), `handleCoordinatorCommand`,
`performCommitCommand`, `performSyncCommand`, `performPushCommand`,
`performPullCommand`, `chooseRepository`, `selectRepository`,
`revealCurrentRepositoryInFinder`, `openCurrentRepositoryOnGitHub`,
`presentRepositoryOptions`, `open(urlString:)`.

`AppCommandCenter.performInvocation` points to the router.

## Invariants

- Disabled commands still produce `HapticFeedback.actionUnavailable()` and no action.
- Commands needing UI feedback still present the main window.

## Verification

- `make test-focused TEST_FILTER='GitMenuBarTests/MainMenuCommandPaletteResolverTests'`
- Add one router test: invocation → expected coordinator call (test double).
- `make build`, `make lint`, `make test`; manual menu-bar commands Commit, Sync, Choose Repository.
