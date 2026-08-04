# Plan 053: Batch compact status reads for monitored projects

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat b2beedd..HEAD -- GitMenuBar/Services/Git/ProjectMonitorStore.swift GitMenuBar/Models/ProjectStatusModels.swift GitMenuBarTests/MonitoredProjectsStoreTests.swift GitMenuBarTests/ProjectStatusReaderTests.swift`
> If any in-scope source file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: Plan 050 for the selected-project/monitor interaction;
  Plan 051 is recommended before parallel refresh changes
- **Category**: perf
- **Planned at**: commit `b2beedd`, 2026-08-04

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: yes — compact monitor reads are independent from the
  selected repository's full refresh once the selection contract is stable
- **Reviewer required**: no — the monitor has an immutable snapshot model and
  this plan keeps its existing bounded concurrency and no-auto-fetch policy;
  escalate if that policy changes
- **Rationale**: Each monitored project currently launches several sequential
  Git processes for one small sidebar snapshot. Git's NUL-delimited porcelain
  v2 already contains the branch, upstream, ahead/behind, and file-state
  information needed here, so one read plus a pure parser is the smallest
  useful optimization.
- **Escalate when**: preserving current detached/error behavior needs a new
  persistence model, unbounded concurrency, automatic network fetch, or a
  second source of project identity.

## Why this matters

The sidebar is intended to remain lightweight, but every automatic monitor
refresh currently performs a repository validation, status read, branch read,
detached-head fallback, upstream read, and ahead/behind read for each project.
With several monitored projects this creates avoidable Process launches and
can compete with the selected project's full refresh. The compact snapshot
only needs counts and attention state; one porcelain-v2 read per project can
provide those values without changing the existing `ProjectStatusSnapshot`
contract or adding a cache.

## Current state

- `GitMenuBar/Services/Git/ProjectMonitorStore.swift:31-41` validates every
  recent/current path with `rev-parse` during `seed`, then calls `refreshAll`,
  which reads the same projects again.
- `ProjectMonitorStore.swift:97-120` keeps a useful maximum of two concurrent
  status operations. Preserve that bound and its main-actor snapshot publish.
- `GitMenuBar/Models/ProjectStatusModels.swift:78-134` currently performs:

  ```swift
  rev-parse --show-toplevel
  status --porcelain -uall
  symbolic-ref --quiet --short HEAD
  rev-parse --short HEAD       // detached fallback
  rev-parse --abbrev-ref --symbolic-full-name @{u}
  rev-list --left-right --count @{u}...HEAD
  ```

  The reader then reduces output to `ProjectStatusSnapshot` counts and branch
  metadata.
- `ProjectStatusSnapshot` and its classification/reasons are the compact
  attention-state contract; do not add full working-tree files or history to
  it. ADR 0004 keeps full selected-repository state in `GitManager`.
- `ProjectMonitorStore.fetchAll()` at `ProjectMonitorStore.swift:85-95` is an
  explicit user action that fetches sequentially and then rereads a snapshot.
  Keep that network side effect explicit and do not parallelize fetches.
- `GitMenuBarTests/MonitoredProjectsStoreTests.swift:77-100` already verifies
  that seed ignores non-Git recent projects; preserve this behavior while
  removing duplicate validation work.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Reader inventory | `rg -n 'ProjectStatusReader|isValidRepository|status|symbolic-ref|rev-list|fetchAll|refreshAll' GitMenuBar/Services/Git/ProjectMonitorStore.swift GitMenuBar/Models/ProjectStatusModels.swift GitMenuBarTests/MonitoredProjectsStoreTests.swift` | all current reader/seed/fetch paths are identified |
| Porcelain fixture inspection | `/usr/bin/git status --porcelain=v2 --branch --untracked-files=all -z | od -An -tx1 -c | sed -n '1,30p'` | NUL record boundaries and branch header fields are visible |
| Monitor tests | `make test` | all monitor and repository tests pass |
| Scoped validation | `make agent-check` | changed Swift lint passes and the Debug build succeeds |
| Guidance validation | `make guidance-check` | exit 0 |
| Merge gate | `make lint && make test` | both commands exit 0 |

## Suggested executor toolkit

- Use `test-strategy` for temporary repository fixtures and parser cases.
- Use `global:swift-conventions` for the NUL-delimited parser.
- Use `swift-concurrency` only if changing the existing bounded scheduler;
  prefer preserving the current `OperationQueue` bound.

## Scope

**In scope** (the only source files to modify):

- `GitMenuBar/Services/Git/ProjectMonitorStore.swift`
- `GitMenuBar/Models/ProjectStatusModels.swift`
- `GitMenuBarTests/MonitoredProjectsStoreTests.swift`
- `GitMenuBarTests/ProjectStatusReaderTests.swift` (create)

Plan metadata files:

- `plans/053-batch-project-monitor-status.md`
- `plans/README.md`

**Out of scope** (do not touch):

- `GitMenuBar/Services/Git/GitManager.swift` selected-project full refresh —
  Plans 050–052 own it.
- Sidebar layout/hit testing, snapshot fields, attention classification,
  sorting/grouping, project names, recents semantics, or a monitor cache.
- Automatic `git fetch`, fetch parallelism, background network work, or
  status-item badge policy.
- SwiftUI `MainMenuView` render invalidation. That is a possible follow-up
  only if Instruments shows it exceeds the measured budget after Git process
  reduction; do not add `debounce`, `EquatableView`, or a new presentation
  store speculatively.

## Git workflow

- Branch: `advisor/053-batch-project-monitor-status` (or the repository's
  current branch convention if the operator already supplied an isolated
  implementation branch).
- Keep the implementation to one logical commit if committing is requested;
  use the repository's Conventional Commit style, e.g.
  `perf(monitor): batch compact project status reads`.
- Do not push or open a PR unless the operator explicitly instructs it.

## Steps

### Step 1: Add a pure porcelain-v2 snapshot parser

Implement the smallest parser seam near the existing project-status models.
Parse `git status --porcelain=v2 --branch --untracked-files=all -z` without
newline splitting. Extract only the data needed by
`ProjectStatusSnapshot`:

- branch head and detached state;
- staged, unstaged, and untracked counts;
- whether an upstream exists;
- ahead and behind counts from `# branch.ab +N -M`.

Use the existing `ProjectStatusSnapshot` defaults for missing/unknown fields.
Preserve status failure handling: if the command fails, distinguish an
unavailable folder from a non-Git folder using the existing `FileManager`
check and keep the current error descriptions. Do not expose file paths or
full status records in the snapshot.

**Verify**:

- Add fixture tests for clean, staged, modified, untracked, mixed, detached,
  upstream/no-upstream, ahead/behind/diverged, malformed headers, and command
  failure.
- `rg -n 'split\(whereSeparator: \\.isNewline\)|porcelain=v2|branch\.ab' GitMenuBar/Models/ProjectStatusModels.swift GitMenuBarTests/ProjectStatusReaderTests.swift` → the new reader path uses NUL-safe records and the tests cover branch headers.

### Step 2: Make one reader call produce one complete compact snapshot

Update `ProjectStatusReader.read(project:now:)` to run the one porcelain-v2
status command and feed its output into the pure parser. Remove the separate
`rev-parse`, `symbolic-ref`, upstream, and `rev-list` reads from the normal
success path. If detached display currently uses a short hash, derive the
same display value from the available branch object-id field or keep one
explicit detached fallback only when the format cannot provide it; do not
silently display a different branch label.

Keep `lastRefreshedAt`, project display names, normalization, and
`lastErrorDescription` behavior unchanged. The reader remains synchronous on
the utility queue; do not move Git work to the main actor.

**Verify**:

- `rg -n 'runGitCommand' GitMenuBar/Models/ProjectStatusModels.swift` → the
  normal successful snapshot path contains one Git command invocation, with
  only an explicitly documented error/detached fallback if needed.
- `make test` → existing seed/classification tests and new reader tests pass.

### Step 3: Remove duplicate seed validation without changing filtering

`ProjectMonitorStore.seed` currently validates candidates and then refreshes
them again. Reuse the new reader result so each candidate is inspected once
while seeding, and persist only valid Git repositories as today. Keep the
existing test expectation that invalid recent folders are not seeded as
monitored projects. If the smallest safe change is to leave one validation
for a path whose status result cannot distinguish a folder error, document
that single exception rather than introducing another service layer.

Do not change `MonitoredProjectsStore` ordering, recents/monitoring separation,
or the meaning of Stop Monitoring/Remove Project.

**Verify**:

- `rg -n 'isValidRepository|seed\(|refreshAll\(' GitMenuBar/Services/Git/ProjectMonitorStore.swift` → seed no longer performs a full validation pass followed by a duplicate full refresh for the same candidates.
- `MonitoredProjectsStoreTests.testSeedIgnoresNonGitRecentProjects` (or its
  live equivalent) passes, and snapshots for valid candidates still appear.

### Step 4: Preserve bounded automatic refresh and explicit fetch

Keep the existing maximum of two concurrent compact status reads. If the
reader result can be published directly, retain the current main-actor merge
of `snapshots` and `isRefreshing` behavior. Do not add an unbounded task group,
poll more frequently than the existing 60-second timer, or fetch remotes in
`refreshAll`.

Keep `fetchAll()` sequential: each explicit fetch may mutate `.git`, so do not
run it concurrently with another fetch for the same repository or with an
automatic read that the current scheduler cannot coordinate safely. After a
fetch, reuse the new one-command reader.

**Verify**:

- `rg -n 'maxConcurrentOperationCount|args: \["fetch"\]|timeInterval' GitMenuBar/Services/Git/ProjectMonitorStore.swift` → the two-operation bound, 60-second timer, and explicit sequential fetch policy remain.
- Manual Debug check with several monitored projects: sidebar rows update,
  unavailable folders remain unavailable, and Fetch All remains explicit.

### Step 5: Measure the monitor reduction and run the gates

Use a representative set of 1, 3, and 10 monitored repositories and inspect
Git Process launches during `refreshAll`. Compare the current multi-command
reader with the one-command reader. Do not persist paths, command output,
credentials, or machine telemetry in this repository; record measurements in
the review/PR only.

Run `make agent-check`, `make guidance-check`, then `make lint && make test`.

**Verify**: all commands exit 0; the review notes the reduced command count
per monitored project and confirms that automatic refresh still has no network
side effect.

## Test plan

- Add `ProjectStatusReaderTests` with real temporary Git repositories and/or
  pure NUL-delimited fixtures for all snapshot states.
- Keep `MonitoredProjectsStoreTests` seed filtering, ordering, classification,
  and rename behavior green.
- Add one regression proving a monitored project with staged, unstaged, and
  untracked files produces the same counts as before.
- Run `make agent-check` and the final lint/test gate.

## Done criteria

- [ ] A successful compact monitor snapshot uses one status read per project
      in the normal path.
- [ ] Staged, unstaged, untracked, detached, upstream, ahead, behind, and
      diverged states retain their existing snapshot/classification behavior.
- [ ] Seed no longer validates and then rereads the same candidates.
- [ ] Automatic refresh remains bounded to two concurrent reads and does not
      fetch remotes.
- [ ] Fetch All remains explicit and sequential.
- [ ] New parser and regression tests pass.
- [ ] Before/after command-count evidence is recorded outside the repository.
- [ ] `make agent-check`, `make guidance-check`, `make lint`, and `make test`
      exit 0.
- [ ] No files outside the in-scope list are modified.
- [ ] `plans/README.md` status row for Plan 053 is updated only after done.

## STOP conditions

Stop and report instead of improvising if:

- Porcelain v2 output cannot preserve current branch, detached, count, or
  error semantics for a supported Git repository.
- A parser relies on newline splitting, loses NUL-delimited paths, or exposes
  full status paths in the compact model.
- Removing seed validation causes invalid folders to enter monitored projects
  or changes recents/monitoring persistence semantics.
- The optimization requires automatic fetch, unbounded parallelism, or a
  change to the status-item badge contract.
- The measured command count does not improve on representative repositories;
  stop before adding a cache or polling change.
- `make agent-check` or the final lint/test gate fails twice after a reasonable
  scoped correction.

## Maintenance notes

- Keep the compact snapshot reader independent from `GitManager`; selected
  project full state and monitored attention state have different freshness and
  ownership contracts.
- If future Git status fields are added, extend the pure parser and fixtures
  first. Do not reintroduce one subprocess per field.
- SwiftUI render invalidation remains deliberately unplanned. Add a follow-up
  only when Instruments demonstrates that `MainMenuRenderSnapshot.build` or
  broad `@EnvironmentObject` invalidation is a larger contributor than Git
  process latency after Plans 050–053.
