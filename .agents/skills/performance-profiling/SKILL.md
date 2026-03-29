---
name: performance-profiling
description: Performance review workflow for GitMenuBar, focused on startup, menu responsiveness, rendering churn, and expensive Git operations.
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

## Review Heuristics

- Avoid repeated Git commands for the same visible state.
- Cache only when invalidation is explicit and cheap to reason about.
- Keep popover and menu rendering work proportional to visible content.
- Prefer measuring before adding memoization or background complexity.
- If a change adds polling, repeated filesystem scans, or repeated parsing, justify it.

## Validation

- Compare before/after menu-open behavior on a real repository.
- Watch for extra work on every `body` recomputation or every repo-state refresh.
- Check that background work does not block main-actor updates or app activation.
- If a performance fix changes behavior, pair it with regression tests where possible.
