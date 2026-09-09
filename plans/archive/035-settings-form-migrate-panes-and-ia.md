# Plan 035: Migrate Settings panes to Form and apply destination map

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat b558d22..HEAD -- GitMenuBar/App/AppSettingsWindowController.swift GitMenuBar/Pages/Settings/SettingsPage.swift GitMenuBar/Components/Settings/ GitMenuBar/Components/Common/SettingsSection.swift GitMenuBar/Components/Common/GitHubConnectionSection.swift GitMenuBar/Components/AI/AISettingsSection.swift GitMenuBar/Components/UsageQuota/UsageQuotaSettingsSection.swift GitMenuBar/Components/Projects/RepositoryPathSection.swift GitMenuBar/Components/Projects/RecentProjectsSection.swift GitMenuBar/Components/Common/KeyboardShortcutsSection.swift .interface-design/system.md plans/034-settings-form-surface-and-general-canary.md plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.
> **Prerequisite**: Plan 034 must be DONE — `SettingsFormPage` / `SettingsFormSectionHeader` / `SettingsFormLayoutPolicy` must exist and General must already use the Form surface.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/034-settings-form-surface-and-general-canary.md
- **Category**: direction
- **Planned at**: commit `b558d22`, 2026-07-25

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: `no` — pane ID rename, content moves, and Form migration share one window controller
- **Reviewer required**: `yes` — IA change (Quotas→AI), destructive Wipe move, hybrid Form embeds
- **Rationale**: Multi-pane migration + preference chrome identity change; medium ambiguity on hybrid sections.
- **Escalate when**: AI provider editor / GitHub auth flows break under Form embedding, or PaneIdentifier rename requires migration of persisted UI state you cannot find.

## Why this matters

After 034, only General uses the native Form surface. Git still piles repo, GitHub, and AI into one ScrollView; Quotas is a thin peer pane; Shortcuts hosts Wipe and Quit. This plan finishes the Form migration and applies the locked destination map so each toolbar pane has a clear job.

## Current state (as of plan authoring; re-check after 034)

Four toolbar panes including Quotas; Wipe/Quit on Shortcuts footer:

```5:16:GitMenuBar/App/AppSettingsWindowController.swift
    static let gitMenuBarGeneral = Self("gitmenubar.general")
    static let gitMenuBarGit = Self("gitmenubar.git")
    static let gitMenuBarQuotas = Self("gitmenubar.quotas")
    static let gitMenuBarShortcuts = Self("gitmenubar.shortcuts")
// Constants.minimumContentSize may already be updated by 034
```

```58:87:GitMenuBar/App/AppSettingsWindowController.swift
        let quotasPane = Settings.Pane(
            identifier: .gitMenuBarQuotas,
            title: "Quotas",
            // …
            contentView: { QuotasSettingsPaneView().environmentObject(usageQuotaStore) }
        )
        // panes: [general, git, quotas, shortcuts]
```

```239:269:GitMenuBar/Pages/Settings/SettingsPage.swift
        // Shortcuts: ScrollView { KeyboardShortcutsSection } + footer HStack Wipe | Quit
```

Git pane stacks commit toggle, `RepositoryPathSection`, `RecentProjectsSection`, `GitHubConnectionSection`, `AISettingsSectionView` with `Divider`s inside a ScrollView (`GitSettingsPaneView` in the same file).

`GitHubConnectionSection` still wraps content in custom `SettingsSection` and may use `.githubConnectionCardChrome` / soft plate — Form migration must **not** reintroduce heavy nested `workbenchPanelSurface` (Plan 032 + system.md).

### Locked destination map

| Pane | Owns after this plan |
|------|----------------------|
| **General** | Login, auto-hide, mouse-monitor, appearance, **Quit** |
| **Git** | Commit-field hide, repo path, recents, GitHub, **Wipe** (Danger zone `Section`) |
| **AI** | Providers + usage quotas (**replaces** Quotas pane) |
| **Shortcuts** | Keyboard shortcuts **only** |

Hybrid rule: scalars = native Form controls; repo path / recents / GitHub / AI provider list = custom subviews **inside** `Section`; editors stay sheets.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift | (see header) | understood; 034 symbols present |
| 034 prerequisite | `rg -n 'struct SettingsFormPage' GitMenuBar/Components/Settings/` | match |
| Incremental | `make agent-check` | exit 0 |
| Full gate | `make lint && make test` | exit 0 |
| No Quotas pane ID | `rg -n 'gitMenuBarQuotas|QuotasSettingsPaneView|"Quotas"' GitMenuBar/` | no live pane wiring (rename/delete as specified) |
| No SettingsSection orphans | `rg -n 'SettingsSection\(' GitMenuBar/` | no call sites, or only justified temporary — prefer zero |
| Geometry leftovers | `rg -n 'minWidth: 420, minHeight: 700' GitMenuBar/` | no matches |

## Suggested executor toolkit

- `macos-app-engineering`, `apple-design`, `swift-conventions`, `accessibility-audit`, `ux-writing` (section titles)
- Preserve Wipe confirmation alerts; use Destructive button variant for Wipe (`role: .destructive`)

## Scope

**In scope**

- `AppSettingsWindowController.swift` — rename Quotas → **AI** pane (`gitmenubar.ai` or similar new `PaneIdentifier`); wire `AISettingsPaneView`; drop quotas identifier
- `SettingsPage.swift` (and/or split pane files if clearer):
  - Add Quit `Section` to General
  - Migrate `GitSettingsPaneView` to `SettingsFormPage`; move Wipe + alerts here; remove AI section from Git
  - New `AISettingsPaneView`: `AISettingsSectionView` + `UsageQuotaSettingsSection` in Form sections
  - Migrate Shortcuts to Form; remove Wipe/Quit footer and git/auth dependencies if unused
  - Delete `QuotasSettingsPaneView` after move
- Adapt section components for Form embedding:
  - `GitHubConnectionSection.swift` — stop depending on outer `SettingsSection` chrome if the Form `Section` header replaces it; keep auth behavior
  - `AISettingsSection.swift`, `UsageQuotaSettingsSection.swift`, `RepositoryPathSection.swift`, `RecentProjectsSection.swift`, `KeyboardShortcutsSection.swift` — remove redundant outer titles/Scroll assumptions so they sit cleanly in a `Section`
- Delete `SettingsSection.swift` when no call sites remain
- Strip remaining `420×700` frames from migrated panes
- Previews for each pane
- Update `.interface-design/system.md` only if destination map text drifts from reality

**Out of scope**

- Settings search, sidebar, expandable/drill-down kit
- Retiring `sindresorhus/Settings`
- Changing Wipe semantics / `gitManager.wipeRepository` behavior
- Main-window quota cards layout (already Plan 033)
- Copying Vozinha source
- New preferences beyond relocating existing controls

## Git workflow

- Branch: `feat/035-settings-form-migrate-panes`
- Commit example: `feat(ui): migrate Settings panes to Form and regroup AI`
- Do NOT push unless asked

## Steps

### Step 1: Confirm 034 primitives

Confirm `SettingsFormPage`, `SettingsFormSectionHeader`, and `SettingsFormLayoutPolicy` exist and General already uses them. If not, **STOP** and run/finish 034 first.

**Verify**: `rg -n 'struct SettingsFormPage|GeneralSettingsPaneView' GitMenuBar/Components/Settings/ GitMenuBar/Pages/Settings/SettingsPage.swift` → Form page exists; General references `SettingsFormPage`

### Step 2: Introduce AI pane identity; keep temporary Quotas content compiling

In `AppSettingsWindowController`:

1. Add `gitMenuBarAI = Self("gitmenubar.ai")` (exact string may vary; do not reuse `gitmenubar.quotas`).
2. Replace the Quotas `Settings.Pane` with an **AI** pane (title `"AI"`, SF Symbol e.g. `sparkles`), content placeholder OK until Step 4 — or point at a stub `AISettingsPaneView` that currently only hosts quotas to avoid a blank pane mid-migration.
3. Update `panes:` order to `[general, git, ai, shortcuts]`.
4. Remove `gitMenuBarQuotas` once nothing references it.

**Verify**: `make agent-check` → exit 0; app opens Settings with an AI toolbar item

### Step 3: Migrate Git pane + move Wipe

Rewrite `GitSettingsPaneView` to `SettingsFormPage`:

1. Section — commit message field preference (labeled Toggle + existing help caption as Section footer or secondary text).
2. Section — repository path: embed `RepositoryPathSection` (trim its own duplicate outer header if Form header covers it).
3. Section — recent projects: embed `RecentProjectsSection`.
4. Section — GitHub: embed adapted `GitHubConnectionSection` under `SettingsFormSectionHeader(title: "GitHub", icon: "globe")`.
5. Section — **Danger zone**: Wipe button (`role: .destructive` / Destructive variant), same enablement rules (`isAuthenticated` && non-empty `remoteUrl`), same confirmation + failure alerts moved from Shortcuts.
6. **Remove** `AISettingsSectionView` from Git.
7. No outer `ScrollView` / `Divider` stack; no new `workbenchPanelSurface`.

Pass `gitManager` / `githubAuthManager` as needed for Wipe.

**Verify**: `make agent-check` → exit 0

### Step 4: Build AI pane (providers + quotas)

Create/finish `AISettingsPaneView`:

```swift
SettingsFormPage { /* header AI / sparkles */ } content: {
  Section { AISettingsSectionView()… } header: { SettingsFormSectionHeader(title: "AI Commit Generation", icon: "sparkles") }
  Section { UsageQuotaSettingsSection()… } header: { SettingsFormSectionHeader(title: "Usage Quotas", icon: "gauge.with.dots.needle.33percent") }
}
```

- Preserve `environmentObject` wiring for `AIProviderStore`, `AICommitCoordinator`, `UsageQuotaStore`.
- Strip duplicate inner titles from those sections when the Form header already names them.
- Delete `QuotasSettingsPaneView`.
- Keep provider editor as a sheet.

**Verify**: `make agent-check` → exit 0

### Step 5: General Quit + Shortcuts cleanup

1. Add a General `Section` (e.g. “App”) with Quit button calling `NSApplication.shared.terminate(nil)` — Ghost/secondary styling OK; not Destructive.
2. Rewrite `ShortcutsSettingsPaneView` to `SettingsFormPage` hosting only `KeyboardShortcutsSection`.
3. Remove Wipe/Quit footer, wipe state, alerts, and `gitManager` / `githubAuthManager` parameters from Shortcuts if unused.
4. Update `AppSettingsWindowController` Shortcuts `contentView` initializer accordingly.

**Verify**: `make agent-check` → exit 0

### Step 6: Retire `SettingsSection` + geometry leftovers

1. `rg` for `SettingsSection(` — migrate remaining callers; delete `SettingsSection.swift` when unused.
2. Remove any remaining `minWidth: 420, minHeight: 700` in Settings.
3. Refresh `#Preview`s for Git, AI, Shortcuts, General (Quit visible).

**Verify**: `rg -n 'SettingsSection\(|minWidth: 420, minHeight: 700|QuotasSettingsPaneView|gitMenuBarQuotas' GitMenuBar/` → no matches  
**Verify**: `make lint && make test` → exit 0  
Update `plans/README.md` row for 035.

## Test plan

- Manual matrix:
  - General: existing toggles + Quit
  - Git: path browse, recents, GitHub connect/disconnect, Wipe confirm cancel/success path (destructive)
  - AI: provider list/add sheet, default provider/model, quota toggles + Refresh
  - Shortcuts: shortcut recording only; no Wipe/Quit
- Toolbar: four items General · Git · AI · Shortcuts; no Quotas
- Material shell still visible behind Forms; Reduce Transparency OK
- Accessibility: toggles/pickers have visible labels; Wipe announces as destructive

## Done criteria

- [ ] Destination map implemented (Quit→General, Wipe→Git Danger, Quotas content→AI pane, Shortcuts shortcuts-only)
- [ ] Git, AI, Shortcuts use `SettingsFormPage` with one scroll owner each
- [ ] No `QuotasSettingsPaneView` / `gitMenuBarQuotas`
- [ ] `SettingsSection` removed or zero call sites with file deleted
- [ ] No `420×700` Settings frames remain
- [ ] No new nested Settings `workbenchPanelSurface` plates
- [ ] `make lint && make test` exit 0
- [ ] `plans/README.md` status row for 035 updated

## STOP conditions

- Plan 034 primitives missing.
- GitHub device-flow or AI provider sheet breaks when embedded in Form and fix needs unrelated architecture — stop and report.
- Persisted Settings package state keyed on `gitmenubar.quotas` causes a crash on launch you cannot fix by identifier rename alone — stop and report.
- Drift that invalidates hybrid embedding assumptions for path/recents.

## Maintenance notes

- Reviewers: confirm Wipe enablement parity and that Quit is not styled destructive.
- Future search/sidebar plans should consume `SettingsFormPage` without rewriting pane bodies.
- PaneIdentifier `gitmenubar.ai` is the new stable ID — avoid renaming casually.
