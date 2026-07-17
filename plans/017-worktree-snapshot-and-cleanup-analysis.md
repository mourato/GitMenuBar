# Plan 017: Add worktree snapshots and conservative cleanup analysis

> Executor instructions: follow every step and verification command. Stop and report instead of improvising when a STOP condition occurs.
>
> Drift check: git diff --stat b56c93d..HEAD -- GitMenuBar/Models/GitModels.swift GitMenuBar/Services/Git GitMenuBarTests plans/README.md

## Status

- Priority: P1
- Effort: L
- Risk: HIGH
- Depends on: plans/016-worktree-model-and-parser.md
- Category: direction
- Planned at: commit b56c93d, 2026-07-17

## Execution profile

- **Recommended profile**: implementer
- **Risk/lane**: High/Full
- **Parallelizable**: no; snapshot state, service state, and GitManager facade form one contract
- **Reviewer required**: yes; this phase decides which data is later labeled safe to delete
- **Rationale**: it combines Git graph queries, worktree filesystem state, background execution, and published observable state
- **Escalate when**: the analyzer needs GitHub PR state, automatic fetch, concurrent repository commands, or force operations

## Why this matters

The UI needs one coherent repository snapshot rather than separate branch and worktree queries that can disagree. This phase adds read-only discovery and explicit eligibility decisions so safe cleanup never means merely that a row looks old.

## Current state

- GitBranchService owns branch state and runs heavy Git work through runOnBackground, publishing through MainActor.
- GitManager mirrors branchService state through Combine and exposes async branch methods.
- getDefaultBranchNameAsync detects origin/HEAD and falls back to local main/master.
- resolveBranchInfoAsync performs per-branch status/date calls; this feature should use batch-oriented commands where possible.
- Plan 016 provides WorktreeParser and immutable worktree models.

## Commands

| Purpose | Command | Expected |
|---|---|---|
| Build | make build | exit 0 |
| Tests | make test | Tests passed |
| Agent loop | make agent-check | lint and Debug build pass |

## Scope

In scope:

- GitMenuBar/Models/WorktreeCleanupModels.swift
- GitMenuBar/Services/Git/GitBranchService+Worktrees.swift
- GitMenuBar/Services/Git/WorktreeCleanupAnalyzer.swift
- GitMenuBar/Services/Git/GitBranchService.swift
- GitMenuBar/Services/Git/GitManager.swift
- GitMenuBarTests/WorktreeCleanupAnalyzerTests.swift
- GitMenuBarTests/GitManagerWorktreeTests.swift
- plans/README.md status row

Out of scope:

- SwiftUI layout and selection controls
- destructive cleanup mutations
- automatic network fetch
- GitHub API or pull-request status

## Steps

### Step 1: Define snapshot and eligibility models

Extend the immutable model layer with a repository worktree snapshot containing the detected default branch name, analysis source/ref information, worktree records, local/remote branch references, and cleanup decisions. Use explicit statuses for merged, notMerged, protected, current, checkedOutElsewhere, dirty, locked, prunable, and unknown. Unknown must never be eligible.

Keep BranchInfo’s existing API compatible. Do not add optional flags that allow merged and unmerged to be true simultaneously.

Verify: make build -> exit 0.

### Step 2: Add read-only Git queries

Implement GitBranchService+Worktrees.swift. Run these operations in one background snapshot task: git worktree list --porcelain; machine-readable local and remote ref enumeration with for-each-ref; refreshed default branch detection; merged local branch enumeration against the local default ref; and status for each existing worktree using its path as the command directory.

Use executeGitCommand argument arrays, never a shell command string. Associate refs/heads/name with linked worktrees and represent detached worktrees explicitly. Do not fetch while loading; remote-tracking data is based on the last fetch and must be labeled.

Verify: make test -> Tests passed.

### Step 3: Implement pure eligibility analysis

Create WorktreeCleanupAnalyzer.swift as a pure transformation. A local branch is eligible only when its tip is reachable from the local default ref, is not protected/current, and is not checked out in any worktree. A worktree is eligible only when it is not main/current, not locked, present, and clean. Remote eligibility is separate and explicit.

Prefer one batch merged-ref query or a Set of refs over one merge-base process per row. Command failure becomes unknown.

Verify: make test -> analyzer tests pass for merged, unmerged, current, elsewhere, dirty, locked, protected, detached, and unknown cases.

### Step 4: Publish through the existing facade

Add a published worktree snapshot to GitBranchService, pipe it through GitManager using the existing Combine pattern, and expose resolveWorktreeSnapshotAsync(). Do not modify MainMenuView yet.

Verify: make agent-check -> lint and Debug build pass.

## Test plan

- Pure analyzer tests for every status and precedence rule.
- Temporary-repository integration tests for linked worktrees and merged/unmerged branches.
- Failed Git queries produce unknown, never eligible.
- Facade returns and publishes the same snapshot.
- Follow GitManagerBranchOperationsTests.swift for facade/state-pipe style.

## Done criteria

- [ ] One read-only snapshot contains worktrees, refs, default ref, and eligibility.
- [ ] No automatic fetch or mutation occurs during analysis.
- [ ] Unknown is never eligible.
- [ ] Work runs off the main actor and publishes on the main actor.
- [ ] make agent-check exits 0.
- [ ] make test exits 0.
- [ ] No UI or destructive mutation files are changed.
- [ ] plans/README.md status row remains accurate.

## STOP conditions

- Git cannot distinguish the selected worktree from the main worktree.
- There is no usable default ref and the analyzer would need to guess.
- Dirty, locked, or prunable state cannot be represented without treating it as safe.
- The only way to obtain data is to fetch or mutate.
- Concurrency diagnostics require unsafe Sendable or nonisolated(unsafe) escapes.

## Maintenance notes

The snapshot is local-ref based. Future GitHub integration may add PR state as a separate signal, never overwrite graph-based status. Revisit batching if branch counts grow; the existing query code documents per-branch round trips as a scalability concern.
