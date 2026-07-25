# Plan 023: Add AI usage quota foundation with Codex and compact main-panel UX

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 278eb3e..HEAD -- GitMenuBar/App/StatusBarController.swift GitMenuBar/Pages/MainMenu/MainMenuContent.swift GitMenuBar/Pages/Settings/SettingsPage.swift GitMenuBar/Services/Persistence/AppPreferences.swift GitMenuBar/Components/AI/AISettingsSection.swift GitMenuBar/Components/Common/InlineStatusBannerView.swift plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: none
- **Category**: direction
- **Planned at**: commit `278eb3e`, 2026-07-25
- **Issue**: (omit unless published via `--issues`)

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `High/Full`
- **Parallelizable**: `no` — domain model, Codex provider, store wiring, and UX share one surface
- **Reviewer required**: `yes` — local credential reads, undocumented ChatGPT usage endpoint, persistence of snapshots, and background refresh touch security, concurrency, and menu-bar performance
- **Rationale**: This introduces a new subsystem that reads OAuth tokens from disk and calls a third-party usage API. Ambiguity around auth shapes and failure modes requires `implementer`, not `implementer-fast`.
- **Escalate when**: scope expands to status-item glyphs/dots, Keychain writes for refreshed tokens, Claude/Antigravity providers, or Cursor (that is Plan 024).

## Why this matters

GitMenuBar users who also use Codex lose context switching to check session/weekly quotas. Mimir already solves Codex monitoring as a dedicated quota app; GitMenuBar should offer a **secondary, Git-first** view of the same data without becoming a second Mimir. Product decision for v1 (**UX option A**): Settings toggles + a compact strip inside the main panel only — **no status-item badge or color-dot changes**. Codex ships first because its ladder (live API → local JSONL → snapshot) is proven in the MIT-licensed Mimir reference at `~/Documents/Projects/References/Mimir`.

## Current state

- GitMenuBar is a menu-bar Git workflow app. `StatusBarController` owns the single `NSStatusItem` and injects environment objects into `MainMenuView` (`GitMenuBar/App/StatusBarController.swift` around the `rootView = MainMenuView(...)` block with `.environmentObject(aiProviderStore)` etc.).
- Existing `AIProviderStore` / `AIProviderAdapters` / Accounts → **AI Commit Generation** are for commit-message LLM providers and API keys. **Do not extend them for quotas.** Create a separate usage-quota domain.
- Settings Accounts pane currently stacks GitHub + AI commit settings:

  ```swift
  GitHubConnectionSection(setAutoHideSuspended: onSetAutoHideSuspended)
  AISettingsSectionView()
      .padding(.top, 4)
  ```

  (`GitMenuBar/Pages/Settings/SettingsPage.swift` in `AccountsSettingsPaneView`.)
- Main scroll content starts with optional banners then working-tree sections (`GitMenuBar/Pages/MainMenu/MainMenuContent.swift` `mainScrollContent`). Compact usage UI should appear as a **small strip after banners / before working tree**, and must vanish entirely when the feature is disabled or no enabled provider has data.
- Preferences keys live in `GitMenuBar/Services/Persistence/AppPreferences.swift` (`AppPreferences.Keys`). Add usage-related keys there.
- Status item already shows a **dirty-file count badge** via `StatusItemBadgeRenderer`. Out of scope for this plan — do not change badge rendering for quotas.
- Xcode uses `PBXFileSystemSynchronizedRootGroup` for `GitMenuBar` and `GitMenuBarTests`; new files under those folders are auto-included. Do **not** edit `project.pbxproj`.
- Reference implementation for Codex (inspiration only — adapt, do not paste entire files):
  - `~/Documents/Projects/References/Mimir/Sources/Mimir/CodexProvider.swift`
  - `~/Documents/Projects/References/Mimir/docs/SERVICES.md` (Codex section)
  - Ladder: ChatGPT `https://chatgpt.com/backend-api/wham/usage` with Bearer from `~/.codex/auth.json` (also `CODEX_HOME` / `~/.config/codex/auth.json`) → refresh token if needed → local `~/.codex/sessions` latest `.jsonl` `token_count` / `rate_limits` primary=session secondary=weekly → last snapshot.
  - Mimir is MIT (Eray Endes). If substantial portions of parsing logic are adapted, keep attribution in a short code comment near the provider (copyright notice requirement). Do **not** copy UI, telemetry, widgets, or Claude/Antigravity code.
- No `CONTEXT.md` / `DESIGN.md` / ADR yet for usage quotas. Vocabulary for this plan:
  - **Usage provider** — Codex (and later Cursor), not AI commit providers
  - **Session window** — ~5-hour primary rate limit
  - **Weekly window** — secondary rate limit
  - **Snapshot** — last successful non-secret quota reading cached locally
  - **Stale** — showing snapshot because live fetch failed

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift check | `git diff --stat 278eb3e..HEAD -- <in-scope paths>` | empty or understood drift only |
| Incremental gate | `make agent-check` | lint-changed + Debug build exit 0 |
| Full lint | `make lint` | exit 0 |
| Full tests | `make test` | prints tests passed, exit 0 |
| Merge gate | `make lint && make test` | both exit 0 |
| Targeted tests | `xcodebuild test -project GitMenuBar.xcodeproj -scheme GitMenuBar -only-testing:GitMenuBarTests/UsageQuotaParsingTests -derivedDataPath .xcode-build-tests` | exit 0 (after tests exist; adjust class name if renamed) |

## Suggested executor toolkit

- Skills (if available): `macos-app-engineering`, `menubar` (confirm status item unchanged), `swift-conventions`, `security-credentials`, `swift-testing-expert` / `test-strategy`, `delivery-workflow` for gates.
- Reference: `~/Documents/Projects/References/Mimir/Sources/Mimir/CodexProvider.swift` and `docs/SERVICES.md` Codex section.
- Do **not** clone additional references for this plan.

## Scope

**In scope** (create or modify only these):

- `GitMenuBar/Models/UsageQuotaModels.swift` (create)
- `GitMenuBar/Services/UsageQuota/UsageQuotaProviding.swift` (create) — protocol
- `GitMenuBar/Services/UsageQuota/CodexUsageProvider.swift` (create)
- `GitMenuBar/Services/UsageQuota/UsageQuotaStore.swift` (create) — `@MainActor` `ObservableObject`, refresh, snapshot persistence of **non-secret** quota fields only
- `GitMenuBar/Services/UsageQuota/UsageQuotaSnapshotStore.swift` (create) — UserDefaults or Application Support JSON for last snapshots; **never** store tokens
- `GitMenuBar/Components/UsageQuota/UsageQuotaSettingsSection.swift` (create) — Settings toggles + privacy note
- `GitMenuBar/Components/UsageQuota/UsageQuotaStripView.swift` (create) — compact main-panel strip + `#Preview`
- `GitMenuBar/Services/Persistence/AppPreferences.swift` — add keys for master enable + per-provider enable
- `GitMenuBar/Pages/Settings/SettingsPage.swift` — insert usage settings in Accounts pane (below AI commit section or as its own titled block; keep AI commit section intact)
- `GitMenuBar/Pages/MainMenu/MainMenuContent.swift` — embed strip when enabled
- `GitMenuBar/App/StatusBarController.swift` — own/create `UsageQuotaStore`, inject `.environmentObject`, trigger refresh when main window presents (and on a sustainable timer **only while store is enabled**)
- `GitMenuBar/Pages/MainMenu/MainMenuPreviewHarness.swift` — inject a store for previews
- `GitMenuBarTests/UsageQuotaParsingTests.swift` (create) — Codex API/local parsing fixtures
- `GitMenuBarTests/UsageQuotaStoreTests.swift` (create) — enable/disable, stale snapshot, no-token paths with fakes
- `plans/README.md` — status row update after execution

**Out of scope** (do NOT touch):

- `StatusItemBadgeRenderer.swift` / any status-item visual for quotas
- Cursor provider (Plan 024)
- Claude, Antigravity, Gemini quota providers
- Existing `AIProviderStore`, adapters, Keychain AI API keys, atomic commit flows
- Widgets, notifications / low-quota alerts, menu-bar color dots
- Writing refreshed Codex tokens back to `auth.json` (read + in-memory refresh for the request is OK; **persisting rotated tokens is STOP** unless a follow-up plan explicitly allows it with security review)
- Adding new SPM dependencies
- Editing `GitMenuBar.xcodeproj/project.pbxproj`

## Git workflow

- Branch: `advisor/023-ai-usage-quota-codex` (or `feat/023-ai-usage-quota-codex`)
- Commit style from recent history: conventional prefixes such as `feat(service): ...`, `refactor(agents): ...`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Define models and provider protocol

Create `UsageQuotaModels.swift` with value types roughly:

- `UsageProviderID`: `codex` (String raw value; leave room for `cursor` later without implementing it)
- `UsageWindow`: remaining percent (0…100), optional `resetAt`, optional human label (`Session`, `Weekly`)
- `UsageQuotaSnapshot`: provider id, display name, session window, weekly window, optional credit/value rows, `isAvailable`, `isStale`, `statusNote`, `fetchedAt`
- Prefer **remaining** percentages in the model (convert from Mimir-style `used_percent` at the provider boundary).

Create `UsageQuotaProviding`:

```swift
protocol UsageQuotaProviding: Sendable {
    var id: UsageProviderID { get }
    func fetchSnapshot() async -> UsageQuotaSnapshot
}
```

**Verify**: `make agent-check` → exit 0 (files compile even if unused yet).

### Step 2: Implement Codex provider with fixture-friendly parsing

In `CodexUsageProvider.swift`, implement the Mimir ladder adapted to GitMenuBar types:

1. Read auth from `CODEX_HOME/auth.json`, `~/.codex/auth.json`, `~/.config/codex/auth.json` (first hit with access or refresh token).
2. Call `GET https://chatgpt.com/backend-api/wham/usage` with `Authorization: Bearer …`, `Accept: application/json`, optional `ChatGPT-Account-Id`, short timeout (≤10s), identifiable `User-Agent` such as `GitMenuBar`.
3. Parse `rate_limit.primary_window` / `secondary_window` (`used_percent`, `reset_at`) and optional `credits` row.
4. On API failure, scan newest `~/.codex/sessions/**/*.jsonl` from the end for `event_msg` / `token_count` / `rate_limits` primary & secondary.
5. On total failure, return unavailable snapshot (store layer applies last disk snapshot + `isStale`).

Extract pure parsing helpers (e.g. `codexAPIWindow`, JSONL record decode) as `internal` or package-visible functions so tests do not hit the network.

Security rules:

- Tokens stay in local variables for the request only; never write to UserDefaults, logs, or `statusNote`.
- User-visible notes may say `chatgpt usage api`, `local .codex sessions`, `sign in to Codex`, `token expired — open Codex` — never the token string.
- Prefer **not** rewriting `auth.json` after refresh. If refresh is required for the live call, keep the new access token in memory for that fetch only. If the only way to refresh requires writing disk and you cannot avoid it, **STOP** and report.

**Verify**: add `UsageQuotaParsingTests` with JSON fixtures (inline strings) covering used→remaining conversion, missing reset, credits unlimited/has_credits, and a minimal JSONL line. Targeted test command exits 0.

### Step 3: Snapshot cache + UsageQuotaStore

`UsageQuotaSnapshotStore`: persist **only** non-secret snapshot fields keyed by provider id (UserDefaults Data via `JSONEncoder` is fine). Atomic write if using files.

`UsageQuotaStore` (`@MainActor`, `ObservableObject`):

- Reads `@AppStorage` / defaults: master `showAIUsageQuotas` (default **false**), `showCodexUsageQuota` (default **true** once master is on — or both default false; pick **master default false** so v1 is opt-in).
- Holds `[UsageQuotaSnapshot]` for enabled providers.
- `refresh(reason:)` runs providers concurrently with a per-provider timeout (~8s), merges stale snapshots when fetch unavailable, publishes results.
- Timer: if master enabled, refresh on a **≥2 minute** interval while the app is running; also refresh when the main window begins presenting. If master disabled, invalidate timer and clear published snapshots from UI (cache on disk may remain).
- Inject only `CodexUsageProvider` in this plan.

Wire creation in `StatusBarController` next to other stores; pass into main window and settings via `.environmentObject`.

**Verify**: `UsageQuotaStoreTests` with a fake `UsageQuotaProviding` cover: disabled master → empty UI state; enabled + success; enabled + failure → stale flag from prior snapshot; tokens never appear in encoded snapshot Data. `make agent-check` → exit 0.

### Step 4: Settings UI (Accounts pane)

Add `UsageQuotaSettingsSection` with:

- Master toggle: **Show AI usage in menu**
- Nested Codex toggle (disabled when master off)
- Short privacy caption: local session only; tokens not stored by GitMenuBar; requests go only to the provider’s own usage endpoint
- Optional “Refresh now” button calling `store.refresh`

Place it in `AccountsSettingsPaneView` **after** `AISettingsSectionView`, with a clear title distinct from “AI Commit Generation” (e.g. **AI Usage Quotas**). Include `#Preview`.

**Verify**: `make agent-check` → exit 0; manually confirm in Debug that toggles persist via AppPreferences keys.

### Step 5: Compact main-panel strip (UX A)

`UsageQuotaStripView`:

- Hidden when master toggle is off, or when there is no snapshot to show for enabled providers.
- One compact row per available provider: name, session remaining `%`, short reset countdown (`2h 15m` / `—`), traffic-light color on the percentage (green ≥40, amber ≥15, red &lt;15 — match Mimir-ish thresholds or document chosen constants).
- Weekly as secondary caption or trailing text, not a second large card.
- Dim / secondary styling when `isStale`; show `statusNote` as accessibility value or caption.
- Accessibility: label like `Codex usage 62 percent remaining, resets in 2 hours`.
- Match `MacChromeMetrics` / `MacChromeTypography`; no new card chrome beyond existing banner density. Study `InlineStatusBannerView` for padding/material restraint — the strip should be **lighter** than a banner.

Embed in `mainScrollContent` after inline banners / create-repo suggestion and **before** working-tree sections.

Refresh on appear of main content when enabled (`task` / `onAppear` → `store.refresh`).

**Verify**: `#Preview` compiles; `make agent-check` → exit 0.

### Step 6: End-to-end validation and sanitization

- Confirm status item still only reflects Git dirty count (no quota dots).
- Confirm Accounts AI commit section unchanged.
- `rg -n "chatgpt.com/backend-api/wham/usage|UsageQuotaStore|showAIUsageQuotas" GitMenuBar` shows expected call sites only.
- `rg -n "access_token|refresh_token" GitMenuBar/Services/UsageQuota` — only local parsing / Authorization header construction; no logging of those fields.
- Run full merge gate.

**Verify**: `make lint && make test` → both exit 0.

## Test plan

- `UsageQuotaParsingTests`: Codex API window parsing; remaining percent math; credits row omit/include; JSONL primary/secondary extraction; empty sessions → unavailable.
- `UsageQuotaStoreTests`: master off; Codex toggle; fake provider success; failure uses snapshot + `isStale`; encoded snapshot has no token-like keys; refresh no-ops or skips network when disabled.
- Model tests after `GitMenuBarTests/AIProviderStoreTests.swift` / `DirectoryPickerServiceTests.swift` style (`@testable import GitMenuBar`, XCTest).
- Manual (record in PR when opened): enable toggle with Codex signed in → strip appears; quit Codex network (airplane) → stale dimmed data; disable toggle → strip gone; status item badge unchanged with dirty files.

## Done criteria

- [ ] Master preference defaults to **off**; enabling shows Codex strip only when Codex data exists or a stale snapshot exists
- [ ] Codex ladder implemented: API → local JSONL → snapshot
- [ ] No status-item quota visuals
- [ ] No secrets in UserDefaults / snapshot store / logs
- [ ] Existing AI commit settings untouched in behavior
- [ ] `make lint && make test` exit 0
- [ ] New UI files include `#Preview`
- [ ] `plans/README.md` Plan 023 status → DONE
- [ ] No files outside Scope modified (`git status`)

## STOP conditions

- Codex live API auth now requires persisting rotated tokens to disk to remain useful — stop for security design review.
- Auth or usage JSON shape has drifted so fixtures from Mimir no longer parse — stop with sample redacted shape notes (no secrets).
- Implementing the strip appears to require changing `StatusItemBadgeRenderer` or Dock behavior — stop; UX A forbids it.
- Cursor or Claude work is needed for this plan’s done criteria — stop; that is Plan 024 / later.
- A step’s verification fails twice after a reasonable fix attempt.

## Maintenance notes

- Plan 024 adds Cursor behind `UsageQuotaProviding` and a Settings toggle; keep the strip multi-provider-ready (ForEach snapshots).
- Undocumented ChatGPT usage endpoint may break; keep parsing isolated and fixture-covered.
- Reviewers should scrutinize: token lifetime in memory, snapshot contents, refresh timer not firing when disabled, main-thread / actor isolation, and menu-open latency (refresh must not block first paint — show last snapshot immediately, update when fetch completes).
- Deferred: low-quota notifications, status-item accents (UX B), Claude quotas, credit purchase links.
