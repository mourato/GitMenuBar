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
| **Local path** | ~/Documents/Projects/References/Vorssaint |
| **Cloned?** | Yes |
| **Remote** | https://github.com/vorssaint/vorssaint-utils |
| **Description** | Menu-bar toolkit (monitor, volume, windows, clipboard, keep-awake). Compact UI, permission-gated degradation, local-first design, sustainable polling, AppKit/SwiftUI interop |

### Mimir

| Attribute | Value |
|-----------|-------|
| **Canonical name** | Mimir |
| **Classification** | UI/UX + Engineering |
| **Local path** | ~/Documents/Projects/References/Mimir |
| **Cloned?** | Yes |
| **Remote** | https://github.com/erayendes/mimir |
| **Description** | macOS menu bar app for tracking AI tool usage limits (Claude, Codex, Antigravity). Real-time quota monitoring, reset countdowns, color status dots, privacy-first local-only data access, minimalist design with dark/light mode support |

## Relevant GitMenuBar touchpoints

When studying Vorssaint, cross-reference:

- `StatusBarController.swift` — `NSStatusItem` ownership and window management
- `GitManager.swift` / `GitExecution.swift` — background dispatch vs sensor polling
- `WindowOpenTrace` — metric-collection idioms for menu-open latency

When studying Mimir, cross-reference:

- `StatusBarController.swift` — status-item glyph and popover lifecycle
- `AIProviderAdapters.swift` / `AIProviderStore.swift` — multi-provider data aggregation pattern
- `StatusItemBadgeRenderer.swift` — status indicator rendering (color dots, quota display)
- `AppPreferences.swift` — local-first data persistence approach
- `UpdateChecker.swift` — background refresh and backoff strategies

## Product routing

After locating reference material:

- Status-item / popover behavior → global `menubar` (+ overlay)
- General macOS UI → global `macos-app-engineering` (+ overlay)
- Architecture adoption → global `code-quality` (+ overlay)
- Latency budgets, Instruments, regression measurement → local `performance-profiling`
