---
name: benchmarking
description: Canonical knowledge about reference projects that inspire GitMenuBar, plus latency budgets, metric collection, and regression detection for benchmarking.
---

# Benchmarking — Reference Projects & Performance Baselines

## Role

This skill owns two related responsibilities:

1. **Reference catalog** — canonical knowledge about open-source macOS projects that inspire GitMenuBar's visual design, code architecture, or engineering practices.
2. **Performance baselines** — latency budgets, metric collection infrastructure, and regression detection for Git operations and UI.

## When to Use

Use this skill when:

- The user mentions a known reference project, "apps referência", "inspiração", or wants to improve something by studying similar apps.
- The task involves establishing latency budgets, collecting performance metrics, detecting regressions, or setting up benchmark gates.

## Scope Boundaries

- Use this skill to identify, classify, locate, consult, and learn from reference projects.
- Delegate to `macos-app-engineering` when the focus is UI/UX pattern extraction or macOS implementation details from a reference.
- Delegate to `menubar` when the focus is status-item, popover, or menu-bar-specific behavior from a reference.
- Delegate to `code-quality` when adopting specific architecture patterns uncovered during reference study.
- Delegate to `performance-profiling` when deep Instruments-driven diagnosis is needed after a benchmark identifies a regression.
- This skill does not implement changes — it directs agents to the right reference code, context, and performance targets.

## Reference Classification

Every reference must be classified into one or more categories when added:

| Category        | Description                                                                                                                                              |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **UI/UX**       | Reference for user experience, interaction design, visual polish, or layout patterns — even if the app does something entirely different from GitMenuBar |
| **Same-domain** | App that does the same thing as GitMenuBar (menu bar utility, Git client, developer productivity tool for macOS)                                         |
| **Engineering** | Reference for architectural decisions, performance patterns, or engineering discipline worth adopting                                                    |

A reference can be one, two, or all three categories.

## Registered References

### vorssaint-utils / Vorssaint

| Attribute          | Value                                                                                                                                                                                                                                                                                                                                                         |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Canonical name** | Vorssaint                                                                                                                                                                                                                                                                                                                                                     |
| **Classification** | UI/UX + Engineering                                                                                                                                                                                                                                                                                                                                           |
| **Local path**     | — (not cloned)                                                                                                                                                                                                                                                                                                                                                |
| **Cloned?**        | ❌ No                                                                                                                                                                                                                                                                                                                                                         |
| **Remote**         | https://github.com/vorssaint/vorssaint-utils                                                                                                                                                                                                                                                                                                                  |
| **Description**    | Open-source macOS menu bar toolkit (system monitor, per-app volume, window management, clipboard history, keep awake). Relevant for compact menu bar UI patterns, permission-gated graceful degradation, local-first architecture, sustainable polling for live updates, and AppKit/SwiftUI interop patterns analogous to GitMenuBar's `StatusBarController`. |

### Relevant GitMenuBar touchpoints

When studying Vorssaint, cross-reference with these GitMenuBar files:

- `StatusBarController.swift` — NSStatusItem ownership and window management
- `GitManager.swift` / `GitExecution.swift` — background dispatch model vs. Vorssaint's sensor polling queues
- `WindowOpenTrace` — compare metric-collection idioms for menu open latency

## Clone Policy

When a reference project is **not cloned locally** (tagged ❌):

1. **Ask the user** if they want to clone it before proceeding with any analysis that depends on the reference.
2. **Clone location**: `~Documents/Projects/references/<CanonicalName>/` — keeping all reference projects organized in a single directory.
3. Use `git clone <remote_url> <target_path>` with the canonical PascalCase name for the target directory.
4. After cloning, update the table above: mark **Cloned?** as ✅ Yes and fill the **Local path**.

## Consultation Methods (Priority Order)

When studying a reference, use this priority order. Start with #1 and fall back as needed.

### 1. Local (preferred)

Clone is available — browse files directly with `Read`, `Glob`, `Grep`, `Bash`. Fastest and most reliable.

### 2. Remote repository web UI

Fetch files via `WebFetch` from GitHub raw URLs or the web interface:

- Raw content: `https://raw.githubusercontent.com/<owner>/<repo>/<branch>/<path>`
- Web: `https://github.com/<owner>/<repo>`

`gh` CLI is also available for GitHub-specific operations (issues, PRs, file listings).

### 3. grep.app

For cross-repository pattern search, use `WebFetch` on `https://grep.app/search?q=<query>` or `WebSearch` to find how other projects implement a specific pattern. Useful when you need to search beyond the registered references.

## How to Use References

When the user wants to solve or improve something, use the classification to pick the right references:

1. **If the problem is UI/UX-related** (layout, animations, interactions, visual polish in the menu bar): consult references classified as **UI/UX** first. Even if they do something different, their UI patterns may inspire the solution.

2. **If the problem is domain-related** (Git operations, repository management, menu bar utility patterns): consult references classified as **Same-domain** first. They solve similar problems and may share architecture or pipeline patterns.

3. **If the problem is engineering-related** (performance, architecture, dispatch model, metric collection): consult references classified as **Engineering** first.

4. **If the problem touches multiple categories**: consult references that span the relevant classifications.

5. **Select the consultation method** following the priority order above:
   - ✅ **Cloned locally** → use Local.
   - ❌ **Not cloned** → try Remote Web, then grep.app. Ask the user whether to clone if deep analysis is needed.

6. Use the reference code as **inspiration only** — never copy-paste without understanding the license and adapting to GitMenuBar's architecture.

7. Document any patterns adopted from references in the relevant PR or issue, cross-referencing the specific GitMenuBar files affected.

## Adding a New Reference

When a new reference project is identified:

1. Add it to the **Registered References** table above.
2. **Classify it** as UI/UX, Same-domain, Engineering, or any combination.
3. Fill in all attributes (canonical name, local path, remote URL, description).
4. Mark cloned status. If not cloned locally, the clone policy applies.
5. Add a **Relevant GitMenuBar touchpoints** subsection listing specific files or types where the reference's patterns apply.

## Performance Baselines

### Latency Budgets

The following budgets define GitMenuBar's performance contract. These are p95 targets measured on Apple Silicon hardware with real-world repository sizes.

| Operation                                | Target (p95)     | Measurement Point                                                            |
| ---------------------------------------- | ---------------- | ---------------------------------------------------------------------------- |
| Menu / main window open                  | < 150 ms         | `WindowOpenTrace` → `CFAbsoluteTime` from `presentMainWindow` to view render |
| `git status --porcelain` on tracked repo | < 100 ms         | Wrap `GitCommandRunner.runGit` for status commands                           |
| Full refresh (`refreshAsync`)            | < 500 ms         | Time the `refreshAsync` Task from start to last published value              |
| Branch switch (no conflicts)             | < 1 s            | Time from `switchBranch` call to new branch state rendered                   |
| Commit history initial load (25 entries) | < 200 ms         | Time `git log` parsing in `CommitHistoryParser`                              |
| Per-file diff for AI commit gen          | < 50 ms per file | Time each `git diff -- <file>` call                                          |

> These budgets are starting points. Refine them based on real hardware and real-world repository sizes.

### Memory & Resource Metrics

- **Memory delta on window open**: Measure `footprint` delta before and after presenting the main window.
- **Working tree cache size**: Track the byte size of `WorkingTreeParser` parsed results.
- **Git process count**: Count concurrent `git` processes spawned during a full refresh — should stay serialized per operation.

### Current Instrumentation

GitMenuBar already has `WindowOpenTrace` logging `CFAbsoluteTime` deltas. Extend this pattern:

```swift
struct Benchmark {
    let label: String
    let start: CFAbsoluteTime

    init(_ label: String) {
        self.label = label
        self.start = CFAbsoluteTimeGetCurrent()
    }

    func finish() {
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print("[Benchmark] \(label): \(String(format: "%.1f", elapsed)) ms")
    }
}
```

### Metric Collection Strategy

1. **Ad-hoc tracing**: Use `CFAbsoluteTime` / `os_signpost` for hot-path instrumentation during development.
2. **XCTest `measure` blocks**: Wrap key Git operations in `measure` to catch regressions in CI.
3. **Persistent log**: Write structured JSON lines to `~/Library/Logs/GitMenuBar/benchmark.ndjson` for offline analysis.
4. **Threshold alerts**: Log a warning (via `os_log`) when any budget is exceeded by > 2×.

### os_signpost Integration

For granular profiling in Instruments:

```swift
import os.signpost

let log = OSLog(subsystem: "com.gitmenubar.app", category: .pointsOfInterest)
let sid = OSSignpostID(log: log)
os_signpost(.begin, log: log, name: "FullRefresh", signpostID: sid)
// ... work ...
os_signpost(.end, log: log, name: "FullRefresh", signpostID: sid)
```

## Regression Detection

### CI Benchmarks

When a CI pipeline is introduced, include a benchmark step:

1. Create a repository with known state (e.g., 1000 files, 500 commits, 10 branches).
2. Run `make benchmark` (to be defined) exercising the benchmark surface.
3. Compare elapsed times against a stored baseline.
4. Fail CI on > 20% regression.

### Manual Regression Checks

Before merging performance-sensitive changes:

1. Run `make test` to confirm correctness.
2. Open the app and measure main window open time with a real-world repo.
3. Switch branches and verify the UI updates within the latency budget.
4. Run `git status` on a large working tree (1000+ files) to verify diff parsing stays under budget.

## Tooling

- **Instruments**: Time Profiler, os_signpost, and Allocations instruments for deep diagnosis.
- **Xcode Organizer**: Monitor `~/Library/Logs/GitMenuBar/benchmark.ndjson` for trend analysis across builds.
- **SwiftLint**: Keep `file_length`, `function_body_length`, and `type_body_length` rules active — large functions correlate with benchmark regressions.

## Trigger Keywords

This skill activates on any of these mentions (case-insensitive partial match):

- `vorssaint`, `Vorssaint`
- `referência`, `referências`, `inspiração`
- `benchmarking`, `benchmark`
- `apps referência`, `projetos referência`
- `latency budget`, `p95`, `regression detection`

## Related Skills

- `macos-app-engineering` — when studying reference UI implementations or UI/UX decisions
- `menubar` — when the reference informs status-item or popover behavior
- `code-quality` — when adopting architecture patterns uncovered during reference study
- `performance-profiling` — when deep Instruments diagnosis is needed after a benchmark regression
- `delivery-workflow` — for merge gates and CI integration of benchmark steps
- `thermo-nuclear-code-quality-review` — when reviewing changes inspired by references
