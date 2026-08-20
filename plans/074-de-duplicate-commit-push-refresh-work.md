# Plan 074: De-duplicate the Commit & Push critical path

> **Executor instructions**: Follow this brief step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the **STOP conditions** section occurs, stop and
> report — do not improvise. This plan reduces repeated local work while the
> existing repository-switch busy guard remains in place. When done, update
> the local status row in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat acad442..HEAD -- GitMenuBar/App/MainMenuActionCoordinator.swift GitMenuBar/Services/Git/GitManager.swift GitMenuBar/Services/Git/GitBranchService+State.swift GitMenuBarTests/MainMenuActionCoordinatorTests.swift GitMenuBarTests/GitManagerRefreshTests.swift`
> If any in-scope file changed since this plan was written, compare the
> **Current state** excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: HIGH
- **Depends on**: Plan 073 baseline; Plan 057 is DONE
- **Category**: perf
- **Planned at**: commit `acad442`, 2026-08-19
- **Finding ID**: `deduplicate-commit-push-refresh-work`
- **Publication**: local
- **Parent issue**: none
- **Issue**: none
- **Integration**: `main`; merge and push require explicit user authorization

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `High/Full`
- **Parallelizable**: no — commit, refresh, remote-status, and error paths
  share one ordering contract
- **Reviewer required**: yes — this changes externally visible Git mutation
  sequencing and remote-freshness behavior
- **Rationale**: The optimization is narrow but touches a commit/push
  transaction. A full implementer plus root review is the smallest safe lane;
  a fast profile must not infer Git remote semantics.
- **Escalate when**: the change needs a new Git abstraction, changes force-push
  policy, changes atomic-commit flows, or removes a remote fetch without a
  deterministic state test.

## Why this matters

The primary manual Commit & Push flow refreshes local state inside
`GitManager.commitLocallyAsync`, refreshes the repository again in the action
coordinator before pushing, then refreshes again after pushing. It also checks
remote status before and after the push, and each remote check runs `git fetch`.
This makes the user wait for state that is either already known or needed only
after the mutation. The goal is to preserve commit/push correctness while
removing duplicate local reads from the critical path; Plan 075 owns any
cross-project overlap.

## Current state

- `GitMenuBar/App/MainMenuActionCoordinator.swift:374-421` currently does:

  ```swift
  let commitResult = await commitLocally(message)
  await refreshRepository()
  await refreshRemoteStatus()
  // check remote-ahead state, then push
  let pushResult = await pushToRemote()
  await refreshRepository()
  await refreshRemoteStatus()
  ```

- `GitMenuBar/App/MainMenuActionCoordinator.swift:448-449` calls
  `gitManager.commitLocallyWithFallbackAsync(message)` without passing the
  existing `skipUIUpdates` capability.
- `GitMenuBar/Services/Git/GitManager.swift:326-368` performs the commit and,
  unless `skipUIUpdates` is true, immediately runs local commit-count,
  working-tree, and branch updates.
- `GitMenuBar/Services/Git/GitManager.swift:161-183` defines a full selected
  refresh as working-tree state, branch state, remote URL, and commit history.
- `GitMenuBar/Services/Git/GitBranchService+State.swift:224-256` defines
  remote status as `git fetch` followed by a left/right count. Do not assume
  that a successful push alone populates every displayed remote flag without a
  test.
- `GitMenuBar/App/MainMenuActionCoordinator+AtomicCommits.swift` has a separate
  atomic-commit flow. It is not part of this plan and must retain its current
  sequencing.

For a normal staged Commit & Push, the current path can launch roughly 30+
Git child processes before hooks and the path-scoped monitor refresh. The exact
number is a measurement result, not an acceptance assumption; use Plan 073's
trace where available.

## Commands and evidence

| Purpose | Command | Expected result |
|---|---|---|
| Drift | `git diff --stat acad442..HEAD -- GitMenuBar/App/MainMenuActionCoordinator.swift GitMenuBar/Services/Git/GitManager.swift GitMenuBar/Services/Git/GitBranchService+State.swift GitMenuBarTests/MainMenuActionCoordinatorTests.swift GitMenuBarTests/GitManagerRefreshTests.swift` | Empty or understood drift only |
| Scoped feedback | `make agent-check` | Changed Swift lint and Debug build pass |
| Behavior tests | `make test` | XCTest suite passes |
| Merge gate | `make lint && make test` | Both commands pass |
| Guidance | `make guidance-check` | Guidance validation passes |
| Hygiene | `git diff --check` | No whitespace errors |

## Unit contract

**Objective:** Reduce duplicate local refresh work in the primary manual
`Commit & Push` transaction while preserving the resulting commit, push,
remote-ahead decision, local/remote failure behavior, and published selected
state.

**In scope:** `MainMenuActionCoordinator`'s primary manual commit path,
`GitManager`'s existing `skipUIUpdates` call path, focused action/refresh tests,
and a narrow command-count seam only if tests cannot observe ordering otherwise.

**Out of scope:** project switching, a queue or actor, automatic fetching
policy, atomic commits, pull/rebase, branch operations, force-push policy,
history model changes, caches, and UI redesign.

**Integration:** no merge or push is authorized by this plan; the implementer
leaves its isolated worktree and branch intact for review.

## External-state addendum

- **Authority:** the actual local worktree/index and configured remote remain
  the source of truth. UI state may lag only during an explicitly measured
  follow-up refresh.
- **Identity:** the current selected repository path and branch at the start of
  the primary action. Plan 075 will make this identity immutable across a
  selection change; this plan keeps the existing switch guard.
- **Scope:** only the current repository's staged/unstaged changes and current
  branch. Do not broaden staging or push targets.
- **Preflight:** preserve the existing status/auto-stage checks and the single
  remote-ahead check required before pushing.
- **Idempotency:** do not re-run `git commit` after it has succeeded. Preserve
  the existing push retry/force-push behavior exactly; a process failure must
  not be interpreted as a successful remote mutation.
- **Failure:** if commit succeeds and push fails, keep the local commit, refresh
  local state, report push failure, and keep retry available. Do not roll back
  or add a new automatic retry.
- **Concurrency:** this plan keeps the current global project-switch guard and
  must not introduce overlapping mutation/read work for the same repository.
- **Destructive actions:** do not add resets, force pushes, branch deletion, or
  any new destructive behavior.

## Steps

### Step 1: Characterize the exact existing primary flow

Use Plan 073's trace if available and read every caller of
`commitLocallyWithFallbackAsync`, `refreshRepository`, and
`refreshRemoteStatus`. Confirm that this plan changes only the primary manual
commit path. Preserve the separate atomic-commit coordinator path.

**Verify**: `rg -n 'commitLocallyWithFallbackAsync|refreshRepository|refreshRemoteStatus|executeAtomicCommits' GitMenuBar/App GitMenuBar/Services/Git GitMenuBarTests` produces a caller map, and no atomic caller is included in the planned edit.

### Step 2: Stop the commit method from publishing duplicate intermediate state

Route the primary manual Commit & Push call through the existing
`skipUIUpdates` parameter. The commit method must still perform the commit and
return its `Result`; it must not skip preflight status, auto-staging, commit
failure handling, or the `isCommitting` lifecycle. Do not remove or repurpose
the parameter for atomic commits or unrelated callers.

Keep one explicit local refresh at a terminal point after the commit/push
decision. If a push fails after a successful commit, that terminal refresh is
still required before returning the failure so the UI shows the local commit.

**Verify**: `rg -n 'commitLocallyWithFallbackAsync|skipUIUpdates|updateLocalCommitCountAsync|updateUncommittedFilesAsync|updateBranchInfoAsync' GitMenuBar/App/MainMenuActionCoordinator.swift GitMenuBar/Services/Git/GitManager.swift` shows the existing parameter is used only for this narrow path, and `make agent-check` passes.

### Step 3: Remove the redundant full refresh before pushing

After the commit completes, perform the existing remote-ahead check needed to
decide whether to show sync options. Do not run a full repository refresh just
to obtain that flag: the remote-status operation already owns its fetch and
left/right count. The current branch does not change merely because a commit
was created, so the push target must remain the branch captured for this
transaction.

After a successful push, perform one full local refresh for working-tree,
branch, remote URL, and history. Preserve the existing post-push remote-status
call until a focused test proves that the push result and local state provide
the same displayed flags; if the trace shows it is safe to defer, document that
as the explicit follow-up boundary rather than silently deleting it.

Do not parallelize the remote check and push. The check may update remote refs,
and Git mutation ordering must remain serial.

**Verify**: focused tests show that the remote-ahead option still appears,
successful push still reaches the final success state, and a push failure still
leaves a local commit. The command trace shows no full selected refresh between
commit completion and the pre-push remote-ahead check.

### Step 4: Add regression coverage for ordering and failures

Use the existing temporary-repository and mocked-session patterns in
`MainMenuActionCoordinatorTests`. Add the smallest deterministic command
observation seam only if current tests cannot prove the removed refresh. Do not
add a general runner protocol; a DEBUG-only first-argument observer or a narrow
test hook is acceptable.

Cover:

- staged Commit & Push does not perform the pre-push full refresh;
- auto-staging still occurs before the commit;
- remote-ahead still returns `.committedAndNeedsSyncOptions`;
- successful push performs one final local refresh and reports success;
- push failure keeps the local commit and reports failure;
- atomic commit flows remain behaviorally unchanged.

Tests must not rely on sleeps, real network remotes, timing luck, or command
output containing credentials. Use a local bare repository only when the
existing integration tests already require it.

**Verify**: `make test` passes, including the new focused cases, and
`git diff --check` passes.

### Step 5: Re-measure and hand off to Plan 075

Repeat the Plan 073 Commit & Push scenario. Record the change in child-process
count, full-refresh count, critical-path duration, and main-thread time. Do not
claim that the project switch is fixed; the existing busy guard intentionally
remains until Plan 075.

**Verify**: `make lint && make test` passes and the handoff names the remaining
critical-path work, especially any post-push fetch that still blocks action
completion.

## Test plan

- Structural pattern: existing `MainMenuActionCoordinatorTests` and
  `GitManagerRefreshTests` with temporary repositories and deterministic async
  seams.
- Regression: no duplicate pre-push full refresh, preserved remote-ahead branch,
  preserved local-commit-on-push-failure behavior.
- Scope guard: atomic commits, pull/rebase, branch mutations, and push retry
  semantics remain covered by their existing tests and are not rewritten here.
- Verification: `make agent-check`, `make test`, `make lint && make test`,
  `make guidance-check`, and `git diff --check`.

## Done criteria

- [ ] Primary manual Commit & Push no longer performs a redundant full refresh
      before its remote-ahead decision.
- [ ] Commit/push result and failure semantics are unchanged.
- [ ] Atomic commit and unrelated Git workflows are unchanged.
- [ ] Deterministic regression coverage proves the new ordering.
- [ ] Plan 073 has a before/after measurement handoff.
- [ ] `make agent-check`, `make test`, `make lint && make test`,
      `make guidance-check`, and `git diff --check` pass.
- [ ] Only the in-scope files are modified, apart from the plan index.

## STOP conditions

Stop and report if:

- the drift check finds an unreviewed change in an in-scope file;
- removing the pre-push refresh changes the branch used for push or the
  remote-ahead decision;
- preserving UI state requires a new cache, event bus, or public Git protocol;
- a test cannot deterministically distinguish duplicate refreshes without
  sleeps or network timing;
- the safe solution changes force-push, rollback, staging scope, or atomic
  commit behavior;
- a push/commit failure can no longer distinguish local success from remote
  success;
- any verification command fails twice after a reasonable scoped fix.

## Maintenance notes

- Keep `skipUIUpdates` as an explicit opt-in; do not make all Git mutations
  suppress UI updates globally.
- Plan 075 must treat any remaining post-push refresh/fetch as an operation
  completion step bound to the original repository path.
- Reviewers should inspect every `await` between commit and push for accidental
  reads from mutable selected state before approving broader concurrency.
