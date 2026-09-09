# Plan 047: Add OpenRouter as an AI usage quota provider (credit balance)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 8176c3d..HEAD -- GitMenuBar/Models/UsageQuotaModels.swift GitMenuBar/Services/UsageQuota/UsageQuotaStore.swift GitMenuBar/Services/Persistence/AppPreferences.swift GitMenuBar/Components/UsageQuota/UsageQuotaSettingsSection.swift GitMenuBar/Components/UsageQuota/UsageQuotaStripView.swift GitMenuBarTests/UsageQuotaStoreTests.swift plans/README.md CONTEXT.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: Plan 033 (Mimir-style quota cards, DONE) — the strip card
  already renders a window + credits line; no card changes are needed
- **Category**: direction
- **Planned at**: commit `8176c3d`, 2026-07-31
- **Issue**: (omit unless published via `--issues`)

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: `no` — parsing, key storage, store wiring, and Settings
  UI share one provider surface
- **Reviewer required**: `yes` — a new Keychain credential surface and a new
  default provider in the quota store touch security and app-wide refresh
- **Rationale**: Follows the proven Plan 023/024 provider pattern with a new
  Keychain-backed API key; ambiguity around the OpenRouter API key field and
  Keychain wiring favors `implementer`, not `implementer-fast`.
- **Escalate when**: scope expands to the `/key` spend-limit endpoint,
  env-var key resolution, CLI support, status-item glyphs, or changing the
  card layout.

## Why this matters

GitMenuBar tracks Codex and Cursor usage in the main panel. Users who route AI
through OpenRouter currently have no in-app visibility into their account
credits. This plan adds OpenRouter as a third **Usage Provider** whose quota is
the monetary **Credit Balance** on the account (`total_credits - total_usage`
from the official OpenRouter `/credits` endpoint). It reuses the existing card,
store, snapshot cache, and refresh pipeline — no new UI surface.

## Current state

- `GitMenuBar/Models/UsageQuotaModels.swift` defines `UsageProviderID`:
  ```swift
  enum UsageProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
      case codex
      case cursor
      // ...
      var displayName: String {
          switch self { case .codex: return "Codex"; case .cursor: return "Cursor" }
      }
  }
  ```
- `GitMenuBar/Services/UsageQuota/UsageQuotaProviding.swift`:
  ```swift
  protocol UsageQuotaProviding: Sendable {
      var id: UsageProviderID { get }
      func fetchSnapshot() async -> UsageQuotaSnapshot
  }
  ```
- `UsageQuotaSnapshot` (same file set, `UsageQuotaModels.swift`) carries
  `sessionWindow`, `weeklyWindow`, `creditValueText`, `isAvailable`, `isStale`,
  `statusNote`. `UsageWindow(remainingPercent:resetAt:label:durationSeconds:)`
  clamps percent 0…100; when `durationSeconds` is nil, `intervalChip` returns
  `label`.
- `UsageQuotaStore` (`GitMenuBar/Services/UsageQuota/UsageQuotaStore.swift`)
  has per-provider toggles (`showCodexUsageQuota`, `showCursorUsageQuota`),
  `isProviderEnabled(_:)` switch, and a default `providers:` array:
  ```swift
  providers: [any UsageQuotaProviding] = [CodexUsageProvider(), CursorUsageProvider()]
  ```
- `UsageQuotaSettingsSection` (`GitMenuBar/Components/UsageQuota/UsageQuotaSettingsSection.swift`)
  renders master toggle + one `Toggle` per provider + a privacy caption +
  "Refresh now". It has only `@EnvironmentObject usageQuotaStore`.
- Card (`GitMenuBar/Components/UsageQuota/UsageQuotaStripView.swift`): if
  `primaryDisplayWindow` exists it renders the percent bar + reset countdown/
  clock meta row + `creditValueText` at the trailing edge; otherwise it shows
  only the credits text line. `UsageQuotaSnapshotStore.save` persists when at
  least one of `sessionWindow`/`weeklyWindow`/`creditValueText` is present.
- Settings embed: `GitMenuBar/Pages/Settings/SettingsPage.swift`
  `AISettingsPaneView` renders `UsageQuotaSettingsSection()` in the
  "Usage Quotas" `Section` (lines ~258–265). No change needed there.
- Preferences keys: `GitMenuBar/Services/Persistence/AppPreferences.swift`
  `AppPreferences.Keys` has `showCodexUsageQuota`, `showCursorUsageQuota`.
- Keychain pattern to mirror: `GitMenuBar/Services/Credentials/AIKeychainStore.swift`
  uses `SecItem` with service `"com.mourato.GitMenuBar"`,
  `kSecAttrAccessibleAfterFirstUnlock`. The quota domain is separate — do NOT
  extend `AIProviderStore`/`AIKeychainStore`; add a small quota-scoped store.
- Parsing-pattern to mirror: `GitMenuBar/Services/UsageQuota/CodexUsageParsing.swift`
  (an `enum` of static helpers, `internal`, fixture-friendly) and its test
  `GitMenuBarTests/UsageQuotaParsingTests.swift`.
- Reference implementation (adapt, do not paste wholesale):
  `~/Documents/Projects/References/CodexBar/Sources/CodexBarCore/Providers/OpenRouter/OpenRouterUsageStats.swift`
  and `.../OpenRouterProviderDescriptor.swift`. CodexBar is MIT-licensed; keep a
  short attribution comment if parsing logic is adapted. Key facts:
  - `GET https://openrouter.ai/api/v1/credits`, header `Authorization: Bearer <key>`,
    `Accept: application/json`, timeout ≤ 15s.
  - Response: `{ "data": { "total_credits": <Double>, "total_usage": <Double> } }`.
  - `balance = max(0, total_credits - total_usage)`.
  - `usedPercent = total_credits > 0 ? min(100, total_usage / total_credits * 100) : 0`.
  - Balance display uses `String(format: "$%.2f", balance)`.
- Vocabulary: `CONTEXT.md` now defines **AI usage quotas**, **Usage Provider**,
  and **Credit Balance** (OpenRouter has no reset window — the card must show no
  reset countdown for it). Use these terms in names and comments.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift check | `git diff --stat 8176c3d..HEAD -- <in-scope paths>` | empty or understood drift only |
| Incremental gate | `make agent-check` | lint-changed + Debug build exit 0 |
| Targeted tests | `make test` with the new fixtures present | tests pass, exit 0 |
| Full gate | `make lint && make test` | both exit 0 |
| Preview check | `make check-preview` | exit 0 (strip already covered; only if strip previews change) |

## Suggested executor toolkit

- Skills (if available): `swift-conventions`, `security-credentials`,
  `test-strategy`, `menubar` (confirm status item unchanged), `delivery-workflow`.
- Reference: `~/Documents/Projects/References/CodexBar/Sources/CodexBarCore/Providers/OpenRouter/OpenRouterUsageStats.swift`
  and `docs/openrouter.md` in the same repo.

## Scope

**In scope** (create or modify only these):

- `GitMenuBar/Services/UsageQuota/OpenRouterUsageParsing.swift` (create) — pure parsing helpers
- `GitMenuBar/Services/UsageQuota/OpenRouterAPIKeyStore.swift` (create) — Keychain store + protocol + in-memory test double
- `GitMenuBar/Services/UsageQuota/OpenRouterUsageProvider.swift` (create) — the provider
- `GitMenuBar/Models/UsageQuotaModels.swift` — add `.openrouter` case + displayName
- `GitMenuBar/Services/Persistence/AppPreferences.swift` — add `showOpenRouterUsageQuota` key
- `GitMenuBar/Services/UsageQuota/UsageQuotaStore.swift` — add `showOpenRouterUsageQuota`, wire `isProviderEnabled`, default providers array
- `GitMenuBar/Components/UsageQuota/UsageQuotaSettingsSection.swift` — OpenRouter toggle + API-key `SecureField` (Keychain) + caption update
- `GitMenuBar/Components/UsageQuota/UsageQuotaStripView.swift` — add an OpenRouter preview snapshot factory + preview case (UI preview coverage)
- `GitMenuBarTests/OpenRouterUsageParsingTests.swift` (create) — parsing fixtures
- `GitMenuBarTests/UsageQuotaStoreTests.swift` — add OpenRouter toggle test
- `plans/README.md` — index row

**Out of scope** (do NOT touch):

- The `/key` spend-limit endpoint, env-var (`OPENROUTER_API_KEY`) resolution, or
  multiple OpenRouter accounts (deferred; decision 3 in the grill was credits only)
- `AIProviderStore`, `AIKeychainStore`, `AIProviderType`, or any AI commit-generation code — OpenRouter does not become a commit-message provider
- `UsageQuotaStripView` card layout / card view logic (only preview additions)
- Status-item glyphs, notifications, CLI support
- Editing `GitMenuBar.xcodeproj/project.pbxproj` (synchronized root group auto-includes new files)

## Git workflow

- Branch: `feat/047-openrouter-usage-quota`
- Commit style from recent history: `git log --oneline -10` shows `feat(service): ...`, `feat: ...`. Use e.g. `feat(quota): add OpenRouter credit balance provider`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Parsing helpers

Create `GitMenuBar/Services/UsageQuota/OpenRouterUsageParsing.swift` with an
`enum OpenRouterUsageParsing` of `static` helpers (mirror the shape of
`CodexUsageParsing`):

- `static func snapshot(fromCreditsData data: Data) -> UsageQuotaSnapshot?` —
  decode `{ data: { total_credits, total_usage } }`; return nil on any missing/
  invalid field or non-200-shaped payload. Compute:
  - `usedPercent = totalCredits > 0 ? min(100, (totalUsage / totalCredits) * 100) : 0`
  - `remainingPercent = UsageQuotaFormatting.remainingPercent(fromUsed: usedPercent)`
  - `balance = max(0, totalCredits - totalUsage)`
  - `creditValueText = String(format: "$%.2f left", balance)`
  - `sessionWindow = UsageWindow(remainingPercent: remainingPercent, resetAt: nil, label: "Credits", durationSeconds: nil)` — resetAt nil is deliberate: credits have no reset window (CONTEXT: **Credit Balance**).
  - `weeklyWindow = nil`
  - `statusNote = "openrouter credits api"`
  - `isAvailable = true`
- `static func doubleValue(_ raw: Any?) -> Double?` (same coercions as `CodexUsageParsing.doubleValue`).

Include a one-line attribution comment: `// Credits parsing adapted from CodexBar (MIT, steipete).`

**Verify**: `make agent-check` → exit 0 (file compiles even if unused yet).

### Step 2: Keychain store

Create `GitMenuBar/Services/UsageQuota/OpenRouterAPIKeyStore.swift`:

- `protocol OpenRouterAPIKeyStoring: Sendable { func loadKey() -> String?; func saveKey(_ apiKey: String); func deleteKey() }`
- `struct OpenRouterAPIKeyStore: OpenRouterAPIKeyStoring` using `SecItem`
  `kSecClassGenericPassword`, service `"com.mourato.GitMenuBar"`,
  account `"openrouter-api-key"`, `kSecAttrAccessibleAfterFirstUnlock` — mirror
  the `SecItem` calls in `AIKeychainStore.swift` (`delete` then `add` on save;
  `kSecMatchLimitOne` + `kSecReturnData` on load).
- `final class InMemoryOpenRouterAPIKeyStore: OpenRouterAPIKeyStoring` — a
  `@unchecked Sendable` class with an `NSLock` (or a simple `var` + lock) for
  tests.

Security rules (from Plan 023 precedent): the key never goes to UserDefaults,
logs, `statusNote`, or the encoded snapshot. The provider keeps it only in a
local variable for the request.

**Verify**: `make agent-check` → exit 0.

### Step 3: Provider

Create `GitMenuBar/Services/UsageQuota/OpenRouterUsageProvider.swift`:

```swift
struct OpenRouterUsageProvider: UsageQuotaProviding {
    let id: UsageProviderID = .openrouter
    private let urlSession: URLSession
    private let keyStore: any OpenRouterAPIKeyStoring

    init(
        urlSession: URLSession = .shared,
        keyStore: any OpenRouterAPIKeyStoring = OpenRouterAPIKeyStore()
    ) { ... }

    func fetchSnapshot() async -> UsageQuotaSnapshot {
        guard let apiKey = keyStore.loadKey(), !apiKey.isEmpty else {
            return .unavailable(providerID: .openrouter, statusNote: "add OpenRouter API key in Settings")
        }
        // GET https://openrouter.ai/api/v1/credits
        // Authorization: Bearer <apiKey>; Accept: application/json;
        // User-Agent: GitMenuBar; X-Title: GitMenuBar; timeoutInterval: 10
        // On success (200...299 and parseable) return the parsed snapshot.
        // On failure/timeout return .unavailable(providerID: .openrouter, statusNote: "openrouter credits unavailable")
    }
}
```

**Verify**: `make agent-check` → exit 0.

### Step 4: Model, preferences, store wiring

1. `GitMenuBar/Models/UsageQuotaModels.swift` — add `case openrouter` to
   `UsageProviderID` and `return "OpenRouter"` in `displayName`.
2. `GitMenuBar/Services/Persistence/AppPreferences.swift` — add
   `static let showOpenRouterUsageQuota = "showOpenRouterUsageQuota"`.
3. `GitMenuBar/Services/UsageQuota/UsageQuotaStore.swift`:
   - Add `@Published var showOpenRouterUsageQuota: Bool` mirroring
     `showCursorUsageQuota` (persist to the new key, call `handlePreferenceChange()`).
   - Init: `showOpenRouterUsageQuota = defaults.object(forKey: ...) as? Bool ?? true`.
   - `isProviderEnabled`: `case .openrouter: return showOpenRouterUsageQuota`.
   - Default providers: `[CodexUsageProvider(), CursorUsageProvider(), OpenRouterUsageProvider()]`.

**Verify**: `make agent-check` → exit 0.

### Step 5: Settings UI

`GitMenuBar/Components/UsageQuota/UsageQuotaSettingsSection.swift`:

- Add an `@State private var openRouterAPIKey = ""` and an injected
  `let apiKeyStore: any OpenRouterAPIKeyStoring` (default `OpenRouterAPIKeyStore()`)
  — the `#Preview` should pass `InMemoryOpenRouterAPIKeyStore()`.
- Add after the Cursor toggle:
  ```swift
  Toggle("OpenRouter", isOn: $usageQuotaStore.showOpenRouterUsageQuota)
      .toggleStyle(.switch)
      .disabled(!usageQuotaStore.showAIUsageQuotas)

  if usageQuotaStore.showOpenRouterUsageQuota {
      SecureField("OpenRouter API key", text: $openRouterAPIKey)
          .onAppear { if openRouterAPIKey.isEmpty { openRouterAPIKey = apiKeyStore.loadKey() ?? "" } }
          .onChange(of: openRouterAPIKey) { _, newValue in
              let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
              if trimmed.isEmpty { apiKeyStore.deleteKey() } else { apiKeyStore.saveKey(trimmed) }
          }
  }
  ```
- Update the privacy caption to mention the OpenRouter key is stored in the
  Keychain and requests go only to `openrouter.ai/api/v1/credits` (keep the
  existing "never stores OAuth tokens" wording).
- Keep the "Refresh now" button.

**Verify**: `make agent-check` → exit 0; `make check-preview` → exit 0.

### Step 6: Strip preview coverage

`GitMenuBar/Components/UsageQuota/UsageQuotaStripView.swift`:

- Add `static func openrouter(remainingPercent: Int, balanceText: String) -> UsageQuotaSnapshot`
  to `PreviewUsageQuotaSnapshotFactory` (providerID `.openrouter`, `sessionWindow`
  with `resetAt: nil`, `label: "Credits"`, `creditValueText: balanceText`).
- Add one `#Preview("Usage Quota Strip – OpenRouter")` using it (with a Codex or
  Cursor snapshot for contrast).

**Verify**: `make agent-check` → exit 0; `make check-preview` → exit 0.

### Step 7: Tests

Create `GitMenuBarTests/OpenRouterUsageParsingTests.swift` (model after
`GitMenuBarTests/UsageQuotaParsingTests.swift` and
`GitMenuBarTests/CursorUsageParsingTests.swift`), covering:

- Full credits payload → remaining percent, `creditValueText` "$X.XX left",
  `sessionWindow?.resetAt == nil`, `statusNote` "openrouter credits api".
- `total_credits = 0`, `total_usage = 0` → remaining 100, "$0.00 left", still `isAvailable`.
- `total_usage > total_credits` → balance clamps to $0.00, remaining 0.
- Missing/invalid JSON → nil.
- `usedPercent` clamp at 100 when usage ≥ credits.

In `GitMenuBarTests/UsageQuotaStoreTests.swift`, add
`testOpenRouterToggleHidesVisibleSnapshots` mirroring
`testCursorToggleHidesVisibleSnapshots` (use a `FakeUsageQuotaProvider` with
`id: .openrouter` and an OpenRouter-shaped snapshot).

**Verify**: `make lint && make test` → both exit 0.

### Step 8: End-to-end validation and sanitization

- `rg -n "openrouter" GitMenuBar` shows only the new call sites
  (provider, parsing, key store, model, store, settings, preview factory).
- `rg -n "openrouter-api-key|total_credits|total_usage" GitMenuBar/Services/UsageQuota`
  shows expected parsing/keychain sites only; no key value ever logged or stored
  in defaults (the `SecureField` binding never appears in a snapshot).
- Run the full gate.

**Verify**: `make lint && make test` → both exit 0; `git status` shows no files
outside the Scope list.

## Test plan

- `OpenRouterUsageParsingTests` — happy path, zero-credit account, over-usage
  clamp, malformed payloads, percent clamp (list above).
- `UsageQuotaStoreTests.testOpenRouterToggleHidesVisibleSnapshots` — toggle-off
  hides an available OpenRouter snapshot.
- Existing tests must stay green: the default-providers array change is
  invisible to store tests because they inject `providers:` explicitly.
- Manual (record in PR): add a real OpenRouter key in Settings → strip shows an
  OpenRouter card with % and `$ balance` and no reset countdown; remove key →
  card disappears; master toggle off → strip gone; status-item badge unchanged.

## Done criteria

- [ ] `UsageProviderID.openrouter` exists; default toggle on; key persisted only in Keychain
- [ ] OpenRouter card renders percent bar + `$X.XX left` and no reset countdown/clock values (both `—`)
- [ ] No secrets in UserDefaults / snapshot store / logs / `statusNote`
- [ ] `make lint && make test` exit 0; new parsing tests pass
- [ ] New/changed UI previews pass `make check-preview`
- [ ] `plans/README.md` Plan 047 status row added and set to DONE
- [ ] No files outside Scope modified (`git status`)

## STOP conditions

- The OpenRouter `/credits` response shape differs from `{ data: { total_credits, total_usage } }`
  (e.g. requires the `/key` endpoint or extra headers to authenticate) — stop with the redacted
  observed shape note (no secret values) for a contract review.
- The Keychain field cannot be scoped to service `"com.mourato.GitMenuBar"` without touching
  `AIKeychainStore` — stop; reusing that store's provider-UUID keys for a fixed account is out of scope.
- A step's verification fails twice after a reasonable fix attempt.
- Implementing the card display requires changing `UsageQuotaStripView` card logic (not just previews) — stop; the existing window+credits card already supports it.

## Maintenance notes

- The `/credits` endpoint is official and documented (unlike the Codex/Cursor
  endpoints); it still may evolve — parsing stays isolated and fixture-covered.
- Deferred (grill decisions): `/key` spend-limit enrichment, env-var key
  resolution, multi-account OpenRouter. If a user wants a key spending limit as
  the primary meter, that is a follow-up plan touching `/key`.
- Reviewers should scrutinize: Keychain service/account naming, key lifetime in
  memory, that `statusNote` never carries the key, and that the store's default
  providers array change doesn't trigger unexpected network calls before the
  master toggle is enabled (it won't — disabled providers are skipped).
