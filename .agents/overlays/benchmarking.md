---
kind: project-overlay
extends: benchmarking
project: GitMenuBar
precedence: project
---

# GitMenuBar reference catalog

**Same-domain** here means menu-bar utilities, Git clients, or macOS developer
productivity tools.

## Registered references

### Vorssaint

| Attribute | Value |
|-----------|-------|
| **Canonical name** | Vorssaint |
| **Classification** | UI/UX + Engineering |
| **Local path** | — |
| **Cloned?** | No |
| **Remote** | https://github.com/vorssaint/vorssaint-utils |
| **Description** | Menu-bar toolkit (monitor, volume, windows, clipboard, keep-awake). Compact UI, permission-gated degradation, local-first design, sustainable polling, AppKit/SwiftUI interop |

### Relevant GitMenuBar touchpoints

When studying Vorssaint, cross-reference:

- `StatusBarController.swift` — `NSStatusItem` ownership and window management
- `GitManager.swift` / `GitExecution.swift` — background dispatch vs sensor polling
- `WindowOpenTrace` — metric-collection idioms for menu-open latency

## Product routing

After locating reference material:

- Status-item / popover behavior → global `menubar` (+ overlay)
- General macOS UI → global `macos-app-engineering` (+ overlay)
- Architecture adoption → global `code-quality` (+ overlay)
- Latency budgets, Instruments, regression measurement → local `performance-profiling`
