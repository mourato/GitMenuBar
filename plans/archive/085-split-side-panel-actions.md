# Plan 085: Split side-panel actions out of MainMenuActionCoordinator

> **Executor instructions**: Read this brief, `AGENTS.md`, and
> [project workflow facts](../../docs/agents/project-workflow.md) before editing.
> Work in a dedicated worktree. Follow the steps in order and run each
> verification command. On a STOP condition, stop and report; do not widen
> scope. Leave merge and push to the operator.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: Plan 084
- **Category**: tech-debt (item 3: god-object decomposition)
- **Planned at**: commit 9084297, 2026-10-07
- **Integration**: main; merge and push require explicit operator authorization

## Execution profile

- **Recommended profile**: Fast/inline
- **Risk/lane**: LOW
- **Parallelizable**: Yes, independent of Plans 082-083
- **Reviewer required**: No
- **Rationale**: MainMenuActionCoordinator.swift is 971 lines; ~20 side-panel actions (lines ~402-770) form one cohesive group sharing executeSidePanelMutation. Lowest value of the item-3 plans.
- **Escalate when**: File is easy to navigate after Plan 084 (then skip and record why); split needs duplicated alert/status publishing.

## Problem

Commit/sync flows and side-panel mutations share one coordinator, making the
file hard to navigate.

## Gate (run first)

Re-measure after Plan 084. If the coordinator is under ~600 lines or the
side-panel group shrank, skip and record why.

## Scope

Move `prepareSidePanelSelection`, `reloadSidePanelBranchData`, all
`*SidePanel*` actions, `performSidePanelCleanup`, `batchSummary`,
`executeSidePanelMutation`, `finishSidePanelMutation` into
`SidePanelActionCoordinator`. It reuses the existing alert/status publishing
(`publishAlert`, `publishSuccess`, `publishOperationStatus`) via injection, not
duplication. Commit and sync flows stay.

## Verification

- Existing side-panel tests pass; `make build`, `make lint`, `make test`.
- Manual: side panel stage/unstage, stash apply/drop, branch switch/delete, cleanup.

## Outcome

DONE 2026-10-08. Gate passed (973 lines). `MainMenuActionCoordinator.swift`
973 → 682 lines; `SidePanelActionCoordinator` owns side-panel actions and
reuses the host's mutation and alert/status publishing. Independent review
replaced an `unowned` host reference with `weak` (mutations skip after
teardown, regression test added) and removed unneeded Observation from the
stateless coordinator. Operator manual checks (side-panel stage/unstage,
stash, branch actions, cleanup, reset, busy-state disabling) pending.
