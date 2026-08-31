---
name: performance-profiling
description: Performance review workflow for GitMenuBar, focused on startup, menu responsiveness, rendering churn, expensive Git operations, latency budgets, and regression detection.
---

# Performance Profiling

Use this skill when the change can affect latency, memory, rendering cost, or repeated Git work.

## Hot Paths

- App launch and status item registration
- Opening the menu or main window
- Repository switching
- Working tree refresh and diff parsing
- History loading, pagination, and branch operations
- AI-assisted commit generation

## Latency budgets

p95 targets on Apple Silicon with real-world repository sizes:

| Operation | Target (p95) | Measurement point |
|-----------|--------------|-------------------|
| Menu / main window open | < 150 ms | `WindowOpenTrace` → `presentMainWindow` to view render |
| `git status --porcelain` on tracked repo | < 100 ms | Wrap `GitCommandRunner.runGit` for status |
| Full refresh (`refreshAsync`) | < 500 ms | Task start to last published value |
| Branch switch (no conflicts) | < 1 s | `switchBranch` to new branch rendered |
| Commit history initial load (25 entries) | < 200 ms | `CommitHistoryParser` / `git log` parse |
| Per-file diff for AI commit gen | < 50 ms/file | each `git diff -- <file>` |

Refine with measured hardware and repo sizes. Warn via `os_log` when a budget is exceeded by > 2×.

## Review heuristics

- Avoid repeated Git commands for the same visible state.
- Cache only when invalidation is explicit and cheap to reason about.
- Keep popover and menu rendering work proportional to visible content.
- Prefer measuring before adding memoization or background complexity.
- If a change adds polling, repeated filesystem scans, or repeated parsing, justify it.
- Extend `WindowOpenTrace` / `CFAbsoluteTime` / `os_signpost` for hot-path timing; use XCTest `measure` for CI-sensitive Git operations when a harness exists.

## Resource checks

- Memory footprint delta on window open
- Working-tree cache size after parse
- Concurrent `git` process count during full refresh (prefer serialized per operation)

## Validation

- Compare before/after menu-open behavior on a real repository.
- Watch for extra work on every `body` recomputation or every repo-state refresh.
- Check that background work does not block main-actor updates or app activation.
- If a performance fix changes behavior, pair it with regression tests where possible.
- Before merging performance-sensitive changes: `make test`, measure window open on a real repo, switch branches within budget, and exercise `git status` on a large working tree when relevant.

## Related skills

Reference-app study → global `reference-apps` + `.agents/overlays/reference-apps.md`.
Deep Instruments sessions stay here; delivery/CI gates → `delivery-workflow`.
