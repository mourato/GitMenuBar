# ADR 0009: Path-bound Git operations across project selection

## Status

Accepted for the path-bound implementation introduced by Plan 075.

## Decision

GitMenuBar keeps one selected-project `GitManager`, but a Git action that can
outlive the current selection captures a `RepositoryOperationContext` before
its first suspension. The context contains the normalized repository path,
the branch name, and the selected-refresh generation.

The operation follows five boundaries:

1. **Capture identity.** Capture the context once; Git commands use its path
   and branch instead of reading mutable selected-project state after `await`.
2. **Admit the operation.** The coordinator records the active context and
   rejects duplicate primary actions. `canSwitchRepository(to:)` compares
   normalized paths: the same project remains blocked, while a different
   project is allowed only during a flow that is explicitly path-bound.
3. **Execute the mutation.** Context overloads on `GitManager` perform commit,
   push, pull, status, and refresh work against the captured path. Branch
   preflight rejects a stale context before mutation.
4. **Publish the result.** `GitRefreshSession` gates refresh publication by
   path and generation. Coordinator alerts, success, and operation status use
   the same current-context gate. Repository selection clears transient action
   UI state before the new project's refresh publishes.
5. **Collect evidence.** Runtime claims require the signposts and manual
   scenarios in the profiling skill; a passing test or build is not a runtime
   baseline.

Manual commit/push and sync/pull flows may switch to another project after
their operation is path-bound. AI generation and atomic/hunk flows remain
selection-blocking because they still read mutable selected state or use
unbound Git APIs. They must become path-bound before their admission policy is
relaxed.

`GitCommandRunner` serializes individual Git processes per normalized directory
with a shared semaphore. This is intentionally a command-level safety
boundary, not a transaction-wide lease. Keep it until measurement shows path
churn or a transaction-level invariant requires a stronger owner; then replace
it with the smallest measured mechanism that covers that invariant.

## Consequences

- A late completion from project A cannot mutate project B's selected snapshot
  or transient action state.
- Switching projects is responsive during safe path-bound flows, while flows
  that are not yet safe remain conservatively blocked.
- New Git action entry points must choose their admission policy and context
  overload explicitly; an unscoped post-`await` read is a correctness bug.
- The per-directory semaphore prevents overlapping Git processes for one
  directory, but does not promise atomicity across a multi-command flow.

## Required regression coverage

`MainMenuActionCoordinatorPathBoundTests` must keep an A/B test that blocks a
commit with a checked continuation, performs the real repository-switch reset,
and asserts all of the following:

- commit and push remain on A;
- a duplicate primary action is skipped;
- A's completion callback fires once;
- A's late status, success, and alert do not leak into B; and
- atomic/unbound work still blocks switching to B.

Use deterministic continuations and observable paths. Do not use sleeps or
assert only the fake manager's mutable selected path.

## Runtime evidence

Use Instruments on a real local repository with the app's Performance log
enabled. For push/pull scenarios, use a disposable local bare remote or a
remote whose mutation is explicitly safe. Capture at least these scenarios,
with three warm runs per scenario:

1. manual commit without push;
2. commit and push with no remote-ahead branch;
3. start A's commit, select B while the Git process is in flight, and wait for
   A to finish;
4. sync/pull and push.

Inspect `primary.action`, `primary.commit`, `primary.remote_status`,
`primary.push`, and `git.command` signposts. Record the observed phase times,
Git command count, main-actor work, and whether switching was admitted. Store
only the summarized result in the handoff; keep trace files and repositories
out of source control.
