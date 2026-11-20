# ADR 0026: Code-level decisions moved out of comments

Status: Accepted
Date: 2026-11-20

## Context

Source code no longer carries comments; the `no_comments` lint rule from the
`delete-comment` skill enforces this with a ratchet baseline. Some comments
recorded non-obvious constraints that a future change could break. This ADR
keeps those constraints, grouped by subject, with the file that owns each one.

## Decision

Each entry below is a constraint the code must keep. Change the code and this
ADR together. When an entry grows into a real design choice, move it into its
own ADR.

### AI credential storage

- `GitMenuBar/Services/AI/AICommitCoordinator.swift`: Quota-section lifecycle for fixed credentials shared with AI providers (OpenRouter). Writes the Keychain item and syncs the stored-key flag on every AI provider that resolves to the same credential, so generation readiness follows the saved key.

### Agent process detection

- `GitMenuBar/Services/Agents/AgentActivityDetector.swift`: KERN_PROCARGS2 stores executable path, padding, then argc NUL-terminated arguments.
- `GitMenuBar/Services/Agents/AgentActivityDetector.swift`: Multi-project servers' launch cwd does not identify their active projects.

### Antigravity quota mapping

- `GitMenuBar/Services/UsageQuota/AntigravityUsageParsing.swift`: Antigravity's model-config endpoints report per-model remaining quota, not a weekly window. Keep those readings model-scoped unless the provider explicitly identifies a five-hour or weekly bucket.

### App delegate lifecycle

- `GitMenuBar/App/GitMenuBarApp.swift`: The app delegate keeps a strong reference to the status bar controller; AppKit retains neither the controller nor its status item.
- `GitMenuBar/App/GitMenuBarApp.swift`: Check the login item status only after the controller is created; the call is optional-chained and silently does nothing before.

### AppKit tooltip behavior

- `GitMenuBar/Components/Branches/BranchManagementRowView.swift`: An empty `.help("")` still registers an AppKit tooltip, so attach it only when there is a reason. Hover state lives in this view, not the branch.

### Auto-fetch refresh behavior

- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift`: With auto-fetch on, the selected repository's behind state would otherwise stay stale until the next background tick, hiding Sync.

### Branch cleanup safety gates

- `GitMenuBar/Services/Git/GitCleanupRepository.swift`: Revalidates against the snapshot right before `execute`; nil means safe to run.
- `GitMenuBar/Services/Git/GitCleanupRepository.swift`: Single validate-execute-report pipeline: identity guard, then serial per-item execution gated on snapshot revalidation before each destructive step.
- `GitMenuBar/Services/Git/GitCleanupRepository.swift`: `git branch --delete` is the final detached-worktree guard after a successful removal.

### Branch integration detection

- `GitMenuBar/Services/Git/GitBranchService+Queries.swift`: Local branches with changes not yet in the selected local default branch. This is Git reachability plus cherry-pick equivalence, not GitHub pull-request merge status.
- `GitMenuBar/Services/Git/GitCleanupRepository+Queries.swift`: Local branches with commits whose changes are not yet in the local default branch: `--no-merged` reachability minus branches whose commits were all cherry-picked. A failed `git cherry` keeps the branch, so the result errs toward "not integrated". Returns nil when Git cannot list branches.

### Claude Code credential handling

- `GitMenuBar/Services/UsageQuota/ClaudeCodeUsageProvider.swift`: Claude Code owns its keychain item. Refreshing would rotate the refresh token it holds, so keychain credentials are only read; Claude Code refreshes them on its next run.
- `GitMenuBar/Services/UsageQuota/ClaudeCodeUsageProvider.swift`: Reads through `/usr/bin/security`: Claude Code creates its item with that tool, so the item's access list already trusts it and no keychain prompt appears, unlike `SecItemCopyMatching`.

### Claude usage API quirks

- `GitMenuBar/Services/UsageQuota/ClaudeCodeUsageParsing.swift`: The OAuth usage API reports utilization as a 0-100 percentage; 1.0 means 1% used.
- `GitMenuBar/Services/UsageQuota/ClaudeCodeUsageParsing.swift`: The Claude usage endpoints report `resets_at` with microsecond precision (`2026-10-16T18:10:00.274725+00:00`), which `[.withInternetDateTime]` alone rejects, while the fractional formatter rejects a plain `2030-01-20T12:00:00Z`. Both options are mutually exclusive, so try the fractional form first and fall back to the standard one.

### Codex reset credit redemption

- `GitMenuBar/Services/UsageQuota/CodexUsageParsing.swift`: Decode CodexBar-compatible reset-credit inventory payloads. `available_count` is authoritative; the credit list only supplies per-reset expiry.
- `GitMenuBar/Services/UsageQuota/CodexUsageParsing.swift`: Network, proxy, or unexpected response. ChatGPT may still have applied the reset.
- `GitMenuBar/Services/UsageQuota/CodexUsageProvider.swift`: Redeems one reset credit. Each call is one user action: it sends a fresh idempotency key and retries only after a 401 (the server did not process that attempt).

### Commit history ordering

- `GitMenuBar/Pages/MainMenu/MainMenuSnapshotModel.swift`: A commit is "future" when it appears before the current HEAD in the history list, which happens after a reset backwards. This holds only while `commitHistory` is newest-first.

### Cost scan refresh gating

- `GitMenuBar/Services/UsageQuota/UsageQuotaStore.swift`: Monthly spend estimate rides along without holding provider-refresh timing hostage. The scan gate is time-based for every reason: while the last scan is still fresh, a manual quota refresh only re-queries providers instead of also enumerating the JSONL sessions again.
- `GitMenuBar/Services/UsageQuota/UsageQuotaStore.swift`: Captured before the detached task so the @MainActor store is not referenced from the scan; resolves fresh, stale-on-failure, or no catalog so the scan prices against live rates when available.

### Cursor token handling

- `GitMenuBar/Services/UsageQuota/CursorAuthTokenReader.swift`: Reads Cursor IDE session tokens from the local VS Code SQLite state database. Tokens are read fresh on each call and must never be persisted by callers.

### File watcher threading

- `GitMenuBar/Services/Git/MonitoredProjectFileWatcher.swift`: Lifecycle methods are called by the Main Actor-owned monitor store. The FSEvents callback only reads the immutable context retained by the stream.

### Gemini usage provider quirks

- `GitMenuBar/Services/UsageQuota/GeminiUsageProvider.swift`: expiryDate in ~/.gemini/oauth_creds.json is either ms or seconds
- `GitMenuBar/Services/UsageQuota/GeminiUsageProvider.swift`: Cloud Resource Manager is only a fallback for accounts where loadCodeAssist does not return the managed Gemini project.

### Git test environment isolation

- `GitMenuBarTests/TestSupport.swift`: Align normal and bare fixtures without depending on the host default branch.

### GitHub open counts query

- `GitMenuBar/Services/GitHub/GitHubOpenCountsReader.swift`: Uses raw `-f` fields so numeric or `@`-prefixed names stay strings, and targets the remote's host so GitHub Enterprise remotes are not sent to github.com.
- `GitMenuBar/Services/GitHub/GitHubOpenCountsReader.swift`: Accepts counts even when GraphQL also reports non-fatal `errors`.

### Haptic feedback

- `GitMenuBar/Components/Common/HapticFeedback.swift`: AppKit's default performer selects the current input device and may suppress feedback when hardware or user settings do not support it. Silence is expected, not a defect.

### Independent reimplementation constraint

- `GitMenuBar/Components/Common/SidePanel.swift`: Trailing contextual column for the main workbench. Independent Workbench-token reimplementation — do not copy upstream sources.

### Keychain access group and accessibility

- `GitMenuBar/Services/Credentials/KeychainItemClient.swift`: Access group shared by every stored credential. The value must stay in sync with the `keychain-access-groups` entry in `GitMenuBar/GitMenuBar-KeychainAccessGroups.entitlements`.
- `GitMenuBar/Services/Credentials/KeychainItemClient.swift`: Accessibility applied when an item is created. Each store keeps the contract it already had so existing items are not rewritten with a different policy.
- `GitMenuBar/Services/Credentials/KeychainItemClient.swift`: Query for one generic-password item. The legacy file keychain ignores `kSecAttrAccessGroup`; it becomes authoritative once the signature carries a provisioning profile that authorizes the group.

### Lucide icon catalog

- `GitMenuBar/Components/Common/LucideContentUnavailableView.swift`: Centered empty-state layout rendered through the Lucide catalog. Apple's content-unavailable view only accepts SF Symbol names, so every empty state in the app uses this view instead.
- `GitMenuBar/Components/Common/LucideIconView.swift`: Catalog-backed interface icons (Lucide, ISC). Call sites never name an SF Symbol or a Lucide file directly: pick a `LucideIconName` case and render it through `LucideIconView`, `Label(lucide:)`, or `NSImage(lucide:)`. New `systemName:` / `systemImage:` / `systemSymbolName:` uses outside this file fail `make lint`; the `questionmark` fallback below is the single sanctioned exception.

### Main menu keyboard handling

- `GitMenuBar/Pages/MainMenu/MainMenuKeyboardNavigation.swift`: When the command palette is presented, MainMenuCommandPaletteView owns arrow/enter/escape via onKeyPress on its focused search field. This guard prevents the main list handler from competing with it.

### Main window toolbar layout

- `GitMenuBar/App/MainWindowToolbarController.swift`: The title is a toolbar item so branch context can sit right beside it; the window title stays set for the Window menu and accessibility.
- `GitMenuBar/App/MainWindowToolbarController.swift`: A plain label, not a control: keep it out of the toolbar's glass item background.
- `GitMenuBar/App/MainWindowToolbarController.swift`: Wraps a toolbar view with horizontal insets; toolbar items add no spacing around custom views.
- `GitMenuBar/App/MainWindowToolbarRepositoryState.swift`: Keep the item around while a fetch is running so its progress stays visible.

### Menu hosting view sizing

- `GitMenuBar/App/StatusBarController+UsageQuotaMenu.swift`: A menu-item host that follows its SwiftUI content size. A quota refresh can change the cards while the menu is open; a frozen frame would clip the new content or draw it over the menu items below.

### Merge-to-default flow

- `GitMenuBar/Services/Git/GitBranchService+MergeToDefault.swift`: Merges `featureBranch` into the detected default branch *without* deleting anything. Stashes uncommitted work, switches to the default branch, merges, then restores the stash. Cleanup is a separate, explicit step via ``cleanupMergedBranchAsync(featureBranch:cleanupOption:repositoryPath:)`` so the user is never forced to pick a destructive option just to merge.

### Meter style preference persistence

- `GitMenuBar/Services/UsageQuota/UsageQuotaPresentationPreferences.swift`: Line is the default compact style: a stored raw value that is absent or no longer known falls back to it, while every valid stored value keeps its earlier choice.

### Observation test timing quirks

- `GitMenuBarTests/MonitoredProjectsStoreTests.swift`: Observation fires before mutation; inspect the completed batch on the actor.
- `GitMenuBarTests/TestSupport.swift`: Re-evaluates `condition` under observation tracking, so a change made after the check always re-runs it. Checking outside tracking could miss a background change.

### OpenCode Go key handling

- `GitMenuBar/Services/UsageQuota/OpenCodeGoUsageProvider.swift`: Chave configurada rejeitada: erro explícito, sem mascarar com estimativa local de outra conta. A cópia em memória pode estar defasada, então a keychain é relida na próxima consulta.

### OpenCode Go usage estimate

- `GitMenuBar/Services/UsageQuota/OpenCodeGoLocalUsage.swift`: Device-local OpenCode Go cost estimate from `~/.local/share/opencode/opencode.db`. Ported from CodexBar's `OpenCodeGoLocalUsageReader` (MIT, steipete) with one deliberate simplification: CodexBar materializes every usage row and keeps a 4 MiB cache; Fase 1 aggregates inside SQLite (`SUM`/`MIN` per window) so a large local history never enters Swift memory. SQL filters, the `opencode-go` provider predicate, legacy `message`/`part` + v2 `session_message` coverage, migrated-message dedup, and the fixed $12/$30/$60 denominators are unchanged. Like CodexBar, these denominators are fixed estimates, not detected subscription tiers, and local history covers only this device.

### Project sidebar status model

- `GitMenuBar/Models/ProjectStatusModels.swift`: Projects sidebar groups, ordered by the next action the operator takes. Working (a running agent) is assigned by the sidebar, not by Git state.
- `GitMenuBar/Models/ProjectStatusModels.swift`: One GitHub open total as a sidebar badge can state it. Known positive totals render as badges; a known zero is intentionally omitted.
- `GitMenuBar/Models/ProjectStatusModels.swift`: Non-GitHub remotes show no badge: there is no open total to compare. Known zero totals also show no badge. Totals come only from the counts read, never from the limited PR list.
- `GitMenuBar/Models/ProjectStatusModels.swift`: Sidebar badge state for the repository's open totals. A failed refresh keeps the last GitHub status, so its totals are not current and show as unavailable instead of as fresh readings.
- `GitMenuBar/Models/ProjectStatusModels.swift`: Stale data from a failed refresh never raises a dot.
- `GitMenuBar/Models/ProjectStatusModels.swift`: Reads the pull-request detail list, so it sees only the listed pull requests, never the repository total.
- `GitMenuBar/Models/ProjectStatusModels.swift`: Local-only branches (no upstream) and stashes are intentional in agent workflows; they do not drive project attention or sidebar state.
- `GitMenuBar/Models/ProjectStatusModels.swift`: Row facts, most urgent first, so truncation never hides which fact matters. The status dot's cause always leads: failing checks, then behind or diverged, then uncommitted changes. Every Needs Action or In Review row states at least one fact, so it never reads "Up to date".
- `GitMenuBar/Services/Git/ProjectStatusReader.swift`: Counts come only from the GraphQL read, so a failed PR detail list does not hide them; the reason describes the counts the overview shows.

### Project status refresh modes

- `GitMenuBar/Services/Git/ProjectMonitorStore.swift`: Local reads carry the previous snapshot's GitHub status and branch health through the mode so file-driven refreshes skip those reads.

### Pull flow options

- `GitMenuBar/App/MainMenuActionCoordinator.swift`: Behind-only with a clean tree fast-forwards either way, so choosing between merge, rebase, and a new branch only helps when local commits and remote commits diverged.

### Quota API timestamp parsing

- `GitMenuBarTests/ClaudeCodeUsageTests.swift`: The usage endpoints report `resets_at` with microsecond precision, which the plain `.withInternetDateTime` formatter rejects.

### Quota provider drag payload

- `GitMenuBar/Components/UsageQuota/QuotaProviderRowView.swift`: App-private drag payload, so only provider rows accept a dragged provider. Text fields ignore it, unlike a plain-string payload.

### Quota refresh scheduling

- `GitMenuBar/Services/UsageQuota/UsageQuotaStore.swift`: Only manual refreshes reach here with non-nil work in flight.

### Quota window resolution

- `GitMenuBar/Components/UsageQuota/UsageQuotaStripView.swift`: Same window resolution as the footer summary items, so the strip value never names a different window than the drawn meter.
- `GitMenuBar/Components/UsageQuota/UsageQuotaSummaryResolution.swift`: `min(by:)` keeps the first minimum, so ties honor the declared order and models keep their provided order.

### Sidebar count column sizing

- `GitMenuBar/Components/Common/WorkbenchMetrics.swift`: AppKit twin of `sidebarCount` for ranking count widths; change both together.
- `GitMenuBar/Components/Projects/ProjectSidebarRowView.swift`: Ranking only: the hidden guide view owns the actual column width, so a near-tie between two strings cannot change the rendered size.

### Sidebar selection styling

- `GitMenuBar/Components/Projects/ProjectsSidebarView.swift`: Navigation stays neutral while the focused content owns the accent selection.

### Subprocess pipe handling

- `GitMenuBar/Services/UsageQuota/AntigravityCLIUsageReport.swift`: Drain stdout while the process runs so a full pipe buffer cannot stall it.

### Subscription error handling

- `GitMenuBar/Services/AI/ChatGPTSubscriptionManager.swift`: Cancellation has no verdict; the caller owns the replacement state.

### SwiftUI representable update deferral

- `GitMenuBar/Components/Projects/SidebarPresenceObserver.swift`: Defer publication out of SwiftUI's representable update.

### Sync-all safety rules

- `GitMenuBar/Services/Git/ProjectMonitorStore+SyncAll.swift`: A snapshot is safe to pull without asking when the remote is strictly ahead, nothing local needs pushing, and the tree is clean: the pull can only fast-forward, so it never creates a merge commit or a conflict.

### Test gate race ordering

- `GitMenuBarTests/UsageQuotaStoreTestSupport.swift`: Register the continuation before notifying the test so opening the gate cannot race with pending-state installation.

### Toolbar icon canvas sizing

- `GitMenuBar/App/AppSettingsWindowController.swift`: Settings `.toolbarItems` items fill a ~32pt box with non-symbol images, while SF Symbols draw at ~17-20pt. Keep the canvas at 32 and the glyph near the symbol optical size; calibrate 17-20.
- `GitMenuBar/Components/Common/LucideIconView.swift`: Canvas render for hosts that stretch non-symbol images to fill the box (ex.: Settings `.toolbarItems` items use a ~32pt box, while SF Symbols draw their glyph at ~17-20pt). Draws the catalog glyph inset and centered on a fixed canvas; the drawing handler re-renders per screen scale, so it stays sharp @1x/@2x. Cached per name+canvas+glyph.

### Unchecked Sendable justifications

- `GitMenuBar/Services/Git/GitRepositoryContext.swift`: Unchecked: wraps UserDefaults, which is thread-safe but not Sendable.
- `GitMenuBar/Services/UsageQuota/OpenRouterUsageParsing.swift`: Unchecked: wraps UserDefaults, which is thread-safe but not Sendable.
- `GitMenuBarTests/TestSupport.swift`: `PromptCapture` and `PromptListCapture` are `@unchecked Sendable` because `MockURLProtocol` handlers run on background `URLSession` threads; their `NSLock` is what makes that true.

### Update check failures

- `GitMenuBar/Services/Platform/UpdateChecker.swift`: The update check fails silently on launch so it never interrupts the user.

### Usage cost scan dedupe

- `GitMenuBar/Services/UsageQuota/UsageQuotaCostEstimate.swift`: `token_usage_record` and `token_count` describe the same turns; prefer the former.

### Usage pricing tables

- `GitMenuBar/Services/UsageQuota/UsageQuotaAPIPricing.swift`: API-equivalent per-token pricing used by the monthly spend-estimate card. Built-in tables are ported from CodexBar's `CostUsagePricing` (MIT, Peter Steinberger — see THIRD-PARTY-NOTICES.md); the `claude-*-5` rows come from a models.dev catalog snapshot (2026-10-07) and need re-checking when the table is next updated. Token math mirrors CodexBar: Codex `input_tokens` already includes cached reads as a subset, so cached and written tokens are split out before billing; Claude bills 1h cache creation at 2x the input rate. Resolution is catalog-first (live models.dev data, ported from CodexBar's `ModelsDevPricing.swift`); the bundled tables below are the offline fallback, so new model IDs price correctly once the catalog is cached.
- `GitMenuBar/Services/UsageQuota/UsageQuotaAPIPricing.swift`: Catalog-first resolution; the bundled table is the offline fallback. Missing cache rates fall back to the input rate, matching Claude's documented cache pricing and CodexBar's models.dev conversion.
- `GitMenuBar/Services/UsageQuota/UsageQuotaAPIPricingTables.swift`: https://developers.openai.com/api/docs/models/gpt-6-astra and /api/docs/pricing. The full request switches to long-context rates above 272K input tokens, including Fast mode.
- `GitMenuBar/Services/UsageQuota/UsageQuotaAPIPricingTables.swift`: GPT-5.6 Sol/Terra/Luna (OpenAI pricing page + model cards). Long context: prompts with >272K input tokens are 2x input / 1.5x output for the full request. Cache writes: 1.25x uncached input. API Fast support and multipliers are applied separately after Standard pricing resolves from models.dev or this bundled fallback.
- `GitMenuBar/Services/UsageQuota/UsageQuotaAPIPricingTables.swift`: GPT-6.1 Sol (models.dev catalog snapshot 2026-10-13). Long context: >272K input tokens bill 2x input / 1.5x output for the full request.

### Usage quota window ordering

- `GitMenuBar/Models/UsageQuotaModels.swift`: The tertiary monthly window. Behaves like a model window for display and exhaustion, but keeps its own slot in the quiet fallback order (Session → Weekly → Monthly → tightest model).

### Working tree discard safety

- `GitMenuBar/Services/Git/GitWorkingTreeService.swift`: Resolve parents, but preserve a final symlink so discard removes the link itself.

### Working-tree selection identity

- `GitMenuBar/Pages/MainMenu/MainMenuInteractionModels.swift`: Keeps list identity scoped to the visible working-tree section while leaving selection identity semantic and section-aware.
- `GitMenuBar/Pages/MainMenu/MainMenuWorkspaceState.swift`: Keeps a selected file attached to its working-tree row when staging moves that row between sections. The old semantic ID must disappear before its counterpart can replace it, so partial staging cannot mix two visible rows for the same path.

### macOS 26 control tinting

- `GitMenuBar/Components/WorkingTree/WorkingTreeSectionHeaderView.swift`: Keeps the selected segment neutral: macOS 26 tints it with the system accent by default, which competes with the prominent Commit action. A secondary fill still marks the selected segment clearly.

### models.dev catalog decoding

- `GitMenuBar/Services/UsageQuota/UsageQuotaModelsDev.swift`: Models are keyed arbitrarily in the live catalog, so decode them tolerantly and skip entries that do not fit the shape. justified: Swift protocol existential, not a type-check suppression.
- `GitMenuBar/Services/UsageQuota/UsageQuotaModelsDev.swift`: The live api.json is a flat provider-key map; a `{"providers": …}` wrapper is tolerated the same way CodexBar does.

### models.dev pricing cache

- `GitMenuBar/Services/UsageQuota/UsageQuotaModelsDev.swift`: Direct pricing sources must both be present and priceable; this rejects empty or partial responses before they replace a cache.

## Consequences

- Readers find the reason for a non-obvious line here, not beside the line.
- New rationale goes into an ADR; a workaround goes into an issue.
