# Plan 048: Flatten Settings panes to one native Form grouping surface

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 9b4e69a..HEAD -- GitMenuBar/Pages/Settings/SettingsPage.swift GitMenuBar/Components/Settings/SettingsFormPage.swift GitMenuBar/Components/Common/GitHubConnectionSection.swift GitMenuBar/Components/AI/AIProviderRow.swift GitMenuBar/Components/Projects/RecentPathRow.swift .interface-design/system.md plans/README.md`
> If any in-scope source/design file changed since this plan was written,
> compare the "Current state" excerpts against the live code before
> proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: plans/034-settings-form-surface-and-general-canary.md and plans/035-settings-form-migrate-panes-and-ia.md (both DONE)
- **Category**: direction
- **Planned at**: commit `9b4e69a`, 2026-08-04

## Execution profile

- **Recommended profile**: `implementer-fast`
- **Risk/lane**: `Low/Fast`
- **Parallelizable**: no — all changes are one visual contract across the Settings panes
- **Reviewer required**: no — no persistence, behavior, navigation, or new dependency changes; escalate if the Form package requires AppKit surgery
- **Rationale**: Small, deterministic SwiftUI-only visual cleanup using the existing grouped `Form`, existing Workbench tokens, and existing row components.
- **Escalate when**: the visual flattening requires changing `SettingsWindowController`, replacing the Settings package, changing pane identifiers, adding a new row abstraction, or touching settings state/persistence.

## Why this matters

The sibling `gugu` settings window uses one native `.formStyle(.grouped) Form` per tab. `Section` supplies the grouping, and the rows are plain `HStack`, `LabeledContent`, `Toggle`, `Picker`, or `VStack` content; settings panes do not add another rounded plate around those rows. GitMenuBar already has the Form migration, but it still inserts a redundant pane-title row inside the Form and adds custom row/card chrome around GitHub, AI providers, and recent projects. Flattening those surfaces makes the Settings window read as one native macOS preferences surface while preserving all existing behavior.

## Current state

### Reference pattern in `gugu`

- `GUGU/App/AppSettingsWindowController.swift:20-72` creates toolbar panes and sets a resizable minimum content size; it does not inject a page title into each pane body.
- `GUGU/UI/Settings/GeneralSettingsPaneView.swift:15-117` uses one `Form` with `.formStyle(.grouped)` and several `Section`s. Each section owns its header with plain `Text`; conditional feature groups remain sections.
- `GUGU/UI/Settings/ShortcutsSettingsPaneView.swift:6-23` keeps shortcuts and reset as Form sections with no custom card wrapper.
- `GUGU/UI/Settings/PermissionsSettingsPaneView.swift:7-39` embeds `PermissionRow` directly in one section and uses a section footer for explanation.
- `GUGU/UI/Components/LabeledToggleRow.swift:7-16` and `LabeledPickerRow.swift:8-21` are plain rows: label, spacer, native control. They do not draw a background, border, or rounded container.
- `GUGU/UI/Settings/ShelfSettingsPaneView.swift:85-115` renders the folder list directly inside a section; nested `VStack`/`HStack` layout is used for content, not another card.

### GitMenuBar code to change

- `GitMenuBar/Components/Settings/SettingsFormPage.swift:4-21` stores a generic `header` and inserts it as a direct child of the grouped `Form` before the native sections. Each pane therefore has a second title row in addition to the Settings toolbar tab.
- `GitMenuBar/Pages/Settings/SettingsPage.swift:15-17,97-99,243-245,275-277` passes the pane title (`General`, `Git`, `AI`, `Shortcuts`) as that extra Form child. The actual groups already have their own `Section` headers.
- `GitMenuBar/Components/Common/GitHubConnectionSection.swift:25,81,107,116-125` applies `githubConnectionCardChrome`, which draws a rounded border around content already hosted in a native Form section.
- `GitMenuBar/Components/AI/AIProviderRow.swift:45-48` applies a permanent gray background and rounded corner to each provider row inside the AI Form section. The small `Default` chip is a state indicator and may remain; the provider row plate must not.
- `GitMenuBar/Components/Projects/RecentPathRow.swift:23-25` applies the global `workbenchRow` style, which adds a rounded padded row treatment. In a native Form section, the Form should own the row grouping; this call site should use a plain button treatment while preserving the hit area and action.

### Existing design constraints

- `.interface-design/system.md:238-247` requires one grouped Form per pane, native Sections, one vertical scroll owner, and hybrid custom subviews only when they live inside a Section. It explicitly disallows new nested `workbenchPanelSurface` plates inside Settings.
- `docs/adr/0001-workbench-depth-and-token-naming.md` defines GitMenuBar as a dense macOS workbench, not a shadowed card dashboard; section/list card chrome is not the default depth language.
- `docs/adr/0002-window-shell-material-and-titlebar-chrome.md` makes the window-level Settings material the shell. Do not add another surface layer or change `WorkbenchWindowChrome` in this plan.
- Keep `SettingsFormSectionHeader` for the existing GitMenuBar Section-header anatomy and Workbench tokens. This plan removes the redundant page header and nested content plates; it does not introduce a second header system or copy `gugu` source.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Source search | `rg -n 'SettingsFormPage|githubConnectionCardChrome|workbenchRow' GitMenuBar/Pages/Settings GitMenuBar/Components/Settings GitMenuBar/Components/Common/GitHubConnectionSection.swift GitMenuBar/Components/AI/AIProviderRow.swift GitMenuBar/Components/Projects/RecentPathRow.swift` | only the intended remaining definitions/call sites are shown at each step |
| Preview coverage | `make check-preview` | exit 0; all changed UI files have preview coverage |
| Scoped validation | `make agent-check` | changed Swift lint passes and Debug build succeeds |
| Guidance validation | `make guidance-check` | exit 0; plan metadata and Markdown links are valid |
| Merge gate | `make lint && make test` | both commands exit 0 |

## Suggested executor toolkit

- Use `global:apple-design` plus `.agents/overlays/apple-design.md` for the
  native macOS surface and material constraints.
- Use `global:macos-app-engineering` plus
  `.agents/overlays/macos-app-engineering.md` for Settings window ownership;
  do not change ownership in this plan.
- Use `global:swift-conventions` for Swift formatting/lint conventions.
- Use `global:swiftui-accessibility-audit` if changing the recent-project
  button style; the visible label, help text, and row hit target must remain.

## Scope

**In scope** (the only source files to modify):

- `GitMenuBar/Components/Settings/SettingsFormPage.swift`
- `GitMenuBar/Pages/Settings/SettingsPage.swift`
- `GitMenuBar/Components/Common/GitHubConnectionSection.swift`
- `GitMenuBar/Components/AI/AIProviderRow.swift`
- `GitMenuBar/Components/Projects/RecentPathRow.swift`

Plan metadata files:

- `plans/048-settings-form-flatten-cardless.md`
- `plans/README.md`

**Out of scope** (do not touch):

- `GitMenuBar/App/AppSettingsWindowController.swift` — keep toolbar panes,
  identifiers, window shell, and 560×440 minimum size.
- `GitMenuBar/Components/Settings/SettingsFormSectionHeader.swift` and
  `SettingsFormLayoutPolicy.swift` — reuse the existing header/token contract;
  do not create or replace it in this slice.
- `GitMenuBar/Components/Common/WorkbenchButtonStyles.swift` — `workbenchRow`
  remains valid for non-Settings surfaces; change only the Settings call site.
- `GitMenuBar/Components/AI/AIProviderEditorSheet.swift` — editors remain
  sheets, as required by the Form contract.
- Settings state, Keychain behavior, GitHub authentication, repository
  selection, quota refresh, pane identifiers, localization, and tests.
- Settings search, sidebar navigation, `NavigationSplitView`, a new design
  system, or a full migration away from `sindresorhus/Settings`.

## Git workflow

- Branch: `advisor/048-settings-form-flatten-cardless` (or the repository's
  current branch convention if the operator already supplied an isolated
  implementation branch).
- Keep the implementation to one logical commit if committing is requested;
  use the repository's Conventional Commit style, e.g.
  `refactor(ui): flatten settings form surfaces`.
- Do not push or open a PR unless the operator explicitly instructs it.

## Steps

### Step 1: Remove the duplicate pane-title row

Change `SettingsFormPage` from a `Header, Content` generic to a content-only
wrapper. Its body must still contain exactly one `Form` with:

```swift
Form {
    content
}
.formStyle(.grouped)
.scrollContentBackground(.hidden)
```

Retain the existing `SettingsFormLayoutPolicy` sizing and
`workbenchScrollbarStyle()` unless the live code has drifted and the executor
can prove they are no longer needed. Do not add a second `ScrollView`.

Update all four panes and the `SettingsFormPage` previews in
`GitMenuBar/Pages/Settings/SettingsPage.swift` and
`GitMenuBar/Components/Settings/SettingsFormPage.swift` so they pass only
their native `Section`s. Keep the existing Section headers such as `App
Behavior`, `Commit`, and `Usage Quotas`; the toolbar already identifies the
selected pane.

**Verify**: `rg -n 'private let header|self\.header|SettingsFormPage.*header' GitMenuBar/Components/Settings GitMenuBar/Pages/Settings` → no matches. `rg -n 'SettingsFormPage' GitMenuBar/Pages/Settings/SettingsPage.swift GitMenuBar/Components/Settings/SettingsFormPage.swift` → the four pane call sites and previews remain.

### Step 2: Remove nested card chrome from Form content

Make the following minimal visual-only edits:

1. In `GitHubConnectionSection.swift`, remove the
   `colorSchemeContrast` environment dependency, the
   `githubConnectionCardChrome` modifier calls, the private card modifier, and
   its private View extension. Preserve all authenticated, authenticating,
   disconnected, error, Connect, Cancel, and Disconnect behavior. Keep only
   the spacing needed to make the device-code and progress states readable;
   do not replace the removed border with another background or plate.
2. In `AIProviderRow.swift`, remove the permanent gray background and
   `.cornerRadius(6)` from the provider row. Keep the provider name, provider
   type/model detail, Default state indicator, Edit/Delete actions, existing
   button styles, and previews. The `Default` chip is a semantic state marker,
   not a group container, so it may retain its small local tint/radius.
3. In `RecentPathRow.swift`, replace `.workbenchRow()` with the smallest plain
   button treatment that preserves the full row hit target and keyboard/VoiceOver
   label. A valid target is `.buttonStyle(.plain)` plus a rectangular
   `contentShape`; do not add a rounded background, border, shadow, or cursor
   abstraction here. Keep the existing path truncation and help text.

Do not modify the shared `workbenchRow` style because it remains correct for
branch/project/overlay rows outside the native settings Form.

**Verify**:

- `rg -n 'githubConnectionCardChrome|colorSchemeContrast|RoundedRectangle|strokeBorder' GitMenuBar/Components/Common/GitHubConnectionSection.swift` → no matches.
- `rg -n 'background\(Color\.gray|cornerRadius\(6' GitMenuBar/Components/AI/AIProviderRow.swift` → no matches; the semantic `Default` chip may still contain its own small status styling.
- `rg -n 'workbenchRow' GitMenuBar/Components/Projects/RecentPathRow.swift` → no matches.
- `make check-preview` → exit 0.

### Step 3: Validate the visual contract and regression surface

Run `make agent-check`, `make guidance-check`, then `make lint && make test`.
Use Xcode Previews or a Debug app run to inspect every toolbar pane at the
minimum window width:

- General: toolbar tab is the only pane-level title; App Behavior, Appearance,
  and App are the visible grouped sections.
- Git: Commit, Repository Path, Recent Projects, GitHub, and Danger Zone are
  separate native groups; GitHub has no inner outline.
- AI: provider rows, Companion CLI, and Usage Quotas sit directly in their
  Sections; providers have no gray rounded row plate.
- Shortcuts: recorder rows and reset action remain in the grouped Form with no
  custom panel.

Check both light/dark appearance and Reduce Transparency. The window-level
material may remain visible behind the Form, and controls must remain legible.
Confirm no action, binding, alert, sheet, Keychain access, or pane navigation
changed.

**Verify**: all commands exit 0; the manual pass shows no duplicate pane title,
no card/plate inside a Form group, one vertical scroll owner per pane, and no
clipped controls at 560pt content width.

## Test plan

- No new unit tests are required: this plan changes only SwiftUI composition
  and visual modifiers; it introduces no new state or pure logic.
- Existing `#Preview`s in every changed UI file are the structural test seam.
- `make check-preview` verifies preview coverage, `make agent-check` verifies
  changed Swift plus a Debug build, and `make lint && make test` is the final
  repository gate.
- Manual regression must exercise Connect/Disconnect, the GitHub device flow,
  Add/Edit/Delete AI provider, recent-project selection, and keyboard shortcut
  recording/reset once, because those controls move visually even though their
  behavior must remain unchanged.

## Done criteria

- [ ] Each Settings pane has exactly one `.formStyle(.grouped)` Form and no
      extra pane-title row inside the Form.
- [ ] `GitHubConnectionSection` has no custom card border or replacement plate.
- [ ] `AIProviderRowView` has no permanent row background/rounded container;
      the semantic Default marker may remain.
- [ ] `RecentPathRowView` no longer uses `workbenchRow` inside Settings.
- [ ] No source file outside the in-scope list is modified.
- [ ] `make check-preview`, `make agent-check`, `make guidance-check`,
      `make lint`, and `make test` exit 0.
- [ ] Manual inspection confirms no visible card-inside-card composition at
      560pt content width in General, Git, AI, and Shortcuts.
- [ ] `plans/README.md` status row for Plan 048 is present and remains TODO
      until implementation is complete.

## STOP conditions

Stop and report back instead of improvising if:

- `SettingsFormPage` or any pane has diverged from the current-state excerpts
  in a way that changes the scroll owner, pane composition, or state flow.
- Removing the page header breaks the Settings package's toolbar layout or
  leaves a pane without any visible Section content.
- Removing a nested plate makes a control inaccessible, clips the device-code
  flow, or loses a VoiceOver label/hit target; restore only the minimum
  structural spacing and report the mismatch.
- The visual fix requires changing `AppSettingsWindowController`, pane
  identifiers, `WorkbenchWindowChrome`, persistence, Keychain code, or an
  out-of-scope shared button style.
- `make agent-check`, `make check-preview`, or the final lint/test gate fails
  twice after a reasonable scoped correction.

## Maintenance notes

- The grouped Form is the only Settings grouping surface. Future complex
  settings content should be embedded directly in a native `Section` and
  should not add `workbenchPanelSurface`, permanent rounded row backgrounds,
  or card borders unless a new design decision explicitly permits it.
- Small semantic indicators such as the AI `Default` chip and native input
  outlines are not group containers; keep them only when they communicate
  state or input affordance.
- If a future Settings sidebar/search project changes pane navigation, reuse
  the pane bodies and preserve this no-nested-plates contract; do not put the
  old page-title row back into the Form.
- Reviewers should inspect the actual Settings window at minimum width and in
  Reduce Transparency, not only the source diff.
