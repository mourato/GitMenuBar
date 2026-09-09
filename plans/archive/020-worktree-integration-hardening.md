# Plan 020: Harden worktree cleanup with integration tests and documentation

> Executor instructions: follow every step and verification command. Stop and report instead of improvising when a STOP condition occurs.
>
> Drift check: git diff --stat b56c93d..HEAD -- GitMenuBarTests docs/ARCHITECTURE.md GitMenuBar/Components/Branches GitMenuBar/Services/Git plans/README.md

## Status

- Priority: P1
- Effort: M
- Risk: MED
- Depends on: plans/019-safe-batch-cleanup.md
- Category: tests
- Planned at: commit b56c93d, 2026-07-17

## Execution profile

- **Recommended profile**: implementer
- **Risk/lane**: Medium/Full
- **Parallelizable**: no; tests must validate the final cleanup contract
- **Reviewer required**: yes; review must compare observable Git state with UI results
- **Rationale**: this is verification and documentation, but it protects a destructive workflow against regressions
- **Escalate when**: tests require network-only remotes, nondeterministic timing, or production changes outside the cleanup surface

## Why this matters

Parser and unit tests cannot prove that linked worktree directories, branch refs, and partial failures behave correctly together. This phase adds deterministic end-to-end coverage and documents the distinction between working trees, Git worktrees, local branches, and remote-tracking refs.

## Current state

- GitManager tests create temporary repositories with runGit and assert actual refs/files.
- GitManagerMergeTests.swift uses bare repositories for reliable local remote behavior.
- docs/ARCHITECTURE.md documents feature folders and previews but not worktree semantics.
- Previous plans expose snapshots and safe batch cleanup.

## Commands

| Purpose | Command | Expected |
|---|---|---|
| Tests | make test | Tests passed |
| Full lint | make lint | exit 0 |
| Merge gate | make lint && make test | both pass |
| Guidance check | make guidance-check | validation passes |

## Scope

In scope:

- GitMenuBarTests/GitWorktreeIntegrationTests.swift
- GitMenuBarTests/GitManagerWorktreeCleanupTests.swift
- GitMenuBarTests/WorktreeParserTests.swift
- docs/ARCHITECTURE.md
- GitMenuBar/Components/Branches only if final accessibility correction is required
- plans/README.md status row

Out of scope:

- new product features
- GitHub API integration
- unrelated performance refactors
- release packaging

## Steps

### Step 1: Add end-to-end fixtures

Create deterministic helpers for a repository containing main, an already merged branch, an unmerged branch, a linked clean worktree, a linked dirty worktree, and a detached worktree where supported. Use unique temporary paths and TestSupport.swift conventions. Never depend on a developer repository or personal GitHub account.

Verify: make test -> fixture tests pass repeatedly.

### Step 2: Test observable cleanup outcomes

Assert that a merged local branch is eligible and deleted with -d; an unmerged branch remains; a branch checked out elsewhere is blocked; a clean linked worktree is removed only when explicitly selected; dirty/locked worktrees remain; stale snapshots skip items; one failure does not prevent later eligible items; and remote deletion requires explicit selection.

Assert actual refs and filesystem paths using runGit and FileManager, not only result messages.

Verify: make test -> integration tests pass repeatedly.

### Step 3: Document the contract

Update docs/ARCHITECTURE.md with: working tree means files/status of one checkout; worktree means one Git checkout managed by git worktree; merged means branch tip reachable from the selected local default branch; unknown, dirty, locked, current, protected, and checked-out-elsewhere are not safe; remote deletion is explicit and based on remote-tracking refs unless fetched.

Verify: make guidance-check -> validation passes.

### Step 4: Perform final manual sign-off

Open the app from the menu bar repeatedly, open Branches & Worktrees, refresh, filter, select cleanup items, cancel and confirm the dialog, and verify VoiceOver labels, keyboard focus, Light/Dark appearances, and dismissal behavior.

Verify: make lint && make test -> both pass; record a manual failure as BLOCKED rather than weakening safety rules.

## Test plan

- End-to-end tests use real Git commands in temporary repositories.
- Parser and analyzer suites remain green.
- No test deletes outside its temporary directory.
- Re-run the suite twice if worktree tests expose timing sensitivity.

## Done criteria

- [ ] Integration tests assert refs and filesystem outcomes.
- [ ] Safety states remain non-eligible.
- [ ] Partial failures are observable and deterministic.
- [ ] Architecture documentation defines terminology and safety contract.
- [ ] make lint && make test passes.
- [ ] Manual menu-bar, accessibility, Light/Dark, and dismissal checks pass.
- [ ] plans/README.md status row remains accurate.

## STOP conditions

- A test can affect a repository outside its temporary directory.
- The result depends on network availability or a personal account.
- Worktree behavior differs by Git version in a way the app cannot represent safely.
- Manual verification shows an action can delete dirty, current, locked, or unknown state.

## Maintenance notes

Keep integration fixtures as the regression contract for future cleanup changes. Provider-aware cleanup must add separate tests and retain local graph-based safety assertions.
