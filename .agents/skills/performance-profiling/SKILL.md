---
name: performance-profiling
description: Performance review for GitMenuBar — startup, menu responsiveness, Git command cost, rendering churn, latency budgets, and regression detection.
---

# Performance Profiling

## When to use

A change can affect latency, memory, rendering cost, or repeated Git work.

## Project specifics

Hot paths: app launch and status item registration, menu/main window open, repository switching, working tree refresh and diff parsing, history loading and branch operations, AI-assisted commit generation.

p95 budgets on Apple Silicon with real repository sizes:

| Operation | Target (p95) | Measurement point |
|-----------|--------------|-------------------|
| Menu / main window open | < 150 ms | `WindowOpenTrace` → `presentMainWindow` to view render |
| `git status --porcelain` on tracked repo | < 100 ms | Wrap `GitCommandRunner.runGit` for status |
| Full refresh (`refreshAsync`) | < 500 ms | Task start to last published value |
| Branch switch (no conflicts) | < 1 s | `switchBranch` to new branch rendered |
| Commit history initial load (25 entries) | < 200 ms | `CommitHistoryParser` / `git log` parse |
| Per-file diff for AI commit gen | < 50 ms/file | each `git diff -- <file>` |

Warn via `os_log` when a budget is exceeded by more than 2×, and refine the numbers with measured hardware and repository sizes.

For commit, push, or project-switch changes, use the runtime scenarios and signpost names in `docs/adr/0009-path-bound-git-operations.md`. Builds and tests prove path binding; only Instruments on a real repository establishes phase latency, Git process count, and main-actor cost. Keep traces outside the repository.

Also watch memory delta on window open, working-tree cache size after parse, and concurrent `git` process count during a full refresh. Before merging performance-sensitive changes: `make test`, then measure window open and branch switch on a real repository.

## Follows global performance

`performance` owns claim binding, baselines, workload parity, and bounded claims; deep Instruments sessions stay here. Related: global `study-reference-apps` with `docs/agents/reference-apps.md`, delivery gates → global `ship`.
