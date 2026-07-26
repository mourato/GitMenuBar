---
kind: project-overlay
extends: benchmarking
project: GitMenuBar
precedence: project
---

# GitMenuBar reference catalog

**Same-domain** here means menu-bar utilities, Git clients, macOS developer
productivity tools, AI coding-agent harness UIs that present Git working-tree
or turn diffs, or AI usage-quota monitors that inform GitMenuBar's secondary
quota strip.

## Registered references

### T3Code

| Attribute | Value |
|-----------|-------|
| **Canonical name** | T3Code |
| **Classification** | UI/UX + Same-domain + Engineering |
| **Local path** | ~/Documents/Projects/References/T3Code |
| **Cloned?** | Yes |
| **Remote** | https://github.com/pingdotgg/t3code |
| **Study ref** | `v0.0.29-nightly.20260725.899` (`5719e8ac4020`) — latest GitHub Nightly/prerelease at clone time |
| **Channel note** | Public desktop releases are Nightly prereleases; the changed-files card also exists on `main`. Prefer the pinned Nightly tag when matching shipped Preview/Nightly UI; re-check `main` before assuming a feature is Nightly-only. |
| **License** | MIT (T3 Tools Inc., 2026). File icons lean on `@pierre/trees` (Apache-2.0, verified 2026-07-26); GitMenuBar uses native SF Symbols + adaptive tints instead of vendoring Pierre SVGs — see `GitMenuBar/Resources/FileTypeIcons/README.md`. |
| **Description** | Web/Electron coding-agent harness (Codex, Claude, Cursor, OpenCode). After each agent turn, a collapsible **Changed files** card shows aggregate `+N/-M` stats, optional compact scope preview, hierarchical folder tree with path compaction, expand/collapse-all, per-type Pierre file icons, and **Open diff**. Primary study surface for GitMenuBar's commit-detail and working-tree file summaries. |

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

### CodexBar

| Attribute | Value |
|-----------|-------|
| **Canonical name** | CodexBar |
| **Classification** | UI/UX + Engineering + Same-domain |
| **Local path** | ~/Documents/Projects/References/CodexBar |
| **Cloned?** | Yes |
| **Remote** | https://github.com/steipete/CodexBar |
| **Description** | Benchmark menu-bar usage monitor for Codex, Claude, Cursor, and many other AI providers. Multi-window rate limits (`limit_window_seconds`), reset-credit inventory, pace tracking, tokenized status-item layouts, and provider-card density without cognitive overload |

## Relevant GitMenuBar touchpoints

When studying T3Code, cross-reference:

- `apps/web/src/components/chat/ChangedFilesTree.tsx` — `ChangedFilesCard` + tree rows (header, Hide/Show, expand-all, Open diff)
- `apps/web/src/lib/turnDiffTree.ts` — path tree build, directory compaction, aggregated stats
- `apps/web/src/components/chat/changedFilesPresentation.ts` — auto-expand thresholds, compact scope/file preview
- `apps/web/src/components/chat/DiffStatLabel.tsx` — compact `+N` / `-M` formatting
- `apps/web/src/components/chat/PierreEntryIcon.tsx` + `apps/web/src/pierre-icons.ts` — extension/name → colored file icons (GitMenuBar maps T3 light/dark token pairs to SF Symbol tints in `FileTypeIcon.swift`)
- `apps/web/src/components/chat/MessagesTimeline.tsx` — when the card mounts after a turn
- GitMenuBar consumers to adapt: `WorkingTreeSectionView.swift`, `WorkingTreeFileRow.swift`, `WorkingTreeSectionHeaderView.swift`, `CommitDetailPageView.swift` (`changedFilesSection` / `CommitChangedFileRowView`)

When studying Vorssaint, cross-reference:

- `StatusBarController.swift` — `NSStatusItem` ownership and window management
- `GitManager.swift` / `GitExecution.swift` — background dispatch vs sensor polling
- `WindowOpenTrace` — metric-collection idioms for menu-open latency

When studying Mimir, cross-reference:

- `StatusBarController.swift` — status-item glyph and popover lifecycle
- `Services/UsageQuota/*` — multi-provider quota aggregation (not AI commit adapters)
- `Components/UsageQuota/UsageQuotaStripView.swift` — compact remaining-% + countdown presentation
- `AppPreferences.swift` — local-first preference keys for opt-in quota UI
- Snapshot/stale fallback patterns in `UsageQuotaStore.swift`

When studying CodexBar, cross-reference:

- `Services/UsageQuota/CodexUsageProvider.swift` / `CodexUsageParsing.swift` — ChatGPT `wham/usage` windows + `wham/rate-limit-reset-credits`
- `UsageQuotaModels.swift` — dynamic interval labels from `limit_window_seconds` / `window_minutes`
- `Components/UsageQuota/UsageQuotaStripView.swift` — footer density: primary % + interval chip + reset countdown + optional reset-credit count
- `CursorUsageProvider.swift` — Cursor billing-period remaining as a single plan window
- Menu-open latency: keep quota refresh non-blocking (show last snapshot first)

## Product routing

After locating reference material:

- Status-item / popover behavior → global `menubar` (+ overlay)
- General macOS UI → global `macos-app-engineering` (+ overlay)
- Architecture adoption → global `code-quality` (+ overlay)
- Latency budgets, Instruments, regression measurement → local `performance-profiling`
