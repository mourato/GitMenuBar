# Plan 032: Add window-level material shell for main panel and Settings

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 7ade5a9..HEAD -- GitMenuBar/App/StatusBarController.swift GitMenuBar/App/AppSettingsWindowController.swift GitMenuBar/Components/Common/WorkbenchPanelSurface.swift GitMenuBar/Components/Common/GitHubConnectionSection.swift GitMenuBar/Components/Common/MainMenuHeaderView.swift .interface-design/system.md docs/adr/0002-window-shell-material-and-titlebar-chrome.md plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/031-header-titlebar-and-project-row-options.md (titlebar alignment should land first)
- **Category**: direction
- **Planned at**: commit `7ade5a9`, 2026-07-25

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: `no`
- **Reviewer required**: `yes` — AppKit vibrancy, Reduce Transparency, Settings (`Settings` package) interaction
- **Rationale**: Window chrome + accessibility appearance edge cases; not Low/Fast.
- **Escalate when**: vibrancy breaks hosting, auto-hide, or requires forking the Settings package.

## Why this matters

The main window is a transparent-titlebar `NSWindow` without a true glass shell; nested plates (formerly the header) read as flat slabs. Product direction matches modern macOS material shells (e.g. Mimir): **window-level** vibrancy/material behind content, solid fallbacks when Reduce Transparency is on, and no double-frost from large nested `workbenchPanelSurface` on the main column. Settings must match in this wave.

## Current state

Main window appearance is titlebar-only; no content vibrancy:

```332:338:GitMenuBar/App/StatusBarController.swift
    private func configureMainWindowAppearance(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
    }
```

Shared material helper for nested surfaces:

```9:35:GitMenuBar/Components/Common/WorkbenchPanelSurface.swift
private struct WorkbenchPanelSurfaceModifier: ViewModifier {
    // Reduce Transparency → controlBackgroundColor
    // else thin/regular/thick Material
}
```

Settings uses `SettingsWindowController` (`AppSettingsWindowController`) with sizing + appearance mode only — no shell material. `GitHubConnectionSection` applies `.workbenchPanelSurface(material: .regular)` in Settings.

Locked design (`.interface-design/system.md` Depth strategy + ADR 0002):

- Window shell on **main + Settings**.
- Soften/avoid large nested plates on the main column; **keep** materials on popovers/sheets.
- Soften Settings `GitHubConnectionSection` plates so they do not double-frost the new shell (not a full Settings redesign).
- Respect Reduce Transparency / Increase Contrast.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift | `git diff --stat 7ade5a9..HEAD -- GitMenuBar/App/StatusBarController.swift GitMenuBar/App/AppSettingsWindowController.swift GitMenuBar/Components/Common/GitHubConnectionSection.swift` | understood |
| Incremental | `make agent-check` | exit 0 |
| Full gate | `make lint && make test` | exit 0 |
| Nested plate audit | `rg -n 'workbenchPanelSurface' GitMenuBar/` | popovers/sheets/confirmations OK; no new main-column plates |

## Suggested executor toolkit

- `macos-app-engineering`, `apple-design`, `accessibility-audit`
- Prefer system materials / `NSVisualEffectView` patterns over custom blur

## Scope

**In scope**

- `StatusBarController.swift` — configure main window content/background for material shell (isOpaque, backgroundColor clear, visual effect hosting as appropriate); keep titlebar behavior from Plan 031
- `AppSettingsWindowController.swift` — apply matching shell treatment to the Settings window without breaking pane toolbar
- Shared helper OK if small (e.g. `WorkbenchWindowChrome.swift` under `GitMenuBar/App/` or `Components/Common/`) — must include Reduce Transparency behavior
- `GitHubConnectionSection.swift` — soften/remove heavy `workbenchPanelSurface` stacking on the Settings shell (borders/tints via `WorkbenchPalette` OK)
- Ensure main-column views do not reintroduce a header plate
- Previews only if a new SwiftUI surface is introduced

**Out of scope**

- Command palette scrim (Plan 030)
- Header control relocation (Plan 031) except fixing regressions caused by vibrancy
- Quota card redesign (Plan 033)
- Restyling all Settings controls / Plan 029 button kit
- Changing popover/sheet materials (keep elevated)
- Status item appearance

## Git workflow

- Branch: `feat/032-window-material-shell`
- Commit example: `feat(ui): add material window shell for main panel and settings`
- Do NOT push unless asked

## Steps

### Step 1: Main window shell

Implement window-level material/vibrancy behind SwiftUI content:

- Content should read as translucent against the desktop / wallpaper when transparency is allowed.
- When `accessibilityReduceTransparency` (or AppKit equivalent preference) is effective, use solid `windowBackgroundColor` / `controlBackgroundColor`.
- Do not break `NSHostingController`, frame autosave, or auto-hide-on-resign.

**Verify**: `make agent-check` → exit 0

### Step 2: Settings window shell

Apply the same shell philosophy to `AppSettingsWindowController`’s window. If the `Settings` package fights custom `contentView` replacement, use the narrowest supported approach (background visual effect behind panes, appearance proxies). If the package makes a true shell impossible without forking, **STOP** and report — do not vendor-fork Settings.

**Verify**: `make agent-check` → exit 0

### Step 3: Soften Settings GitHub plates

Adjust `GitHubConnectionSection` so cards are not thick material slabs on top of the new shell (e.g. clear/thin backgrounds + `WorkbenchPalette` borders, or lighter weight). Keep hierarchy readable in light and dark.

**Verify**: `rg -n 'workbenchPanelSurface' GitMenuBar/Components/Common/GitHubConnectionSection.swift` → reduced/removed or justified thin usage documented in commit body

### Step 4: Regression pass

- Main panel: titlebar controls from 031 still aligned; palette scrim from 030 still full-bleed; popovers still material-elevated.
- Reduce Transparency ON/OFF; Increase Contrast spot-check.
- Light and dark appearance modes.

**Verify**: `make lint && make test` → exit 0

## Test plan

- No credential/quota logic changes — no new usage-quota tests.
- Prefer a small helper unit test only if you extract pure “resolved fill style” logic; otherwise manual a11y matrix is the acceptance bar.

## Done criteria

- [ ] Main window shows material shell (manual) with solid Reduce Transparency fallback
- [ ] Settings window matches shell intent (manual)
- [ ] `GitHubConnectionSection` no longer double-frosts heavily
- [ ] Popovers/sheets still use materials
- [ ] `make lint && make test` exit 0
- [ ] `plans/README.md` status row for 032 updated

## STOP conditions

- Settings package cannot accept a shell without forking — stop and report; ship main-only only after operator approval (contradicts locked 15B unless operator amends).
- Vibrancy breaks Plan 031 titlebar hosting or Plan 030 scrim — stop rather than ripping those plans out.
- Drift in Current state excerpts.

## Maintenance notes

- Reviewers: watch performance (continuous blur) and menu-bar panel opacity on varied wallpapers.
- Future surfaces should prefer shell + tint over new large `workbenchPanelSurface` plates on the main column.
- Plan 033 quota cards sit on this shell — keep cards visually quiet (no drop shadows).
