# Plan 063: Keep sidebar monitor reads compact

> **Executor instructions:** Read this plan completely before editing. This
> plan deliberately trades line-level diff decoration in the Projects sidebar
> for a fast, bounded project attention snapshot. The selected project keeps
> detailed working-tree line diffs through `GitManager`. Do not restore the
> sidebar detail by adding a background cache or a second enrichment service.
>
> **Drift check (run first):** `git diff --stat f2c84e5..HEAD -- GitMenuBar/Models/ProjectStatusModels.swift GitMenuBar/Services/Git/ProjectMonitorStore.swift GitMenuBar/Components/Projects/ProjectsSidebarView.swift GitMenuBarTests/ProjectStatusReaderTests.swift GitMenuBarTests/MonitoredProjectsStoreTests.swift GitMenuBar/Services/Git/WorkingTreeParser.swift plans`
> Plan 061 must be complete first because it moves seed off the opening path;
> this plan then reduces the work performed by each automatic monitor read.

## Status

- **Priority:** P1
- **Effort:** M
- **Risk:** MEDIUM
- **Depends on:** Plan 061; Plan 057 (Swift 6.2 baseline); Plan 053 (DONE)
- **Category:** perf / sidebar UX / Git reads
- **Planned at:** commit `f2c84e5`, 2026-08-07

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: Medium / Full
- **Parallelizable**: no with Plan 061; yes with Plan 062 after Plan 061,
  provided the worktree is isolated because neither plan should rewrite the
  other's shared files.
- **Reviewer required**: yes — review data semantics and the selected/sidebar
  boundary because this changes what automatic snapshots compute and display.
- **Rationale**: The monitor's job is lightweight attention state, but dirty
  projects currently trigger numstat plus a full read of every untracked file
  merely to decorate a sidebar row. The existing ADR separates this snapshot
  from selected-project full detail; use that boundary instead of inventing a
  cache.
- **Escalate when**: a caller other than the sidebar needs monitor line diffs,
  compact status cannot preserve counts/error behavior, or product direction
  requires retaining line-level sidebar decoration.
- **Reuse → extend → create**: reuse `ProjectStatusSnapshot`, the existing
  reader/parser, and shared sidebar controls; extend the reader with one
  compact-read boundary; create no second snapshot model or enrichment store.

## Why it matters

`ProjectStatusReader.read` first runs porcelain status, then calculates line
diffs for dirty projects. For untracked files, `WorkingTreeParser` reads
every file into memory to count lines. With up to 20 monitored projects, total
cost grows with repository contents rather than the small status data the
sidebar needs.

The sidebar needs project name, availability, branch/upstream state,
changed-file counts, and attention status. It does not need exact
additions/deletions; the selected-project working-tree screen already provides
that detail. This plan makes that boundary explicit so large untracked files
cannot delay or churn automatic project monitoring.

## Current state

- `GitMenuBar/Models/ProjectStatusModels.swift:167-205` builds
  `ProjectStatusSnapshot` from porcelain status and calls `readLineDiff`
  whenever the tree is dirty.
- `ProjectStatusModels.swift:207-249` runs numstat and then
  `lineDiffForUntrackedFiles` for each untracked path.
- `GitMenuBar/Services/Git/WorkingTreeParser.swift:73-80,107-127` reads each
  untracked file synchronously to calculate line counts.
- `GitMenuBar/Services/Git/ProjectMonitorStore.swift:106-136` uses the
  reader for automatic seed/refresh and bounds concurrent projects to two.
- `GitMenuBar/Components/Projects/ProjectsSidebarView.swift:196-200` shows
  `WorkingTreeLineDiffView` for every dirty monitor snapshot; its
  accessibility label also reports added/deleted lines at lines 225-232.
- `GitManager` uses `WorkingTreeParser` for selected-repository detail. That
  path is outside this plan and must retain line-diff behavior.

## Product and technical contract

1. Automatic monitor reads collect only existing compact status fields: branch,
   staged/unstaged/untracked counts, upstream/ahead/behind, error, and refresh
   timestamp.
2. Automatic monitor reads do not run numstat or read untracked file contents.
3. The Projects sidebar no longer renders additions/deletions for compact
   monitor rows. It continues to show changed-file counts and attention/error
   state. Selected-project detail is unchanged.
4. `ProjectStatusSnapshot` remains the model boundary unless a field is
   demonstrably dead after the caller scan. Do not create a second snapshot
   type or cache.
5. Existing status parsing, invalid/non-Git filtering, refresh cadence, and
   maximum two-project concurrency remain unchanged.
6. Manual/selected detail remains the only place where line-level diff work is
   requested for the current project.

## Scope

**In scope (the only implementation files for this plan):**

- `GitMenuBar/Models/ProjectStatusModels.swift`
- `GitMenuBar/Services/Git/ProjectMonitorStore.swift`
- `GitMenuBar/Components/Projects/ProjectsSidebarView.swift`
- `GitMenuBarTests/ProjectStatusReaderTests.swift`
- `GitMenuBarTests/MonitoredProjectsStoreTests.swift`
- `plans/063-use-compact-sidebar-monitor-reads.md`
- `plans/README.md`

**Out of scope:**

- `GitMenuBar/Services/Git/GitManager.swift` selected working-tree reads and
  line-diff behavior.
- Project monitoring persistence, timer cadence, concurrency limit, or remote
  fetch behavior.
- Background line-diff enrichment, custom cache, database, Git daemon, new
  dependency, or new snapshot store.
- History/commit diff views, AI diff parsing, and working-tree components
  outside the Projects sidebar.

## Commands and evidence

| Purpose | Command | Expected result |
|---|---|---|
| Drift | `git diff --stat f2c84e5..HEAD -- <scope>` | Empty or understood Plan 061/057 drift only |
| Focused loop | `make agent-check` | Changed Swift lint and Debug build pass |
| Tests | `make test` | Reader, monitor, and selected-detail tests pass |
| Preview gate | `make check-preview` plus `./scripts/check-preview.sh GitMenuBar/Components/Projects/ProjectsSidebarView.swift` when the changed-file set is empty | Changed sidebar candidate retains preview coverage |
| Guidance | `make guidance-check` | `guidance-check: passed` |
| Hygiene | `git diff --check` | No whitespace errors |
| Merge gate | `make lint && make test` | Both commands pass |
| Performance | real monitored projects with large untracked files | no monitor file-content reads; duration/CPU delta recorded |

## Suggested executor toolkit

- `performance-profiling` for process/file-read comparison.
- `swiftui-expert-skill` and `swiftui-accessibility-audit` for sidebar
  state and label changes.
- `swift-conventions` and `test-strategy` for reader flags and fixtures.
- `apple-design` only if removing line decoration leaves a hierarchy gap;
  reuse existing Workbench tokens first.

## Ordered implementation steps

### 1. Inventory compact/detail callers

Run the drift check and
`rg -n 'ProjectStatusReader|lineDiff|WorkingTreeParser' GitMenuBar GitMenuBarTests`.
Confirm monitor snapshots are consumed by the Projects sidebar and selected
detail is provided by `GitManager`. Capture baseline monitor time and
process/file-read behavior on a repository with many untracked files.

**Verify:** no hidden production caller requires monitor line diffs; if one
exists, stop and reconcile the contract instead of silently removing data.

### 2. Add an explicit compact reader path

Add the smallest reader option needed to skip line-diff enrichment for monitor
reads, for example `includeLineDiff` on the existing `read` method. Keep
the full/test path explicit and preserve current failure/default values. The
compact path must return after status parsing; it must not call numstat or
`lineDiffForUntrackedFiles`.

Use the compact option from `ProjectMonitorStore.seed` and automatic
refresh/`fetchAll`. Do not change the existing two-project automatic bound,
sequential explicit-fetch behavior, or the snapshot publication generation
from Plan 061.

**Verify:** a temporary-repository test with a modified tracked file and a
large untracked file proves compact read preserves counts/branch/error fields
and returns zero line diff without reading file content. Full reader tests
retain line-diff expectations if the explicit full option remains needed.

### 3. Remove line-level decoration from compact sidebar rows

Stop rendering `WorkingTreeLineDiffView` for `ProjectStatusSnapshot` rows.
Keep changed-file counts, project name, branch/attention state, and errors.
Update the accessibility label to describe available status counts, not
unavailable additions/deletions. Do not remove the shared
`WorkingTreeLineDiffView`; selected working-tree and history surfaces use it.

If the row becomes visually sparse, use existing spacing, secondary text, and
Workbench tokens. Do not add a replacement metric requiring another Git query.

**Verify:** the sidebar preview shows clean, dirty, unavailable, and compact
rows with no misleading `+0/-0`; accessibility labels do not claim unloaded
line data.

### 4. Preserve selected detail and validate the budget

Run the command table. Test automatic seed, 60-second refresh, explicit
monitor fetch, invalid recent paths, clean/dirty/untracked projects, and
selected-project working-tree details. Compare process count, file reads, and
time against the baseline. Check Plan 061's async seed still publishes the
compact snapshot correctly.

**Verify:** automatic monitor work is bounded by status reads, selected detail
still reports line diffs, and no new cache/worker/persistence layer exists.

## Test plan

- Update `ProjectStatusReaderTests` for compact/full reader behavior, dirty
  tracked/untracked fixtures, status failures, and unchanged branch/count
  fields.
- Update `MonitoredProjectsStoreTests` for compact snapshots and existing
  invalid-path/seed expectations.
- Run `make agent-check`, `make test`, `make check-preview`, and
  `make guidance-check`.
- If `make check-preview` hits the known clean-tree `files[@]`/Bash
  `set -u` failure, run the explicit sidebar candidate command from the
  table and record the script issue separately; do not fix it in this plan.
- Run `make lint && make test` before handoff.
- Manually verify sidebar labels and selected-project line-diff details on a
  large real repository.

## Done criteria

- Automatic monitor seed/refresh never performs line-diff numstat or reads
  untracked file contents.
- Sidebar rows no longer promise additions/deletions that compact snapshots
  do not contain; changed-file counts and attention/error status remain clear.
- Selected-project detail retains existing line-diff behavior.
- Tests, preview, agent, guidance, lint, and test gates pass, with measured
  process/file-read or latency improvement recorded.
- No custom cache, enrichment service, or parallelism change was introduced.

## STOP conditions

- A production caller outside the Projects sidebar depends on monitor line
  diffs.
- Removing line decoration creates a product requirement for an exact sidebar
  diff metric; obtain that decision instead of adding a new query.
- Compact reads cannot preserve existing error/count/branch semantics.
- Selected-project GitManager detail changes as a side effect.
- Plan 061/057 changed reader/monitor APIs and drift is not a small local
  reconciliation.

## Maintenance notes

The monitor is an attention snapshot, not a second selected-project Git
manager. Keep it cheap as new sidebar fields are proposed: first ask whether
the field comes from the existing compact status result. If it requires file
content or a new Git process, keep it in selected-project detail unless a
measured product need justifies a new plan.

## Local implementation evidence

- `ProjectStatusReader.read` keeps full line-diff behavior by default and now
  accepts `includeLineDiff`; monitor seed, refresh, and explicit fetch pass
  `false`.
- `ProjectsSidebarView` uses existing compact snapshot fields for branch,
  upstream, changed-file count, and accessibility status; it no longer renders
  `WorkingTreeLineDiffView` for monitor rows.
- `ProjectStatusReaderTests` covers a dirty tracked file plus a large
  untracked file and confirms compact counts/branch/error behavior with zero
  line diff; full reader expectations remain explicit.
- Local checks passed: `make agent-check`, `make test`, `make check-preview`,
  `make guidance-check`, `make lint && make test`, and `git diff --check`.
- Review remediation changed sidebar rows to use adaptive minimum height,
  readable changed-file counts, and honest unavailable/detached labels.
- Merged and pushed as `ba10841`; a large-repository file-read/timing
  comparison remains an operator handoff because this session has no
  controlled native performance measurement channel.
