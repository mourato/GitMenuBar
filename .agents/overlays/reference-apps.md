---
kind: project-overlay
extends: reference-apps
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
| **Reference revision** | `v0.0.29-nightly.20260725.899` (`5719e8ac4020`, 2026-07-24) |
| **Channel note** | Public desktop releases are Nightly prereleases; the changed-files card also exists on `main`. Prefer the pinned Nightly tag when matching shipped Preview/Nightly UI; re-check `main` before assuming a feature is Nightly-only. |
| **License** | MIT (`LICENSE`; copyright T3 Tools Inc., 2026). The separately reused `@pierre/trees` subset is Apache-2.0 with a MIT `headless-tree/core` notice. |
| **License URL** | https://opensource.org/license/mit |
| **Reuse decision** | T3Code is a UI/behavior reference only; reimplement the changed-files interaction natively. The separately audited `@pierre/trees` asset subset is reused under Apache-2.0; see `docs/file-type-icons.md` and `GitMenuBar/Resources/FileTypeIcons/NOTICE.md`. No T3Code README credit required. |
| **Description** | Web/Electron coding-agent harness (Codex, Claude, Cursor, OpenCode). After each agent turn, a collapsible **Changed files** card shows aggregate `+N/-M` stats, optional compact scope preview, hierarchical folder tree with path compaction, expand/collapse-all, per-type Pierre file icons, and **Open diff**. Primary study surface for GitMenuBar's commit-detail and working-tree file summaries. |

### Vorssaint

| Attribute | Value |
|-----------|-------|
| **Canonical name** | Vorssaint |
| **Classification** | UI/UX + Engineering |
| **Local path** | ~/Documents/Projects/References/Vorssaint |
| **Cloned?** | Yes |
| **Remote** | https://github.com/vorssaint/vorssaint-utils |
| **Reference revision** | `e83393cad615` (2026-08-05; nearest tag `v3.3.0`) |
| **License** | GPL-3.0-or-later (`LICENSE`; copyright 2026 Vorssaint) |
| **License URL** | https://www.gnu.org/licenses/gpl-3.0.html |
| **Reuse decision** | Inspiration and independent reimplementation only; do not copy source, assets, trademarks, or brand identity. No README credit required. |
| **Description** | Menu-bar toolkit (monitor, volume, windows, clipboard, keep-awake). Compact UI, permission-gated degradation, local-first design, sustainable polling, AppKit/SwiftUI interop |

### Mimir

| Attribute | Value |
|-----------|-------|
| **Canonical name** | Mimir |
| **Classification** | UI/UX + Engineering |
| **Local path** | ~/Documents/Projects/References/Mimir |
| **Cloned?** | Yes |
| **Remote** | https://github.com/erayendes/mimir |
| **Reference revision** | `7d050393a6ec` (2026-07-11; nearest tag `v2.6`) |
| **License** | MIT (`LICENSE`; copyright Eray Endes, 2026) |
| **License URL** | https://opensource.org/license/mit |
| **Reuse decision** | Codex usage parsing logic is adapted under MIT; preserve the copyright and license notice in `THIRD-PARTY-NOTICES.md` and credit the source in `README.md`. UI, telemetry, widgets, and unrelated providers remain inspiration-only. |
| **Description** | macOS menu bar app for tracking AI tool usage limits (Claude, Codex, Antigravity). Real-time quota monitoring, reset countdowns, color status dots, privacy-first local-only data access, minimalist design with dark/light mode support |

### CodexBar

| Attribute | Value |
|-----------|-------|
| **Canonical name** | CodexBar |
| **Classification** | UI/UX + Engineering + Same-domain |
| **Local path** | ~/Documents/Projects/References/CodexBar |
| **Cloned?** | Yes |
| **Remote** | https://github.com/steipete/CodexBar |
| **Reference revision** | `cc8da27cec92` (2026-07-20) |
| **License** | MIT (`LICENSE`; copyright Peter Steinberger, 2026) |
| **License URL** | https://opensource.org/license/mit |
| **Reuse decision** | OpenRouter credits parsing and three provider icons are adapted under MIT; preserve the copyright and license notice in `THIRD-PARTY-NOTICES.md` and credit the source in `README.md`. Other UI and provider code remains inspiration-only. |
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

- Status-item / popover behavior → global `macos-app-engineering` (+ overlay)
- General macOS UI → global `macos-app-engineering` (+ overlay)
- Architecture adoption → global `code-quality` (+ overlay)
- Latency budgets, Instruments, regression measurement → local `performance-profiling`
