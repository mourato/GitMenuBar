# Plan 024: Add Cursor usage quota provider behind the shared usage strip

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 278eb3e..HEAD -- GitMenuBar/Services/UsageQuota GitMenuBar/Models/UsageQuotaModels.swift GitMenuBar/Components/UsageQuota GitMenuBar/Services/Persistence/AppPreferences.swift GitMenuBar/App/StatusBarController.swift plans/023-ai-usage-quota-foundation-and-codex.md plans/README.md`
> If Plan 023 has not landed, STOP. If in-scope files drifted, reconcile with live code before proceeding.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: HIGH
- **Depends on**: plans/023-ai-usage-quota-foundation-and-codex.md
- **Category**: direction
- **Planned at**: commit `278eb3e`, 2026-07-25

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `High/Full`
- **Parallelizable**: `no` — depends on Plan 023’s protocol, store, Settings, and strip
- **Reviewer required**: `yes` — reads Cursor IDE SQLite session DB and calls an undocumented dashboard API; security and fragility review required
- **Rationale**: Cursor has no official personal usage API. Implementation mirrors community patterns (e.g. CursorBar) and must stay isolated, fixture-tested, and opt-in.
- **Escalate when**: Cursor requires browser cookies the local DB no longer holds, team-only Admin APIs, or status-item UX changes.

## Why this matters

Cursor quotas are as operationally useful as Codex for many GitMenuBar users, but Mimir does **not** implement Cursor. After Plan 023 ships the shared usage domain and UX option A strip, Cursor should plug in as a second `UsageQuotaProviding` without redesigning Settings or the main panel. Expect higher breakage risk than Codex; degrade to clear “open Cursor and sign in” / stale snapshot states.

## Current state

- **Prerequisite**: Plan 023 must be DONE. Expect these to exist:
  - `UsageQuotaProviding`, `UsageQuotaSnapshot`, `UsageProviderID`
  - `UsageQuotaStore` + snapshot cache
  - `UsageQuotaStripView` iterating snapshots
  - Settings master toggle + Codex toggle
- Cursor is **absent** from Mimir (`~/Documents/Projects/References/Mimir/docs/SERVICES.md` lists Claude, Codex, Antigravity only).
- Community pattern (inspiration — adapt under GitMenuBar architecture; verify against live Cursor install during implementation):
  1. Read `cursorAuth/accessToken` from SQLite `ItemTable` in  
     `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`
  2. Use that token to call Cursor usage endpoints (CursorBar documents `GET https://cursor.com/api/usage-summary`; other tools also mention legacy `GET https://cursor.com/api/usage` and `api2.cursor.sh` period-usage). Prefer the **smallest** endpoint set that yields billing-period remaining % and reset/end date for individual accounts.
  3. **Never store** the token; read fresh each refresh.
  4. If the DB is locked by a running Cursor, copy to a temp file before opening (common SQLite pattern).
- GitMenuBar has **no** SQLite SPM package today (only KeyboardShortcuts + Settings). Prefer system SQLite3 via a tiny internal helper, or `sqlite3` CLI only if unavoidable — **do not** add a package unless STOP and operator approves.
- UX remains option **A**: Settings toggle + same compact strip; **no** status-item changes.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Confirm 023 landed | `rg -n "UsageQuotaStore|CodexUsageProvider" GitMenuBar/Services/UsageQuota` | matches exist |
| Incremental gate | `make agent-check` | exit 0 |
| Targeted tests | `xcodebuild test -project GitMenuBar.xcodeproj -scheme GitMenuBar -only-testing:GitMenuBarTests/CursorUsageParsingTests -derivedDataPath .xcode-build-tests` | exit 0 |
| Merge gate | `make lint && make test` | both exit 0 |

## Suggested executor toolkit

- Skills: `security-credentials`, `swift-conventions`, `test-strategy`, `macos-app-engineering`
- Optional read-only reference: https://github.com/c-johannesen/cursorbar (TokenProvider / usage-summary flow). Do not vendor their app UI.
- Local Cursor paths on the operator Mac for smoke tests only; never commit DB files or tokens.

## Scope

**In scope**:

- `GitMenuBar/Models/UsageQuotaModels.swift` — add `cursor` to `UsageProviderID` if not already reserved
- `GitMenuBar/Services/UsageQuota/CursorUsageProvider.swift` (create)
- `GitMenuBar/Services/UsageQuota/CursorAuthTokenReader.swift` (create) — SQLite/token read helper
- `GitMenuBar/Services/UsageQuota/UsageQuotaStore.swift` — register Cursor provider; honor per-provider toggle
- `GitMenuBar/Services/Persistence/AppPreferences.swift` — `showCursorUsageQuota` key
- `GitMenuBar/Components/UsageQuota/UsageQuotaSettingsSection.swift` — Cursor toggle + note that the API is unofficial and may break
- `GitMenuBarTests/CursorUsageParsingTests.swift` (create)
- `GitMenuBarTests/CursorAuthTokenReaderTests.swift` (create) — use a **temp** SQLite fixture DB checked into tests or built in `setUp`, never real user DB
- `plans/README.md` — status update

**Out of scope**:

- Status-item / agents badge / CursorBar agent monitoring
- Team Admin / Analytics APIs
- Storing Cursor tokens in Keychain or UserDefaults
- Changing Codex provider behavior except shared store registration
- Editing `project.pbxproj`
- Adding SPM dependencies without STOP + approval

## Git workflow

- Branch: `advisor/024-ai-usage-quota-cursor` off the branch/main that contains Plan 023
- Commit style: `feat(service): ...`
- Do NOT push/PR unless instructed

## Steps

### Step 1: Confirm Plan 023 contracts

Open the live `UsageQuotaProviding` / `UsageQuotaSnapshot` / strip ForEach. Confirm adding a second snapshot automatically appears in the strip. If the strip is Codex-hardcoded, fix that **minimally** here so both providers render.

**Verify**: `rg -n "UsageProviderID|ForEach" GitMenuBar/Components/UsageQuota GitMenuBar/Models` shows a generic iteration; `make agent-check` → exit 0.

### Step 2: Token reader with fixture DB

Implement `CursorAuthTokenReader` that:

- Resolves the default `state.vscdb` path under Application Support `Cursor` (allow injectable path for tests).
- Opens SQLite read-only; on lock/`SQLITE_BUSY`, copy DB (+ `-wal`/`-shm` if needed) to a temp directory and open the copy.
- Queries the key used by Cursor for the access token (community: `cursorAuth/accessToken` in `ItemTable`). Keep the key string in one constant.
- Returns `String?`; never logs the value.

Build a minimal SQLite fixture in tests with a dummy JWT-shaped string and assert read success; assert missing key → nil.

**Verify**: `CursorAuthTokenReaderTests` pass; `make agent-check` → exit 0.

### Step 3: Cursor usage fetch + normalize

`CursorUsageProvider`:

- Obtain token via reader; if nil → unavailable snapshot with note `sign in to Cursor`.
- Call the chosen usage endpoint(s) with short timeout; map response into `UsageQuotaSnapshot`:
  - Prefer a single **remaining percent** for the primary strip metric (plan/billing period).
  - Map billing cycle end to `resetAt` when available.
  - Put secondary breakdown (auto vs API dollars, etc.) only if it fits existing optional value rows without bloating the strip; otherwise keep in `statusNote` / omit from v1 strip.
- On HTTP/parse failure → unavailable (store applies stale snapshot).
- Document the endpoint URL(s) in a comment as **unofficial / may break**.

Because live response shapes drift, isolate decoding in pure functions tested with **redacted fixtures** captured during development (no real account ids or tokens in the repo).

**Verify**: `CursorUsageParsingTests` pass with fixtures; no network in unit tests.

### Step 4: Wire store + Settings

- Append `CursorUsageProvider` to the store’s provider list when Cursor toggle is on (and master on).
- Add Settings toggle under the Plan 023 usage section.
- Privacy caption: token read from local Cursor DB each refresh; not stored; unofficial API.

**Verify**: store tests with fake Cursor provider; Settings preview still compiles; `make agent-check` → exit 0.

### Step 5: Manual smoke + merge gate

Manual checklist (operator machine with Cursor signed in):

1. Master + Cursor toggles on → strip shows Cursor % or clear unavailable note
2. Codex still works when both enabled (order: Codex then Cursor, or alphabetical — pick one and test)
3. Sign-out / missing DB → friendly note, no crash
4. Status item unchanged

**Verify**: `make lint && make test` → exit 0.

## Test plan

- Fixture SQLite token read / missing key / injectable path
- Usage JSON fixtures → remaining % + reset mapping
- Store: Cursor disabled skipped; enabled failure → stale
- Ensure snapshot encoder still omits any auth fields

## Done criteria

- [ ] Plan 023 contracts reused; strip shows Cursor without status-item changes
- [ ] Token never persisted by GitMenuBar
- [ ] Unit tests cover reader + parser with fixtures (no live credentials in repo)
- [ ] Settings toggle works with master gate
- [ ] `make lint && make test` exit 0
- [ ] `plans/README.md` Plan 024 → DONE

## STOP conditions

- Plan 023 not merged / contracts missing
- Token no longer present in `state.vscdb` and requires interactive browser cookie paste — stop; do not add manual cookie UI in this plan
- Implementation seems to need a new SPM SQLite package — stop for approval
- Usage endpoint returns only team-admin shapes for the operator account — stop with findings
- Verification fails twice after reasonable fixes

## Maintenance notes

- Treat Cursor decoding as the most likely break point after IDE updates; keep fixtures and a single decode entry point.
- Reviewers: temp DB copy cleanup, no token logging, timer still gated by master toggle, strip density with two providers.
- Deferred: agent running counts, overspend gauges, CursorBar-style menu-bar meters (conflicts with GitMenuBar Git badge / UX A).
