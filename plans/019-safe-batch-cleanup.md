# Plan 019: Implement revalidated safe cleanup for branches and worktrees

> Executor instructions: follow every step and verification command. Stop and report instead of improvising when a STOP condition occurs.
>
> Drift check: git diff --stat b56c93d..HEAD -- GitMenuBar/Services/Git GitMenuBar/Models/GitModels.swift GitMenuBar/Components/Branches GitMenuBarTests plans/README.md

## Status

- Priority: P0
- Effort: L
- Risk: HIGH
- Depends on: plans/018-worktree-visualizer-ui.md
- Category: security
- Planned at: commit b56c93d, 2026-07-17

## Execution profile

- **Recommended profile**: implementer
- **Risk/lane**: High/Full
- **Parallelizable**: no; all mutations target one Git repository and must be serialized
- **Reviewer required**: yes; this phase deletes branches and may delete worktree directories
- **Rationale**: safe deletion requires preflight, per-item revalidation, partial-failure reporting, and strict avoidance of force flags
- **Escalate when**: a force deletion is proposed, cleanup fetches automatically, remote deletion becomes default, or multiple repository mutations run concurrently

## Why this matters

The current local branch deletion path uses git branch -D and can discard unmerged commits. Existing merge cleanup also uses -D and trusts the caller’s prior analysis. This phase introduces an explicit batch API that revalidates every item and uses non-force Git operations.

## Current state

- GitBranchService+Mutations.swift:257-297 rejects only the current branch and executes git branch -D.
- GitBranchService+MergeToDefault.swift:112-184 deletes merged and remote branches but trusts the caller’s analysis.
- BranchManagementSheet confirms individual deletion but does not know worktree ownership.
- Plans 017 and 018 provide immutable eligibility snapshots and UI selection.

## Commands

| Purpose | Command | Expected |
|---|---|---|
| Build | make build | exit 0 |
| Tests | make test | Tests passed |
| Agent loop | make agent-check | lint and Debug build pass |
| Merge gate | make lint && make test | both pass |

## Scope

In scope:

- GitMenuBar/Services/Git/GitBranchService+Mutations.swift
- GitMenuBar/Services/Git/GitBranchService+MergeToDefault.swift
- GitMenuBar/Services/Git/GitBranchService+Cleanup.swift
- GitMenuBar/Services/Git/GitManager.swift
- GitMenuBar/Components/Branches/BranchManagementSheet.swift
- GitMenuBar/Components/Branches/CleanupConfirmationView.swift
- GitMenuBarTests/GitManagerMergeTests.swift
- GitMenuBarTests/GitManagerWorktreeCleanupTests.swift
- plans/README.md status row

Out of scope:

- GitHub PR merge status
- automatic fetch
- force deletion
- repository selection or menu-bar lifecycle

## Steps

### Step 1: Make individual local deletion conservative

Change ordinary branch deletion and existing merged-branch cleanup to use git branch --delete rather than -D. Preserve current/default/unknown guards and return the Git error when the branch is not safely deletable. Add regression coverage for an unmerged branch remaining after failed deletion.

This is an intentional safety behavior change: the UI may report that a branch needs manual Git intervention, but the app must not discard it.

Verify: make test -> existing merge tests and the new unmerged-delete test pass.

### Step 2: Add a serial batch cleanup API

Create GitBranchService+Cleanup.swift with an async API accepting selected immutable cleanup items and a snapshot/repository identity. Process items serially in one background operation. Before each mutation, verify the branch/worktree still exists, its HEAD hash matches the analyzed hash, and it remains eligible.

For local branches use git branch --delete. For linked worktrees use git worktree remove without --force only after confirming the path is not main/current, not locked, and clean. For remote branches, call the existing authenticated delete operation only when a separate explicit remote-delete selection is present.

Return per-item success, skipped-as-stale, or failed with a user-readable reason. Continue after failure and refresh once after the batch.

Verify: make test -> batch tests prove serial processing, stale skipping, partial success, and no force flags.

### Step 3: Wire confirmation and selection

Add CleanupConfirmationView. Confirmation text must enumerate local branch deletions, worktree directory removals, and remote deletions separately. Require a second confirmation when any worktree directory or remote branch is selected. Do not silently include remote deletion because a local branch is selected.

Connect Cleanup mode selection to the batch API. Disable cleanup while loading or while another cleanup runs, clear selected IDs after completion, show per-item results, and reload the snapshot.

Verify: make agent-check -> lint and Debug build pass.

### Step 4: Verify Git behavior manually

Using a disposable repository, exercise one merged branch, one unmerged branch, one linked dirty worktree, one clean linked worktree, and one current worktree. Confirm the summary and final results match actual Git state.

Verify: make lint && make test -> both pass; manual test confirms no unmerged branch or dirty worktree is removed.

## Test plan

- Existing GitManagerMergeTests.swift remains green.
- New tests cover non-force local deletion, merged deletion, current/default rejection, worktree removal, dirty/locked rejection, stale hash rejection, remote opt-in, and partial failure.
- Follow TestSupport.swift and the existing bare-remote setup pattern.

## Done criteria

- [ ] No safe cleanup path uses -D or --force.
- [ ] Every selected item is revalidated immediately before mutation.
- [ ] Local, worktree, and remote deletion are separately visible in confirmation.
- [ ] Batch execution is serial and reports per-item outcomes.
- [ ] Dirty, locked, current, protected, stale, and unknown items are not deleted.
- [ ] make agent-check passes.
- [ ] make lint && make test passes.
- [ ] plans/README.md status row remains accurate.

## STOP conditions

- A worktree must be removed with --force.
- Git state differs from the snapshot and the API cannot safely skip it.
- Remote deletion requires implicit authorization or the token flow is insufficient.
- Correctness requires switching branches, stashing, or modifying the current worktree.

## Maintenance notes

Review every future cleanup feature against the no-force invariant. Provider-aware cleanup must preserve graph-based Git status as a separate signal. Keep batch execution serial unless repository locking and cancellation are redesigned.
