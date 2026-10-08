# Plan 084: Slim GitManager into a thin observable store

> **Executor instructions**: Read this brief, `AGENTS.md`, and
> [project workflow facts](../docs/agents/project-workflow.md) before editing.
> Work in a dedicated worktree. Follow the steps in order and run each
> verification command. On a STOP condition, stop and report; do not widen
> scope. Leave merge and push to the operator.

## Status

- **Priority**: P2
- **Effort**: L (three PRs)
- **Risk**: MEDIUM
- **Depends on**: Observable migration merged to main
- **Category**: tech-debt (item 3: god-object decomposition)
- **Planned at**: commit 9084297, 2026-10-07
- **Integration**: main; merge and push require explicit operator authorization

## Execution profile

- **Recommended profile**: Standard/full
- **Risk/lane**: MEDIUM
- **Parallelizable**: C2 and C3 may run in parallel after C1 merges
- **Reviewer required**: Yes
- **Rationale**: GitManager.swift is 1968 lines mixing observable state, command execution, callback wrappers duplicating Async APIs, and repository initialization. Existing GitBranchService and GitCommitHistoryService already show the target pattern.
- **Escalate when**: Stale-operation protection (RepositoryOperationContext, GitRefreshSession) must change; a view would need direct Git access; a slice exceeds ~600 changed lines.

## Problem

`GitMenuBar/Services/Git/GitManager.swift` is the largest file in the app.
Many APIs exist twice (completion-handler wrapper plus `Async`), and unrelated
responsibilities share one type.

## Slices (one PR each, in order)

### C1 — Delete completion-handler wrappers

For each pair (`stageFile`/`stageFileAsync`, `pushToRemote`/`pushToRemoteAsync`,
`updateUncommittedFiles`, `updateBranchInfo`, `fetchBranches`, `checkRepoVisibility`,
`pullFromRemote`, `discardAllUnstagedChanges`, `isCommitPublishedToUpstream`,
`diffForCommit`, `rewriteCommitMessage`, …): grep callers, migrate them to
`await`, delete the wrapper. Pure deletion of behavior-equivalent code.

### C2 — Extract repository initialization

Move `isGitRepository`, `hasRemoteConfigured`, `remoteRepositoryExists`,
`initializeRepository`, `createInitialCommit`, `addRemote`,
`hasUncommittedChanges(at:)`, `updateRemoteURL`, `pushToNewRemote` into
`GitRepositoryInitService`. Expected main consumer: `Pages/CreateRepository`.
Verify with grep before moving.

### C3 — Extract working-tree operations

Move stage/unstage/discard/diff operations into `GitWorkingTreeService`,
following `GitBranchService`. `GitManager` keeps published state and delegates.

## Invariants

- Operations stay path-bound (ADR 0009) and stale-checked via `RepositoryOperationContext`.
- No Git operation moves into a view.
- Published state seen by views is unchanged.

## Verification (each slice)

- Focused tests for the touched service (`make test-focused TEST_FILTER='GitMenuBarTests/<Name>'`); add tests for each new service's public operations.
- `make build`, `make lint`, `make test`.
- Manual: stage/unstage/discard a file; commit; push; pull; create repository flow.
