# Plan 033: Enrich usage quota strip into Mimir-style provider cards

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 7ade5a9..HEAD -- GitMenuBar/Components/UsageQuota/UsageQuotaStripView.swift GitMenuBar/Models/UsageQuotaModels.swift GitMenuBarTests/UsageQuotaStoreTests.swift GitMenuBarTests/UsageQuotaParsingTests.swift .interface-design/system.md plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW
- **Depends on**: plans/032-window-material-shell-main-and-settings.md (recommended so cards sit on the glass shell; soft dependency)
- **Category**: direction
- **Planned at**: commit `7ade5a9`, 2026-07-25

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: `yes` — UI-only vs Plans 030–031 if shell already present; still prefer after 032
- **Reviewer required**: `no` — presentation only; no new credential paths (023/024 already shipped providers)
- **Rationale**: SwiftUI redesign of existing `UsageQuota*` snapshots; data model mostly sufficient. Escalate if parsing/API changes appear necessary.
- **Escalate when**: need new provider fields, status-item glyphs, or credential reads.

## Why this matters

Plans 023/024 shipped a compact quota strip (UX option A). Mimir-like chrome was deferred. Product now wants secondary but richer cards: progress bar, countdown, and exact next-cycle clock — for **both** Codex and Cursor — without status-item badges. Data already includes `remainingPercent`, `resetAt`, interval chips, and traffic-light thresholds.

## Current state

Strip row (single line; countdown beside %; no progress bar; no absolute clock):

```23:70:GitMenuBar/Components/UsageQuota/UsageQuotaStripView.swift
private struct UsageQuotaProviderRow: View {
    // displayName | interval chip | percent badge + countdown | weekly footnote | credits
}
```

```109:127:GitMenuBar/Components/UsageQuota/UsageQuotaStripView.swift
private struct UsageQuotaPercentBadge: View {
    // traffic-light dot + "\(percent)%" + resetCountdown(until:)
}
```

Formatting already supports countdown like `6d 23h`:

```169:187:GitMenuBar/Models/UsageQuotaModels.swift
    static func resetCountdown(until resetAt: Date?, now: Date = Date()) -> String { ... }
    static func trafficLightColor(for remainingPercent: Int) -> UsageQuotaTrafficLight { ... }
```

`UsageWindow` has `remainingPercent`, `resetAt`, `label`, `durationSeconds`. Weekly secondary already deduped when identical to primary.

Locked UI contract (`.interface-design/system.md` → Usage quota cards):

- Provider-agnostic cards for visible Codex/Cursor snapshots.
- Primary: name, interval chip, traffic-light `%`, **progress bar**, countdown + icon, locale **time-only** clock + icon from `resetAt`.
- Secondary weekly row when weekly differs (same rule as today’s trailing footnote).
- Natural height for 1–2 providers; traffic-light colors (not mint-only).
- Still secondary to Git workflow; Settings toggles unchanged.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift | `git diff --stat 7ade5a9..HEAD -- GitMenuBar/Components/UsageQuota/` | understood |
| Incremental | `make agent-check` | exit 0 |
| Quota tests | `make test` (or filtered xcode test for `UsageQuota` if available) | exit 0 |
| Full gate | `make lint && make test` | exit 0 |
| No status-item quota | `rg -n 'UsageQuota|quota' GitMenuBar/App/StatusBarController.swift` | no new glyph wiring |

## Suggested executor toolkit

- `apple-design`, `swift-conventions`, `swiftui-performance-audit` (keep updates quiet)
- New/changed Views need `#Preview` (existing strip previews are the pattern)

## Scope

**In scope**

- `GitMenuBar/Components/UsageQuota/UsageQuotaStripView.swift` (and/or split files under `Components/UsageQuota/` if clearer) — card layout
- Optional small formatting helpers in `UsageQuotaModels.swift` / `UsageQuotaFormatting` — e.g. `resetClockTime(until:locale:)` for time-only strings; keep pure and testable
- Previews for 100%, mid, low, stale, dual-window, dual-provider
- Unit tests for any new pure formatting helpers
- Accessibility labels/values updated for bar + clock

**Out of scope**

- New providers, auth/token refresh, Settings pane redesign
- Status-item quota glyphs / UX option B
- Changing traffic-light thresholds
- Expanding window chrome (Plans 030–032)
- Persisting layout preferences

## Git workflow

- Branch: `feat/033-usage-quota-mimir-cards`
- Commit example: `feat(ui): enrich usage quota strip into provider cards`
- Do NOT push unless asked

## Steps

### Step 1: Add time-only clock formatter (+ tests)

Add a pure helper that formats `resetAt` as locale-aware **time only** (e.g. `18:27` / `6:27 PM`). When `resetAt` is nil or past, show an em dash or hide the clock row per existing countdown “—” behavior — be consistent and document in code comment.

**Verify**: new tests in `GitMenuBarTests/` modeled after `UsageQuotaParsingTests` / formatting coverage → pass via `make test` (or targeted test invocation used in this repo)

### Step 2: Build provider card UI

Replace/reshape `UsageQuotaProviderRow` into a compact card:

1. Top: `displayName` + interval chip … traffic-light `%<n>` (keep `%` after the number unless an existing formatter says otherwise; do **not** adopt Mimir’s `%100` prefixing if it fights current copy — stay with `"\(percent)%"`).
2. Progress bar: filled fraction = `remainingPercent / 100`, colored with the same traffic-light color as the percentage.
3. Meta row: SF Symbol gauge/speedometer + `resetCountdown`; clock symbol + time-only string.
4. Optional weekly secondary row (chip + % + muted treatment) when weekly differs from primary — mirror today’s condition.
5. Preserve stale opacity / status notes / reset credits / credit value text without cluttering the primary hierarchy (credits may remain a compact trailing/meta line).

Use `WorkbenchMetrics` / `WorkbenchTypography` / `WorkbenchPalette`; no raw magic spacing/colors. Prefer quiet bars (no drop shadows). Respect Reduce Motion (no indeterminate shimmer required).

**Verify**: `make agent-check` → exit 0

### Step 3: Accessibility + previews

- Combined accessibility element should announce provider, percent, countdown, clock time, weekly if present, stale.
- Expand `#Preview`s for high/low/stale/dual window.

**Verify**: `make lint && make test` → exit 0

## Test plan

- Unit tests: clock formatter locales if feasible; countdown unchanged.
- Existing store/parsing tests must remain green — do not change provider parsing unless a bug blocks display.
- Manual: Codex only, Cursor only, both, quotas disabled, missing `resetAt`.

## Done criteria

- [ ] Visible providers render card with bar + countdown + time-only clock
- [ ] Traffic-light colors drive % and bar
- [ ] Weekly secondary appears only when it differs (existing rule)
- [ ] No status-item quota additions
- [ ] `make lint && make test` exit 0
- [ ] `plans/README.md` status row for 033 updated

## STOP conditions

- Display requires new API fields not in `UsageQuotaSnapshot` / `UsageWindow` — stop and report.
- Temptation to add status-item badges — out of scope.
- Drift in Current state excerpts.

## Maintenance notes

- Reviewers: height impact on small main windows; ensure 2 providers still fit without crushing Git lists.
- Keep quota domain separate from `AIProviderStore` (023 decision).
- If Mimir reference code is consulted, do not copy credential handling — UI layout inspiration only.
