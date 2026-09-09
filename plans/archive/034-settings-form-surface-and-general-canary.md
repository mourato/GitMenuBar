# Plan 034: Establish Settings Form surface and migrate General canary

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat b558d22..HEAD -- GitMenuBar/App/AppSettingsWindowController.swift GitMenuBar/Pages/Settings/SettingsPage.swift GitMenuBar/Components/Common/SettingsSection.swift .interface-design/system.md plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/032-window-material-shell-main-and-settings.md (DONE — window shell must remain)
- **Category**: direction
- **Planned at**: commit `b558d22`, 2026-07-25

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: `no` — shared Form contract + canary pane + window geometry
- **Reviewer required**: `yes` — becomes the shared Settings Form owner; shell interaction is easy to get wrong
- **Rationale**: New public UI primitives plus Settings package / vibrancy edge cases; not Low/Fast.
- **Escalate when**: Form background cannot show through the shell without AppKit introspection, or the Settings package prevents `.formStyle(.grouped)` from filling the pane.

## Why this matters

Settings panes today are hand-rolled `ScrollView` + `VStack` + `HStack` label/control rows with manual `Divider`s. That fights the Plan 032 material shell, reads unlike native macOS preferences, and makes later IA moves harder. This plan ships the reusable grouped-`Form` surface and proves it on **General** only. Plan 035 migrates the remaining panes and applies the destination map.

## Current state

Toolbar Settings window (`sindresorhus/Settings`), four panes, tall/narrow geometry:

```5:16:GitMenuBar/App/AppSettingsWindowController.swift
private extension Settings.PaneIdentifier {
    static let gitMenuBarGeneral = Self("gitmenubar.general")
    static let gitMenuBarGit = Self("gitmenubar.git")
    static let gitMenuBarQuotas = Self("gitmenubar.quotas")
    static let gitMenuBarShortcuts = Self("gitmenubar.shortcuts")
}
// ...
    private enum Constants {
        static let minimumContentSize = NSSize(width: 420, height: 700)
    }
```

General pane is ScrollView + manual rows (not Form):

```14:67:GitMenuBar/Pages/Settings/SettingsPage.swift
    var body: some View {
        ScrollView {
            VStack(spacing: WorkbenchMetrics.groupSpacing) {
                // Open at Login, Auto-hide, Mouse monitor toggles…
                Divider()
                appearancePicker
            }
            .padding(.horizontal, WorkbenchMetrics.windowPadding)
            .padding(.vertical, WorkbenchMetrics.groupSpacing)
        }
        .frame(minWidth: 420, minHeight: 700)
        .preferredColorScheme(preferredColorScheme)
    }
```

Custom section chrome (used by GitHub and others; **do not delete in this plan**):

```3:21:GitMenuBar/Components/Common/SettingsSection.swift
struct SettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    // SF Symbol + sectionLabel header over content
}
```

Shell already installed on Settings:

```128:131:GitMenuBar/App/AppSettingsWindowController.swift
    private func configureWindowShell() {
        guard let contentView = windowController.window?.contentView else { return }
        WorkbenchWindowChrome.installShell(in: contentView)
    }
```

Xcode uses `PBXFileSystemSynchronizedRootGroup` for `GitMenuBar/` — new Swift files under that tree compile without `pbxproj` edits.

### Locked design (must honor)

From `.interface-design/system.md` → **Settings Form surface**:

- One `.formStyle(.grouped)` `Form` per pane via `SettingsFormPage`
- Native `Section`s + `SettingsFormSectionHeader` (title + optional SF Symbol)
- Exactly one vertical scroll owner (the Form)
- `.scrollContentBackground(.hidden)` so the window material shows through
- No new nested `workbenchPanelSurface` in Settings panes
- Scalars use visible native labels (`Toggle("…")`, `Picker("…")`, not empty-title + side `Text`)
- Keep `sindresorhus/Settings` toolbar; primitives must be **chrome-agnostic**
- Geometry target: min width **~520–600**; drop forced tall `420×700`
- **Ideas only** from Vozinha — recreate with Workbench tokens; do not copy Vozinha source
- Quit / Wipe / Quotas→AI moves belong to **035**, not this plan

If the **Settings Form surface** section is missing from `.interface-design/system.md` at execution time, treat the bullets above as authoritative and STOP only if they conflict with a newer committed design doc.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift | `git diff --stat b558d22..HEAD -- GitMenuBar/App/AppSettingsWindowController.swift GitMenuBar/Pages/Settings/SettingsPage.swift GitMenuBar/Components/Common/SettingsSection.swift .interface-design/system.md` | understood |
| Incremental | `make agent-check` | exit 0 |
| Guidance | `make guidance-check` | exit 0 (after plan/index edits) |
| Full gate | `make lint && make test` | exit 0 |
| No nested plates in new Form files | `rg -n 'workbenchPanelSurface' GitMenuBar/Components/Settings/ GitMenuBar/Pages/Settings/` | no matches in new Form primitives / General |

## Suggested executor toolkit

- `macos-app-engineering`, `apple-design`, `swift-conventions`, `accessibility-audit`
- Every new `View` file needs `#Preview` (AGENTS.md)
- Optional visual check: open Settings → General on material shell; Reduce Transparency on/off

## Scope

**In scope**

- Create under `GitMenuBar/Components/Settings/` (new folder):
  - `SettingsFormPage.swift`
  - `SettingsFormSectionHeader.swift`
  - `SettingsFormLayoutPolicy.swift` (width/gutter helper; keep tiny)
- `GitMenuBar/Pages/Settings/SettingsPage.swift` — migrate **`GeneralSettingsPaneView` only** to `SettingsFormPage`
- `GitMenuBar/App/AppSettingsWindowController.swift` — update `Constants.minimumContentSize` to the new geometry (~520–600 width; shorter min height, e.g. ~420–480 — pick one pair and use it consistently)
- `#Preview`s for new primitives and updated General pane
- Ensure `.interface-design/system.md` **Settings Form surface** section remains accurate if this plan lands the first commit that includes it

**Out of scope**

- Migrating Git / Quotas / Shortcuts panes to Form (Plan 035)
- Moving Quit, Wipe, or Quotas→AI (Plan 035)
- Deleting `SettingsSection.swift` (still used by GitHub until 035)
- Settings search, sidebar chrome, expandable/drill-down rows
- Retiring or forking `sindresorhus/Settings`
- Copying code from the sibling `vozinha` project
- Main-panel UI, quotas cards on the main window

## Git workflow

- Branch: `feat/034-settings-form-surface`
- Commit example: `feat(ui): add Settings Form surface and migrate General pane`
- Do NOT push unless asked

## Steps

### Step 1: Add layout policy + section header + form page

Create the three files under `GitMenuBar/Components/Settings/`.

**`SettingsFormLayoutPolicy`**

- `defaultOuterGutter` — reuse `WorkbenchMetrics.windowPadding` (or document a Settings-specific alias that equals it)
- `contentWidth(availableWidth:outerGutter:)` → `max(0, availableWidth - 2 * gutter)` with **no** maximum content width

**`SettingsFormSectionHeader`**

- Parameters: `title: String`, optional `icon: String?` (SF Symbol), optional trailing `Accessory`
- Layout: `HStack` — icon (accent or secondary; hide from accessibility) + title + `Spacer` + accessory
- Must work as a `Section` header

**`SettingsFormPage`**

- Generic over `Header` + `Content`
- Body shape (behavioral contract — match intent, not foreign source):

```swift
GeometryReader { geometry in
    Form {
        header
        content
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .frame(
        minWidth: SettingsFormLayoutPolicy.contentWidth(availableWidth: geometry.size.width),
        maxWidth: .infinity,
        maxHeight: .infinity,
        alignment: .topLeading
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
}
```

- Previews at ~560 and ~600 width showing a sample `Section` with `Toggle` / `Picker`
- **No** outer `ScrollView` wrapping the Form

**Verify**: `make agent-check` → exit 0

### Step 2: Migrate `GeneralSettingsPaneView`

Replace the ScrollView/VStack body with `SettingsFormPage`:

1. Optional page header via `SettingsFormSectionHeader(title:icon:)` (e.g. “General” / `gearshape`) — keep quiet; do not add marketing copy.
2. `Section` for app behavior: Open at Login, Auto-hide, Mouse-monitor — use **labeled** `Toggle("…", isOn:)` (or `Toggle { LabeledContent }` if a subtitle is needed). Preserve existing `LoginItemManager` binding behavior and accessibility labels.
3. `Section` for appearance: segmented `Picker` with a visible label; header can use `SettingsFormSectionHeader(title: "Appearance", icon: "paintbrush")` or equivalent.
4. Remove the pane’s `.frame(minWidth: 420, minHeight: 700)` — sizing comes from the window + Form.
5. Keep `.preferredColorScheme(preferredColorScheme)` and `SettingsAppearance` helper as today.
6. Update `#Preview("General Settings Pane")` accordingly.

Do **not** add Quit here (035).

**Verify**: `make agent-check` → exit 0

### Step 3: Update Settings window minimum size

In `AppSettingsWindowController.Constants`, change `minimumContentSize` from `420×700` to the locked band (recommend `NSSize(width: 560, height: 440)` unless live toolbar chrome requires a slightly taller min — stay within ~520–600 × content-driven height).

Call `configureWindowSizing()` still sets `contentMinSize`; keep `.resizable`.

**Verify**: `rg -n '420, height: 700|minWidth: 420, minHeight: 700' GitMenuBar/App/AppSettingsWindowController.swift GitMenuBar/Pages/Settings/SettingsPage.swift` → General and window Constants no longer use 420×700; other panes may still until 035

### Step 4: Full gate + index

**Verify**: `make guidance-check && make lint && make test` → exit 0  
Update `plans/README.md` row for 034 → DONE with commit SHA when committing.

## Test plan

- No mandatory new unit tests if behavior is pure SwiftUI composition; prefer previews.
- Manual:
  - Open Settings → General: grouped Form, material visible behind sections
  - Toggle login / auto-hide / mouse monitor; change appearance — preferences stick
  - Reduce Transparency: Form remains legible on solid shell
  - Resize window: Form uses full width; no centered “island”
  - Switch to Git/Quotas/Shortcuts: still open (legacy layout OK)

## Done criteria

- [ ] `SettingsFormPage`, `SettingsFormSectionHeader`, `SettingsFormLayoutPolicy` exist under `GitMenuBar/Components/Settings/` with `#Preview`s
- [ ] `GeneralSettingsPaneView` uses `SettingsFormPage` + native `Section`s; no outer `ScrollView`
- [ ] Form uses `.scrollContentBackground(.hidden)`; no new `workbenchPanelSurface` in Settings Form files
- [ ] Window min size updated off `420×700`
- [ ] Git / Quotas / Shortcuts still compile and open (unchanged structure OK)
- [ ] `make lint && make test` exit 0
- [ ] `plans/README.md` status row for 034 updated

## STOP conditions

- Achieving hidden Form background / shell bleed requires forking `sindresorhus/Settings` or AppKit view surgery beyond `WorkbenchWindowChrome.installShell` — stop and report.
- Drift in Current state excerpts for General or window controller.
- Temptation to migrate Git/AI/Shortcuts or move Quit/Wipe in this plan — defer to 035.
- Copying files from `../vozinha` — stop; recreate locally.

## Maintenance notes

- Reviewers: General must not reintroduce nested plates or a second scroll owner.
- Plan 035 depends on these three symbols existing with this contract.
- Keep primitives free of `Settings.Pane` / toolbar assumptions so chrome can change later.
