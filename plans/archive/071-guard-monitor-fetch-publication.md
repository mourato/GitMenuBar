# Plan 071: Guard monitor fetch publication against stale snapshots

> **Executor instructions**: Read this plan completely before editing. Use one
> isolated worktree, preserve unrelated changes, and keep remote fetch
> sequential and user-triggered. Root-session review is required after
> implementation. Reconcile Plan 057's Swift 6.4 toolchain baseline before
> starting.
>
> **Drift check (run first)**: `git diff --stat 11a88dd..HEAD --
> GitMenuBar/Services/Git/ProjectMonitorStore.swift
> GitMenuBar/Services/Git/MonitoredProjectsStore.swift
> GitMenuBarTests/MonitoredProjectsStoreTests.swift
> GitMenuBarTests/ProjectMonitorStoreTests.swift docs/adr/0004-multi-project-monitoring-snapshots.md plans`

## Status

- Priority: P1
- Effort: M
- Risk: HIGH
- Depends on: Plan 057 (Swift 6.4 toolchain baseline); Plans 060–063 are DONE
- Category: correctness / concurrency / monitoring persistence
- Planned at: commit `11a88dd`, 2026-08-11

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: High / Full
- **Parallelizable**: Yes after Plan 057; the monitor-store slice is separate
  from selected GitManager and CLI work, but final validation is serial.
- **Reviewer required**: Yes — root-session review of publication admission,
  removal/rename behavior, and the remote-fetch boundary.
- **Rationale**: Regular status refresh already checks a generation before
  writing snapshots; `fetchAll` publishes each background result without any
  generation or enrollment check. A minimal admission token closes the race
  without adding a cache or changing monitoring ownership.
- **Escalate when**: the fix changes automatic-vs-user-triggered fetch policy,
  introduces concurrent remote fetches, or needs a second monitor store.

## Why it matters

`fetchAll` snapshots the monitored list, fetches in the background, and then
unconditionally writes each result. If a project is removed while fetch is in
flight, it can be reinserted into `snapshots`. If a newer local refresh or
rename completes first, the older fetch result can overwrite it. The regular
refresh path already demonstrates the intended admission pattern; fetch must
join that publication contract.

This plan protects snapshot ownership only. It does not make remote fetch
automatic, parallel, or part of selected `GitManager` state.

## Current state

- `GitMenuBar/Services/Git/ProjectMonitorStore.swift:93-96` removes the
  persisted project and current snapshot but does not invalidate in-flight
  fetch work.
- `:132-141` captures `monitoredProjects`, runs a sequential background
  `fetch`/`ProjectStatusReader.read` loop, and assigns each snapshot on the
  MainActor without checking that the project is still monitored or that the
  result is current.
- `:144-171` regular `refresh(projects:)` has `refreshGeneration` and checks it
  before publication; `fetchAll` bypasses that guard.
- `:118-130` allows path refreshes to queue while `isRefreshing` is true;
  preserve this local refresh lifecycle rather than reusing the flag as a
  remote-fetch lock without tracing all completion paths.
- `GitMenuBarTests/MonitoredProjectsStoreTests.swift:78-102` covers seed
  filtering and persistence but has no fetch/remove or fetch/refresh race.
- `GitCommandRunner` is a concrete `final` runner and the production fetch loop
  is asynchronous, so deterministic race tests may need the smallest existing
  operation seam. Do not build a broad Git runner protocol only for this plan.
- `docs/adr/0004-multi-project-monitoring-snapshots.md` deliberately keeps
  remote fetch user-triggered and selected `GitManager` single-repository.

## Commands and evidence

| Check | Command | Expected result |
|---|---|---|
| Publication references | `rg -n 'fetchAll|refreshGeneration|snapshots\[|remove\(path|rename\(path' GitMenuBar/Services/Git GitMenuBarTests` | Every background snapshot write has an admission check |
| Focused tests | `make test TEST_FILTER=MonitoredProjectsStoreTests` | Fetch/remove and fetch/refresh races pass deterministically |
| Focused gate | `make agent-check` | Changed lint and build pass |
| Full tests/lint | `make test && make lint` | Existing monitor and app tests remain green |
| Guidance/hygiene | `make guidance-check && git diff --check` | Exit 0 |

If the Makefile does not support `TEST_FILTER`, use its documented focused-test
argument or the smallest existing `xcodebuild ... -only-testing` equivalent.

## Suggested executor toolkit

- Use `swift-concurrency`, `code-quality`, and `delivery-workflow`.
- Reuse the existing generation/admission pattern from `refresh(projects:)`.
- Prefer a monotonic token and direct enrollment check over a cache, event bus,
  or new repository abstraction.
- Keep the worker sequential as required by ADR 0004; do not increase remote
  concurrency while fixing publication.

## Scope

In scope:

- Add a minimal publication token/admission check for background fetch results.
- Invalidate or supersede fetch publication when a project is removed, renamed,
  re-added, seeded, or a newer local refresh takes ownership, as required by
  the chosen token design.
- Verify at publication time that the path remains monitored and that the
  result belongs to the current fetch/refresh generation.
- Add deterministic tests for fetch/remove and fetch/newer-refresh ordering,
  using a narrow test seam only if the concrete runner cannot control timing.
- Preserve sequential user-triggered remote fetch and existing snapshot shape.

Out of scope:

- Automatic remote fetch, fetch scheduling policy, parallel fetches, or network
  retry/backoff.
- Replacing `GitCommandRunner`, `ProjectStatusReader`, `ProjectMonitorStore`,
  or `MonitoredProjectsStore` with protocols/services.
- Changing selected-repository `GitManager` refresh behavior, UI layout, or
  persistence keys.

## Git workflow

Use `fix/monitor-fetch-publication-admission` in an isolated worktree. Use a
scoped Conventional Commit such as `fix(monitor): reject stale fetch snapshots`;
do not push, reset, or rewrite history.

## Ordered implementation steps

### 1. Map every snapshot writer and mutation

Trace seed, add, remove, rename, local refresh, pending refresh, and fetch
paths. Decide whether one shared monotonic publication generation or a fetch
token plus explicit invalidation is smaller and preserves `isRefreshing`.
Do not overload `refreshGeneration` in a way that leaves an in-flight local
refresh permanently marked as active.

**Verify:** every asynchronous `snapshots[...] = ...` write has a named
admission rule, and remote fetch remains user-triggered/sequential.

### 2. Add the smallest stale-publication guard

Capture a token when `fetchAll` starts. Before each MainActor write, require the
token to still be current and the normalized project path to remain in
`monitoredProjects`. Invalidate the token on removal and on any newer operation
that should own the same snapshot. Preserve current pending-refresh behavior;
if fetch is invoked while a local refresh is active, either queue one fetch or
skip it deterministically, but do not allow older data to win.

**Verify:** removing a project prevents a late fetch from recreating its
snapshot; a newer local refresh cannot be overwritten by an older fetch.

### 3. Add a deterministic test seam only if needed

First try the existing runner/store seams. If real Git commands cannot hold a
fetch at the required point, add one narrow internal operation closure or
structured worker seam modeled on `selectedRefreshOperation`; production must
default to the current runner/read implementation. Do not add a general
`GitCommandRunner` protocol or expose test controls to product code.

**Verify:** tests can pause and release fetch/read work without sleeps, network,
or timing assumptions; production initialization remains unchanged.

### 4. Add race regression tests

Extend `MonitoredProjectsStoreTests` or add a focused `ProjectMonitorStoreTests`
file. Cover fetch/remove and fetch/newer-refresh (and rename/re-add if the
chosen token requires it). Assert both the persisted monitored list and the
published snapshot map. Repeat the tests to prove deterministic admission.

**Verify:** the tests fail against the unconditional `fetchAll` publication and
pass with the guard; existing seed/persistence/classification tests remain
green.

### 5. Validate the handoff

Run the Commands and evidence table, inspect actor hops and generation changes,
and obtain root-session review. Update this plan and the ledger only after
focused/full checks pass.

**Verify:** the diff contains only monitor publication/test changes and does
not alter ADR 0004's remote-fetch boundary.

## Test plan

- Fetch completes after project removal: no snapshot is reinserted.
- Fetch completes after a newer local refresh: the newer snapshot remains.
- Rename/re-add behavior matches the chosen token admission rule.
- Multiple monitored projects still fetch sequentially and publish valid
  snapshots.
- Existing seed filtering, persistence, classification, `make agent-check`,
  `make test`, `make lint`, `make guidance-check`, and `git diff --check`.

## Done criteria

- Every `fetchAll` result is admitted by current generation and enrollment
  checks before publication.
- Removed or superseded projects cannot be resurrected or overwritten by stale
  fetch results.
- Sequential user-triggered fetch and snapshot ownership remain unchanged.
- Deterministic regressions and all required gates pass; root review accepts
  the concurrency boundary.

## STOP conditions

- The guard requires automatic fetching, concurrent remote work, or a new
  persistence model.
- A test depends on sleep duration, network state, or a real remote.
- A token change can leave `isRefreshing` stuck or drop pending refreshes.
- The proposed seam becomes a general Git abstraction with one production
  implementation.
- Snapshot data would still be published without checking current enrollment.

## Maintenance notes

Any future background snapshot producer must use the same admission rule as
local refresh and fetch. Keep monitor snapshots path-scoped and immutable from
the selected `GitManager`; update ADR 0004 only if the product intentionally
changes that boundary.
