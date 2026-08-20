# Plan 075: Switch projects while path-bound Git actions finish safely

> **Executor instructions**: Follow this brief step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the **STOP conditions** section occurs, stop and
> report — do not improvise. This is the high-risk concurrency slice. When
> done, update the local status row in `plans/README.md`; leave the isolated
> worktree and branch intact for root review.
>
> **Drift check (run first)**: `git diff --stat acad442..HEAD -- GitMenuBar/App/MainMenuActionCoordinator.swift GitMenuBar/Pages/MainMenu/MainMenuActions.swift GitMenuBar/App/StatusBarController.swift GitMenuBar/App/GitMenuBarApp.swift GitMenuBar/Services/Git/GitManager.swift GitMenuBar/Services/Git/GitRepositoryContext.swift GitMenuBar/Services/Git/GitExecution.swift GitMenuBar/Services/Git/ProjectMonitorStore.swift GitMenuBarTests/MainMenuActionCoordinatorTests.swift GitMenuBarTests/GitManagerRefreshTests.swift GitMenuBarTests/RepositorySelectionCoordinatorTests.swift`
> If any in-scope file changed since this plan was written, compare the
> **Current state** excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P0
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: Plans 073 and 074; Plans 050–053, 059–063, 066–071 are DONE
- **Category**: concurrency / perf / correctness
- **Planned at**: commit `acad442`, 2026-08-19
- **Finding ID**: `path-bound-git-actions-project-switching`
- **Publication**: local
- **Parent issue**: none
- **Issue**: none
- **Integration**: `main`; merge and push require explicit user authorization

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `High/Full`
- **Parallelizable**: no — selection, mutation identity, refresh admission,
  monitor publication, and UI action state form one concurrency contract
- **Reviewer required**: yes — this changes shared Git state and must receive
  root-session review plus the full repository gates
- **Rationale**: The requested behavior crosses the MainActor UI, mutable
  selected-repository state, synchronous Git processes, remote mutation, and
  path-scoped monitor snapshots. A full implementer is the narrowest safe
  profile; do not split this plan across concurrent implementers.
- **Escalate when**: the solution needs a second `GitManager`, a persisted
  queue, an event bus, a new Git runner protocol, unsafe Sendable escapes, broad
  automatic fetching, or a new user-visible queue UI.

## Why this matters

Today the sidebar remains clickable but project selection is rejected while any
primary action is active. Removing that guard alone is unsafe: the current
`GitManager` reads a mutable `UserDefaults`-backed repository path, and the
unscoped refresh/remote-status calls after a commit can operate on whichever
project is selected when they resume. The result could be a delayed refresh of
the wrong project or, worse, a push targeted at project B after the commit was
created in project A.

This plan makes the in-flight action path-bound, lets selection of another
project proceed immediately, and preserves serialization for Git work that
touches the same worktree. It deliberately does not build a general-purpose
queue UI or create one `GitManager` per monitored project.

## Current state

- `GitMenuBar/App/MainMenuActionCoordinator.swift:97-103` treats the whole
  primary action as global busy state and makes `canSwitchRepository` false.
- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift:194-222` returns before the
  selection transaction when that guard is false. The AppKit and external-open
  paths use the same property through `StatusBarController` and
  `GitMenuBarApp`.
- `GitMenuBar/Services/Git/GitRepositoryContext.swift:15-27` reads the current
  path from `UserDefaults`; this is appropriate for selected UI state but not
  for a long-lived mutation that can suspend across a project switch.
- `GitMenuBar/Services/Git/GitManager.swift:242-274` already owns a selected
  refresh task, generation, path identity, and guarded publication through
  `GitRefreshSession`. Reuse that pattern for selected reads; do not create a
  second refresh owner.
- `GitMenuBar/Services/Git/GitManager.swift:755-825` uses a session path only
  when a session is supplied; the ungated APIs read the mutable selected path.
- `GitMenuBar/Services/Git/GitManager.swift:605-659` captures path and branch
  at push entry, but the surrounding action flow still invokes later unscoped
  refresh and remote-status work.
- `GitMenuBar/App/StatusBarController.swift:89-94` already sends completed
  commit paths to `ProjectMonitorStore.refresh(path:)`, which is a useful
  path-scoped completion seam for actions that finish after the user selects a
  different project.
- `docs/adr/0004-multi-project-monitoring-snapshots.md:3-5` requires one
  selected `GitManager` and lightweight per-path monitor snapshots. The plan
  must preserve that boundary.
- `GitMenuBarTests/GitManagerRefreshTests.swift` covers stale selected-refresh
  publication, but no test currently holds a mutation open while selecting a
  second repository. `MainMenuActionCoordinatorTests.swift:11-25` asserts the
  old global switch block and must be replaced with concurrency-specific cases.

## Commands and evidence

| Purpose | Command | Expected result |
|---|---|---|
| Drift | `git diff --stat acad442..HEAD -- GitMenuBar/App/MainMenuActionCoordinator.swift GitMenuBar/Pages/MainMenu/MainMenuActions.swift GitMenuBar/App/StatusBarController.swift GitMenuBar/App/GitMenuBarApp.swift GitMenuBar/Services/Git/GitManager.swift GitMenuBar/Services/Git/GitRepositoryContext.swift GitMenuBar/Services/Git/GitExecution.swift GitMenuBar/Services/Git/ProjectMonitorStore.swift GitMenuBarTests/MainMenuActionCoordinatorTests.swift GitMenuBarTests/GitManagerRefreshTests.swift GitMenuBarTests/RepositorySelectionCoordinatorTests.swift` | Empty or understood drift only |
| Scoped feedback | `make agent-check` | Changed Swift lint and Debug build pass |
| Tests | `make test` | XCTest suite passes, including overlap regressions |
| UI preview gate | `make check-preview` | Preview coverage check passes; use the documented explicit candidate workaround only for the known clean-tree script baseline |
| Merge gate | `make lint && make test` | Both commands pass |
| Guidance | `make guidance-check` | Guidance validation passes |
| Hygiene | `git diff --check` | No whitespace errors |

## Unit contract

**Objective:** Selecting project B during a commit/push for project A changes
the selected UI promptly; A's complete mutation remains targeted at A; no A
result publishes into B; and same-repository Git operations remain serialized.

**In scope:** primary manual commit/push action state, immutable repository
operation identity, selected-refresh admission, path-scoped completion, the
selection busy guard, and deterministic concurrency tests.

**Out of scope:** atomic commit redesign, pull/rebase redesign, branch
management redesign, automatic remote fetch policy across all projects, a
persisted/offline queue, queue UI, per-project `GitManager` instances, cache,
database, daemon, or new dependency.

**Integration:** no merge, push, branch deletion, or worktree cleanup is
authorized by this plan. The implementer leaves its isolated worktree and
branch intact for root review.

## External-state addendum

- **Authority:** the actual local worktree/index and configured remote are the
  authority. Queue state is process-local coordination only; it must never
  claim a commit or push succeeded without the Git result.
- **Identity:** an immutable `RepositoryOperationContext` must contain the
  normalized repository path and the branch/ref target captured before the
  operation. Credentials continue through the existing provider and are never
  stored in queue entries, logs, plans, or persistence.
- **Scope:** the operation may read and mutate only that repository path and
  captured branch target. A later selected path must not alter it.
- **Preflight:** immediately before a queued mutation begins, verify that the
  repository still exists and that the expected branch/ref target is unchanged.
  If a queued operation is stale or the branch changed, fail closed with a
  normal user-visible error; do not silently retarget it.
- **Idempotency:** queue entries exist only in memory. Do not enqueue duplicate
  commit/push work from repeated UI events. Once `git commit` succeeds, record
  that phase and never create a second commit while retrying the push.
- **Failure:** preserve the existing partial-success contract: a local commit
  may remain when push fails. Publish failure only to the original repository
  if it is still selected; otherwise refresh its monitor snapshot and make the
  result available through the existing path-scoped status mechanism.
- **Concurrency:** serialize commit, push, pull, branch mutation, fetch, and
  selected/monitor refreshes that target the same worktree. Allow at most the
  requested cross-project overlap: one background mutation for A plus the
  selected local refresh for B. Do not create unbounded task groups or polling.
- **Destructive actions:** do not add rollback, reset, force push, branch
  deletion, or automatic retries. Do not cancel an in-flight commit/push after
  it has started; cancellation can leave remote state uncertain. Cancel or
  supersede stale reads only.

## Recommended design boundary

Use the smallest path-keyed operation coordinator that the existing flows
require. It may be a private actor or a narrowly scoped operation scheduler,
but it must not become a generic command bus.

The coordinator must accept immutable, `Sendable` operation data and return
immutable results. Do not pass `GitManager`, SwiftUI state, or an unstructured
closure that reads `storedRepoPath` after an `await` into a background actor.
Reuse the existing `GitCommandRunner` and Git services; add path/context
parameters or nonisolated worker methods where necessary instead of copying
commit/push command sequences.

The selected `GitManager` remains the UI facade. Its selected publications use
the existing `GitRefreshSession` generation/path gate. A completed operation
checks the captured context against the current selection before publishing
alerts, success, operation progress, or selected Git state. If the context is
not selected, use the existing `ProjectMonitorStore.refresh(path:)` path-scoped
completion instead.

The queue is internal and process-local. No visible queue, persistence, retry
history, cache, notification bus, or new project manager is justified by this
request.

## Steps

### Step 1: Map every mutation and refresh overlap before editing

Audit all callers of `commitLocallyWithFallbackAsync`, `pushToRemoteAsync`,
`refreshAsync`, `refreshSelectedRepository`, `checkRemoteStatusAsync`,
`ProjectMonitorStore.refresh`, and `ProjectMonitorStore.fetchAll`. Identify
which operations can target the same path while a primary action is active.

Keep the current documented monitor boundary in mind: local status snapshots
may refresh, but remote fetch remains user-triggered. Do not broaden that
policy while solving selection latency.

**Verify**: `rg -n 'commitLocallyWithFallbackAsync|pushToRemoteAsync|refreshAsync|refreshSelectedRepository|checkRemoteStatusAsync|ProjectMonitorStore|fetchAll' GitMenuBar GitMenuBarTests --glob '*.swift'` produces a written overlap map in the implementation handoff; no caller is changed by assumption.

### Step 2: Introduce immutable operation identity

Create the smallest value type or existing-context extension needed to carry
normalized repository path and branch/ref target across awaits. Make it safe to
cross the Swift 6 complete-concurrency boundary. Capture it before the action
starts, not after a refresh or push has suspended.

Update the primary manual commit/push path to use this context for every Git
mutation and every post-mutation refresh. Any helper that still reads
`storedRepoPath`, `repositoryContext.repositoryPath`, or selected branch state
after an await is not path-bound and must be fixed or excluded from the queued
operation.

**Verify**: `rg -n 'storedRepoPath|repositoryPath|currentBranch|refreshAsync\(|checkRemoteStatusAsync\(' GitMenuBar/App/MainMenuActionCoordinator.swift GitMenuBar/Services/Git/GitManager.swift` shows each in-flight primary-action use either captures immutable context before suspension or publishes through a current-session gate; `make agent-check` passes.

### Step 3: Serialize same-repository work and admit a different selection

Add the narrow operation coordinator/scheduler. Its rules are:

- same normalized path: mutation and refresh work execute in order;
- different path: project selection and its local selected refresh may proceed
  while A's push is waiting on the remote;
- active mutation count: one at a time for the initial implementation, with
  one selected local read for the newly selected project allowed alongside it;
- stale selected refreshes: use the existing generation/path cancellation and
  publication gates;
- no unbounded queue: coalesce obsolete refreshes and reject duplicate primary
  mutations rather than accumulating identical work.

Remove only the busy guard that blocks changing the selected project. Keep a
busy guard for starting a second mutation against the same path. Update all
selection entry points that use `canSwitchRepository`, including the status-bar
picker and external-folder path, so they share one admission rule.

Do not let selection itself wait for A's final history or remote refresh. B's
selected state should reset and use the existing progressive fast/detail
refresh behavior immediately.

**Verify**: a deterministic overlap test can select B before A's operation
releases its gate; B becomes current and reaches its fast refresh; the test
also proves that a second A mutation is not started or duplicated.

### Step 4: Gate completion publication by repository identity

When A's mutation finishes after B is selected:

- do not write A's staged/unstaged files, branch, history, remote flags,
  operation status, alert, or success into B's selected `GitManager` state;
- refresh A's compact monitor snapshot through the existing path-scoped
  callback;
- retain enough result state for the original action to resolve exactly once;
- if the user switches back to A, admit the selected refresh after A's queued
  mutation completes rather than running two conflicting reads.

When A remains selected, preserve the current success/failure UI and operation
progress. Do not add a second notification system or persist action results.

**Verify**: tests use distinct A/B paths and assert that late A completion
cannot change B's branch, files, remote flags, history, operation status, or
alert. They also assert that A's monitor refresh occurs once after completion.

### Step 5: Add deterministic concurrency regression tests

Extend `MainMenuActionCoordinatorTests` and `GitManagerRefreshTests`, or add a
focused `RepositoryOperationQueueTests` only if the scheduler has meaningful
independent state. Use an existing operation closure seam or add the smallest
DEBUG/test-only gate that pauses a fake operation without sleeping.

Cover:

- A Commit & Push starts, B is selected, and B renders current state before A
  completes;
- A's push still uses A's path and branch after B is selected;
- late A refresh/state publication is rejected while B is current;
- A's local commit remains visible through A's monitor snapshot after a push
  failure;
- selecting A again while A is active does not overlap same-path Git work;
- a canceled/superseded selected refresh resolves and cannot signal stale
  completion;
- duplicate clicks do not enqueue duplicate commits or pushes.

Tests must not use sleeps, real remote-network timing, persisted queue state,
or secret values. A temporary local bare remote is acceptable only for an
existing integration pattern that needs actual push semantics.

**Verify**: `make test` passes repeatedly, and the overlap tests fail against
the old global guard/path-sensitive bug before the implementation and pass
after it without timing luck.

### Step 6: Validate UI and resource behavior

Run the full command table. Manually exercise two real local repositories:

- start Commit & Push in A;
- immediately select B and confirm the project name, working-tree state, and
  branch belong to B;
- wait for A to finish and confirm B does not flash A's success/error state;
- return to A and confirm its final state is current;
- repeat with push failure and with a slow history refresh.

Use Instruments from Plan 073 to confirm the new behavior does not create
unbounded Git processes, render storms, or main-actor blocking. The expected
steady state is one A mutation process/sequence plus one B local refresh,
with same-path work serialized.

**Verify**: `make agent-check`, `make check-preview`, `make test`,
`make lint && make test`, `make guidance-check`, and `git diff --check` all
pass; manual results and any known clean-tree preview-script limitation are
recorded in the handoff.

## Test plan

- Structural patterns: `GitManagerRefreshTests` for generation/path gating and
  `MainMenuActionCoordinatorTests` for action state; model new deterministic
  gates after existing `selectedRefreshOperation` seams.
- Required regression: A/B overlap, path-correct push, stale publication
  rejection, same-path serialization, duplicate-action suppression, and
  partial local-commit/push-failure behavior.
- Concurrency review: inspect every actor hop and every `await` in the queued
  operation for mutable selected-state reads.
- Verification: `make agent-check`, `make check-preview`, `make test`,
  `make lint && make test`, `make guidance-check`, and `git diff --check`.

## Done criteria

- [ ] Selecting B during A's Commit & Push is admitted immediately.
- [ ] A's entire mutation remains bound to A's normalized path and branch.
- [ ] Same-path Git mutations/fetches/refreshes do not overlap.
- [ ] Stale A publications cannot overwrite B's selected state or UI feedback.
- [ ] A completion updates its path-scoped monitor state exactly once.
- [ ] No persisted queue, per-project `GitManager`, event bus, cache, or new
      dependency was introduced.
- [ ] Deterministic overlap tests cover the failure and cancellation cases.
- [ ] `make agent-check`, `make check-preview`, `make test`,
      `make lint && make test`, `make guidance-check`, and `git diff --check`
      pass.
- [ ] Only the in-scope files are modified, apart from the plan index.

## STOP conditions

Stop and report if:

- the drift check finds an unreviewed change in an in-scope file;
- path identity cannot be made immutable without creating a second
  `GitManager` or changing unrelated public Git APIs broadly;
- any operation can still read the selected path/branch after an await;
- same-path `git fetch`, push, commit, or refresh can overlap without a
  proven Git-safe boundary;
- the scheduler requires unbounded task groups, polling, persistent queue
  state, a new dependency, or unsafe `@unchecked Sendable`/`nonisolated(unsafe)`
  state without a documented invariant and removal plan;
- a canceled mutation could be reported as successful or retried without
  knowing whether the remote changed;
- a late A publication can alter B's selected state or user-visible feedback;
- tests require sleeps, network timing, or secrets;
- `make check-preview`, `make test`, or `make lint && make test` fails twice
  after a reasonable scoped fix.

## Maintenance notes

- Keep `GitManager` as the selected-repository facade and
  `ProjectMonitorStore` as the lightweight per-path snapshot owner, per ADR
  0004.
- Any future Git mutation must enter the same path-identity and same-worktree
  serialization boundary; do not add a direct unscoped `Task` around `git`.
- Do not expand this into a visible queue until users need to manage multiple
  pending mutations. The first useful behavior is immediate selection with
  safe completion.
- Reviewers should inspect push target capture, remote fetch ordering,
  cancellation, task lifetime, and every publication guard before approving
  integration.
