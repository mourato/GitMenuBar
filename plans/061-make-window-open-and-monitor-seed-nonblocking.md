# Plan 061: Make window opening and monitor seeding non-blocking

> **Executor instructions:** Read this plan completely before editing. Keep
> implementation scoped to the opening path and background monitor bootstrap.
> Do not solve selected-project loading or redesign the sidebar here. Update
> the ledger only after implementation and review pass.
>
> **Drift check (run first):** `git diff --stat f2c84e5..HEAD -- GitMenuBar/App/StatusBarController.swift GitMenuBar/Services/Git/ProjectMonitorStore.swift GitMenuBar/Models/ProjectStatusModels.swift GitMenuBar/Services/Git/UsageQuotaStore.swift GitMenuBarTests/MonitoredProjectsStoreTests.swift GitMenuBarTests/UsageQuotaStoreTests.swift Makefile scripts plans`
> Plan 057 is a repository-wide prerequisite. If it is still in progress,
> reconcile its live Swift/concurrency baseline before touching these files.

## Status

- **Priority:** P0
- **Effort:** L
- **Risk:** HIGH
- **Depends on:** Plan 057 (Swift 6.2 baseline); Plans 050–053 (DONE)
- **Category:** perf / app lifecycle / concurrency
- **Planned at:** commit `f2c84e5`, 2026-08-07

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: High / Full
- **Parallelizable**: no — lifecycle presentation, monitor bootstrap, and
  refresh throttling affect the same first-open budget and must be validated
  as one serial change.
- **Reviewer required**: yes — review MainActor boundaries, stale async
  results, persistence/filtering behavior, and first-open measurements.
- **Rationale**: The visible 200 ms fade is a deterministic delay, while the
  larger risk is synchronous Git work during `StatusBarController` startup.
  The existing monitor and quota stores are the smallest seams to fix these
  costs without a cache, daemon, or new dependency.
- **Escalate when**: background seed requires changing Git semantics, creating
  a second monitor owner, adding a custom cache, or allowing stale seed
  results to replace a newer refresh.
- **Reuse → extend → create**: reuse `WindowOpenTrace`, the existing bounded
  monitor queue, and quota test fakes; extend their lifecycle/session guards;
  create no new cache, worker abstraction, or telemetry service.

## Why it matters

The keyboard shortcut reaches `presentMainWindow`, but the window starts at
alpha `0` and takes `0.20` seconds to become visible. Separately,
`StatusBarController.init` calls `ProjectMonitorStore.seed` synchronously;
that method runs `git status`, line-diff enrichment, file reads, and project
persistence work before the app has finished becoming interactive. Every
window presentation can also start a quota refresh while the previous result
is still fresh.

This plan makes the first frame immediate and moves only existing background
work off the opening path. It does not promise that Git becomes faster; it
prevents nonessential Git and network work from blocking the user-visible
surface. The target is a measured p95 menu/main-window open under 150 ms on a
representative real repository, with no regression in monitor filtering or
quota correctness.

## Current state

- `GitMenuBar/App/StatusBarController.swift:620-647` sets window alpha to
  `0`, animates to `1`, and uses `windowPresentationDuration = 0.20`.
- `StatusBarController.init` calls
  `projectMonitor.seed(currentPath:recentProjects:)` before initialization
  returns. The call is synchronous even though `ProjectMonitorStore` is
  `@MainActor`.
- `GitMenuBar/Services/Git/ProjectMonitorStore.swift:31-55` creates a
  `ProjectStatusReader` and reads current/recent projects inline.
  `ProjectStatusReader` invokes synchronous `GitCommandRunner` work.
- `GitMenuBar/Models/ProjectStatusModels.swift:193-249` performs compact
  status plus dirty-project line-diff work. Plan 063 owns making that read
  cheaper; this plan only removes it from the opening path.
- `GitMenuBar/Services/Git/UsageQuotaStore.swift:80-87` cancels the previous
  refresh and starts another for every `.windowPresented` request. The store
  has a 120-second timer interval but no last-success guard for presentations.

## Product and technical contract

1. The window becomes visible at full alpha in the same presentation turn. Do
   not replace the fade with another delay, transition, or artificial sleep.
2. `StatusBarController` may schedule monitor seed work, but no Git process
   or file-content read may execute synchronously on the main actor as part of
   that scheduling call.
3. Seed results are applied only if they belong to the latest seed generation.
   A late seed cannot overwrite a newer refresh, project list, or selection.
4. Seed still filters invalid/non-Git recent paths exactly as today and keeps
   `MonitoredProjectsStore` ordering and persistence semantics.
5. A `.windowPresented` quota refresh is skipped while one is in flight or
   while a successful presentation refresh is younger than the existing
   `refreshInterval`. Manual refresh remains a force-refresh path.
6. Keep existing `WindowOpenTrace` instrumentation and add only timestamps
   needed to compare shortcut received, window visible, and first useful
   project data. Do not add telemetry infrastructure.

## Scope

**In scope (the only implementation files for this plan):**

- `GitMenuBar/App/StatusBarController.swift`
- `GitMenuBar/Services/Git/ProjectMonitorStore.swift`
- `GitMenuBar/Services/Git/UsageQuotaStore.swift`
- `GitMenuBarTests/MonitoredProjectsStoreTests.swift`
- `GitMenuBarTests/UsageQuotaStoreTests.swift`
- `plans/061-make-window-open-and-monitor-seed-nonblocking.md`
- `plans/README.md`

**Out of scope:**

- Selected-repository refresh phases, loading states, and skeletons; Plan 062
  owns those.
- Removing line-diff work from the monitor reader or changing sidebar detail;
  Plan 063 owns that behavior.
- Custom caches, SQLite, a Git daemon, debouncing, `EquatableView`, broad
  render-store changes, new dependencies, or network prefetching.
- Changing Git output, monitored-project persistence rules, credentials, or
  quota provider implementations.

## Commands and evidence

| Purpose | Command | Expected result |
|---|---|---|
| Drift | `git diff --stat f2c84e5..HEAD -- <scope>` | Empty or understood Plan 057 drift only |
| Focused loop | `make agent-check` | Changed Swift lint and Debug build pass |
| Tests | `make test` | Existing and new monitor/quota tests pass |
| Preview gate | `make check-preview` | No new SwiftUI file; on a clean tree, record the known empty-file-array baseline failure |
| Guidance | `make guidance-check` | `guidance-check: passed` |
| Hygiene | `git diff --check` | No whitespace errors |
| Merge gate | `make lint && make test` | Both commands pass |
| Performance | existing `WindowOpenTrace` plus repeated real-repo opens | p95 visible-open target under 150 ms, or remaining bottleneck recorded |

## Suggested executor toolkit

- `performance-profiling` for before/after timing and regression evidence.
- `swift-concurrency` for the async seed/session boundary.
- `macos-app-engineering` plus its project overlay for status-item/window
  lifecycle behavior.
- `swift-conventions` for touched Swift files.

## Ordered implementation steps

### 1. Capture the baseline and trace callers

Run the drift check, `git status -sb`, `git diff --check`, focused tests, and
the existing window-open measurement. Confirm every `seed` call, every
`windowPresented` quota request, and every alpha-animation caller. Record
cold and warm open behavior separately.

**Verify:** the baseline identifies whether the visible delay is dominated by
the fade, synchronous seed, or another caller; no unrelated dirty file is in
scope.

### 2. Remove the deterministic presentation delay

Change `presentMainWindow` so the window is made visible at alpha `1` in the
same turn. Remove the now-unused duration/reduced-motion animation path only
if no other caller uses it. Preserve activation, key-window behavior,
route-selection, presentation state, transparency handling, and trace
semantics.

**Verify:** repeated shortcut opens show no alpha transition and existing
focus/close/route behavior remains unchanged.

### 3. Make monitor seed asynchronous without changing its contract

Keep cheap candidate collection and `seedIfNeeded` persistence on the main
actor, then run `ProjectStatusReader` reads using the existing bounded
utility-queue pattern. Make seed awaitable for tests and schedule it from
`StatusBarController` instead of executing it inline in `init`.

Use a small generation/cancellation guard owned by `ProjectMonitorStore`:

- increment it for each seed/refresh replacement;
- capture the generation with candidate paths;
- publish snapshots and `isRefreshing` only when the generation is current;
- preserve invalid-path filtering and the existing “refresh if no snapshot”
  behavior without doing a second full read for the same candidate.

Do not use `Task.detached`, a new worker abstraction, or an unbounded task
group. Reuse the existing reader and bounded queue. The first await must occur
before any synchronous Git command is invoked.

**Verify:** `MonitoredProjectsStoreTests` awaits seed completion and still
proves invalid recent folders are ignored; source review confirms no
`GitCommandRunner` call remains on the seed caller's main-actor turn.

### 4. Throttle presentation-triggered quota refreshes

Add the smallest last-success/in-flight guard to
`UsageQuotaStore.refresh`. Apply it only to `.windowPresented`, using the
existing 120-second interval. Manual refresh bypasses the guard. Keep provider
concurrency, timeout, persisted-result merging, and error handling unchanged.

Add one deterministic test with existing fake providers: after a successful
presentation refresh, a second presentation refresh within the interval does
not invoke providers again. Do not use wall-clock sleeps; reuse the existing
async test seam or inject only a clock value if needed.

**Verify:** `UsageQuotaStoreTests` proves duplicate presentation opens do not
cancel/restart a fresh result, while explicit refresh still runs.

### 5. Measure and close the lifecycle loop

Run the command table. Measure at least ten cold-ish and ten warm shortcut
opens with a representative repository and record median/p95 for visible
window, first sidebar snapshot, and final selected-project refresh. Check a
non-Git current folder, invalid recent path, provider timeout, and reduced
motion setting.

**Verify:** the fade is gone, seed no longer blocks opening, stale seed results
cannot replace newer state, quota calls are bounded, and any remaining delay
has an identified owner for Plan 062 or a later measured plan.

## Test plan

- Update `MonitoredProjectsStoreTests` for async seed, invalid-path
  filtering, snapshot publication, and repeated seed/refresh generation.
- Add/update `UsageQuotaStoreTests` for in-flight and fresh-result throttling,
  manual-refresh bypass, and existing provider failures.
- Run `make agent-check`, `make test`, `make guidance-check`, and
  `make check-preview`.
- If the clean-tree preview script fails at `files[@]` under `set -u`, record
  that existing baseline; do not broaden this plan to repair the script.
- Run `make lint && make test` before handoff.
- Manually smoke-test keyboard shortcut, window focus, route, reduced motion,
  and non-Git folder behavior.

## Done criteria

- The keyboard-open path has no 200 ms alpha animation and remains focused on
  showing the existing window.
- Monitor seed schedules Git/file work off the main actor and publishes only
  current results.
- Existing monitor filtering/persistence and quota-provider behavior remain
  correct.
- Focused tests, agent, guidance, preview, lint, and test gates pass; timing
  evidence is recorded.
- No cache, daemon, dependency, or selected-refresh/UI redesign was added.

## STOP conditions

- Removing the fade exposes another synchronous operation that cannot be
  measured or safely moved within this scope.
- Async seed requires changing Git status semantics, persistence ordering, or
  creating a second source of monitored-project truth.
- A stale-result race cannot be covered by the existing generation/session
  pattern.
- Quota throttling suppresses explicit user refresh or changes provider/error
  behavior.
- Plan 057 changes touched APIs after the drift check and cannot be reconciled
  without broad migration work.

## Maintenance notes

Keep first-open work limited to presentation, cheap local state, and existing
bounded background reads. If profiling shows monitor reads—not startup—are the
remaining cost, use Plan 063's compact-read boundary before adding a cache. If
the selected repository remains slow after the window is visible, continue
with Plan 062 rather than adding more opening-path work.
