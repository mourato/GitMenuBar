# Plan 096: Restructure the Quotas settings group into calm, self-explaining sections

> **Executor instructions**: Read this plan fully, then `AGENTS.md`,
> [project workflow facts](../docs/agents/project-workflow.md), and
> [DESIGN.md](../DESIGN.md) (Settings uses the native grouped `Form`; Workbench
> tokens only, no raw sizes or colors in views). Run every verification command
> and confirm its expected result before continuing. On any STOP condition,
> stop and report. Do not improvise. Bind the unit with `bind-unit` before
> editing and execute it through `ship`. Work in a dedicated worktree. Leave
> merge and push to the operator.
>
> **Drift check (run first)**:
> `git diff --stat 7e5ac97..HEAD -- GitMenuBar/Components/UsageQuota GitMenuBar/Services/UsageQuota GitMenuBar/Pages/Settings/SettingsPage.swift GitMenuBarTests/UsageQuotaPresentationPreferencesTests.swift GitMenuBarTests/QuotaProviderStatusTests.swift`
> Empty output expected. Any change in these paths: compare the excerpts below
> with the live files; a mismatch is a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (UI-only; no stored-preference format change)
- **Plan root**: `plans/`
- **Depends on**: none
- **Category**: direction (settings UX)
- **Planned at**: commit `7e5ac97`, 2026-11-12

## Execution profile

- **Recommended profile**: Standard
- **Risk/lane**: LOW
- **Executor**: `implementer` role, worker tier from `core/models.toml`
- **Parallelizable**: No (single coherent settings surface)
- **Reviewer required**: Yes (UI owner reviews diff and screenshots)
- **Rationale**: About seven files of SwiftUI layout plus two small preference
  and status helpers. All product decisions are settled below.
- **Escalate when**: inline provider reordering cannot work inside the grouped
  `Form` (see Step 5 fallback), or the live preview needs changes to
  `StatusBarController`.

## Why this matters

Today the Quotas group is one flat column: ten global rows (four segmented
controls in a row, with uneven widths) before the provider list. The labels
"Figures" and "Count" do not say what they change. The warning fields look
like static text, so a caption must say "Press Return to apply". The per-provider
metric chips suggest free multi-select, but the code silently keeps at most two
metrics and the order matters (first value on top in Text mode). "In strip" and
"Hidden" pills repeat the toggle. "Strip order" repeats the list in a sheet.

Result after this plan: four sections with one clear job each, a live preview
of the menu-bar strip, one segmented control instead of four, toggles for
binary choices, two explicit metric menus per provider, and inline reorder.
No stored preference changes format, so existing user settings keep working.

## Target layout (approved by the UI owner, English labels)

```
Quotas  (section header with icon)
  Show AI usage quotas                                   [switch]
  Preview          [live UsageQuotaMenuBarStrip]

Menu bar
  Show in menu bar                                       [switch]
    caption: When off, quotas appear only inside the menu.
  Style                               [ Text | Bars | Circular ]   (only segmented)
  Show                                          [ Remaining ▾ ]

Providers   (header caption: Drag to set menu bar order)
  ⋮ icon Claude Code                       [exception pill] [switch] ›
      (expanded)
      API key block (key providers only, unchanged)
      Menu bar shows                              [ Session ▾ ]
      Second metric                               [ None ▾ ]
  ...

Pace and warnings
  Show pace marker                                       [switch]
    caption: Marks where usage should be at this point in the period.
      Workdays per week   (indented, disabled when pace is off)  [ 5 ▾ ]
      Show workday ticks  (indented, disabled when pace is off)  [switch]
  Warn during session at                            [ 50, 80   ]  (bordered field)
    caption: Percent used, separated by commas.
  Warn during week at                               [ 50, 80   ]  (bordered field)
  footer: Updated 2 min ago · Refresh now                    (i) Privacy
```

When "Show AI usage quotas" is off, show only the first section (toggle,
without the preview) and hide the other three sections.

Settled decisions (do not reopen):

- Warning thresholds stay a free comma-separated list (existing
  `setSessionWarningThresholds(from:)` / `setWeeklyWarningThresholds(from:)`
  parsing is unchanged).
- All labels are English, exactly as written in this plan.
- The metric labels are "Menu bar shows" and "Second metric", never
  "Top"/"Bottom" (the position differs per style: stacked in Text and Bars,
  side by side in Circular).
- Pills show only exception states. "In strip" and "Hidden" no longer render.
- The long privacy text moves, verbatim, into a popover behind the (i) button.

## Current state

- `GitMenuBar/Components/UsageQuota/UsageQuotaSettingsSection.swift` — owns all
  rows of the group. Returns bare rows; `SettingsPage` wraps them in one
  `Section`. Excerpts:
  - `:20-31` `Picker("Status item", …menuBarVisibility…).pickerStyle(.segmented)`
  - `:34-46` `Picker("Figures", …meterStyle…).pickerStyle(.segmented)`
  - `:48-60` `Picker("Count", …valueStyle…).pickerStyle(.segmented)`
  - `:72-80` `Stepper("Workdays per week: \(preferences.workdaysPerWeek)", … in: 1 ... 7)`
  - `:82-94` `Picker("Workday ticks", …workdayTickAppearance…).pickerStyle(.segmented)`
  - `:96-107` two `TextField`s with `.onSubmit(commit…)` and the "Press Return to apply" caption
  - `:109-111` `ForEach(preferences.orderedProviderIDs) { QuotaProviderRowView(providerID:) }`
  - `:114-128` "Strip order" row + `.sheet { QuotaStripOrderSheetView() }`
  - `:130-140` privacy `Text(...)` caption; `:142-146` `Button("Refresh now")`
- `GitMenuBar/Pages/Settings/SettingsPage.swift:204-211` —
  `Section { UsageQuotaSettingsSection() } header: { SettingsFormSectionHeader(title: "Quotas", icon: "gauge.with.dots.needle.33percent") }`.
- `GitMenuBar/Components/UsageQuota/QuotaProviderRowView.swift:12-47` — header
  row: icon, name, `QuotaStatusPillView(status: currentStatus)`, `Toggle`,
  chevron button, then `QuotaProviderDetailView` when expanded.
- `GitMenuBar/Components/UsageQuota/QuotaProviderDetailView.swift:21-60` —
  "Menu bar" caption plus `metricChips`, which call
  `preferences.toggleMetric(metric, for: providerID)`.
- `GitMenuBar/Components/UsageQuota/QuotaStripOrderSheetView.swift` — sheet
  with `List { ForEach … .onMove { preferences.moveProvider(from:to:) } }` and
  per-row accessibility actions "Move <name> up/down" calling
  `preferences.moveProvider(providerID, by: ±1)` (`:35-64`). Reuse that
  accessibility pattern.
- `GitMenuBar/Components/UsageQuota/QuotaStatusPillView.swift:19-36` —
  `QuotaProviderStatus.title` ("Hidden", "Checking", "In strip", "No data",
  "Needs key", "Unavailable").
- `GitMenuBar/Components/UsageQuota/QuotaProviderStatus.swift:5-35` — pure
  `resolve(...)`; keep it unchanged (covered by `QuotaProviderStatusTests`).
- `GitMenuBar/Services/UsageQuota/UsageQuotaPresentationPreferences.swift`:
  - `:29-45` `ValueStyle` titles "Left"/"Used".
  - `:47-63` `MenuBarVisibility` `.always` / `.menuOnly`.
  - `:89-105` `WorkdayTickAppearance` `.subtle` / `.hidden`.
  - `:200-202` `selectedMetrics(for:)` defaults to `[.session, .weekly]`.
  - `:204-215` `setSelectedMetrics` dedupes and keeps at most 2.
  - `:217-227` `toggleMetric` (only caller: `QuotaProviderDetailView:34`;
    test: `UsageQuotaPresentationPreferencesTests.swift:85-92`).
- `GitMenuBar/Components/UsageQuota/UsageQuotaMenuView.swift:144-180` —
  `UsageQuotaMenuPresentation.groups(snapshots:preferences:)`;
  `:256-...` `UsageQuotaMenuBarStrip(groups:style:tint:)`, default tint
  `labelColor`. The status item builds it in
  `GitMenuBar/App/StatusBarController+UsageQuotaMenu.swift:6-37` and `:69-85`
  from `usageQuotaStore.visibleSnapshots`. Reuse both for the preview; read
  that file for the frame/size the strip is rendered at.
- Tokens: `WorkbenchMetrics.rowContentInset` for nested labels
  (DESIGN.md "nested disclosure labels use `WorkbenchMetrics.rowContentInset`").

## Commands you will need

| Purpose | Command | Expected on success |
| --- | --- | --- |
| Build | `make build` | exit 0 |
| Focused tests | `make test-focused TEST_FILTER='GitMenuBarTests/UsageQuotaPresentationPreferencesTests'` | all pass |
| Focused tests | `make test-focused TEST_FILTER='GitMenuBarTests/QuotaProviderStatusTests'` | all pass |
| Preview check | `make check-preview` | exit 0 |
| Lint | `make lint` | exit 0 |
| Full tests | `make test` | exit 0 |
| Guidance | `make guidance-check` | exit 0 (this plan file and `plans/README.md` changed) |
| Visual proof | `make install-app`, open Settings → Quotas | layout matches "Target layout" |

## Suggested executor toolkit

- `codegraph_explore` queries: `UsageQuotaSettingsSection SettingsPage`,
  `QuotaProviderRowView QuotaProviderDetailView QuotaStripOrderSheetView`,
  `UsageQuotaMenuBarStrip UsageQuotaMenuPresentation updateStatusItemAppearance`,
  `UsageQuotaPresentationPreferences setSelectedMetrics toggleMetric`.
- Skills: `macos-ui` (grouped Form, native controls), `swiftui-pro`,
  `test-hygiene` for the test edits.

## Scope

**In scope** (only these paths may change):

- `GitMenuBar/Components/UsageQuota/UsageQuotaSettingsSection.swift`
- `GitMenuBar/Components/UsageQuota/QuotaProviderRowView.swift`
- `GitMenuBar/Components/UsageQuota/QuotaProviderDetailView.swift`
- `GitMenuBar/Components/UsageQuota/QuotaStatusPillView.swift`
- `GitMenuBar/Components/UsageQuota/QuotaStripOrderSheetView.swift` (delete, unless Step 5 fallback applies)
- `GitMenuBar/Services/UsageQuota/UsageQuotaPresentationPreferences.swift`
- `GitMenuBar/Pages/Settings/SettingsPage.swift` (only the Quotas `Section` wrapper at `:204-211`)
- `GitMenuBarTests/UsageQuotaPresentationPreferencesTests.swift`
- `GitMenuBarTests/QuotaProviderStatusTests.swift`
- `plans/README.md` (status row only)

**Out of scope**:

- Stored keys in `AppPreferences.Keys` and the raw values of every enum
  (`MenuBarVisibility`, `WorkdayTickAppearance`, `ValueStyle`, `MeterStyle`,
  `Metric`). Map toggles onto the existing enums; do not migrate data.
- `QuotaProviderStatus.resolve(...)` logic.
- `StatusBarController+UsageQuotaMenu.swift`, the strip renderer, quota
  fetching, and the API-key editor (`QuotaAPIKeyEditorView`).
- Any other Settings section.

## Git workflow

- Branch and worktree follow `skills/bind-unit/references/worktree-admission.md`.
- One commit, for example `feat(quotas): restructure quota settings into sections`.
- Do not merge, push, or delete branches without operator authorization.

## Steps

### Step 1: Replace `toggleMetric` with explicit primary and secondary setters

In `UsageQuotaPresentationPreferences`:

- Add `func setPrimaryMetric(_ metric: Metric, for providerID: UsageProviderID)`:
  new list is `[metric]` plus the current second metric when it differs from
  `metric`. Write through `setSelectedMetrics`.
- Add `func setSecondaryMetric(_ metric: Metric?, for providerID: UsageProviderID)`:
  `nil` keeps only the first metric. A value equal to the first metric is
  ignored. Write through `setSelectedMetrics`.
- When the stored list is empty, treat `.session` as the displayed first
  metric in the view, but do not write until the user changes a menu.
- Delete `toggleMetric`.
- Change `ValueStyle.title` from "Left" to "Remaining" (raw value stays `left`).

Tests in `UsageQuotaPresentationPreferencesTests.swift`: replace
`testTogglingThirdMetricReplacesSecondMetric` with cases for: setting the
first metric keeps a different second metric; setting the first metric equal
to the second drops the second; setting the second to `nil` leaves one
metric; setting the second equal to the first is ignored; values persist
across a new `UsageQuotaPresentationPreferences(defaults:)` instance.

**Verify**: `make test-focused TEST_FILTER='GitMenuBarTests/UsageQuotaPresentationPreferencesTests'` → all pass
(build fails until Step 3 removes the `toggleMetric` call; do Steps 1 and 3 together if needed).

### Step 2: Show pills only for exception states

In `QuotaStatusPillView.swift`, add `var showsPill: Bool` on
`QuotaProviderStatus`: `false` for `.hidden` and `.inStrip`, `true` otherwise.
In `QuotaProviderRowView`, render `QuotaStatusPillView` only when
`currentStatus.showsPill`. Keep the row's accessibility: when the pill is not
shown, put the status in the toggle's accessibility value instead.

Add one test in `QuotaProviderStatusTests.swift` that asserts `showsPill` for
all six cases.

**Verify**: `make test-focused TEST_FILTER='GitMenuBarTests/QuotaProviderStatusTests'` → all pass

### Step 3: Replace metric chips with two menus

In `QuotaProviderDetailView`, remove `metricChips` and the "Menu bar" caption.
Add two `Picker`s with `.pickerStyle(.menu)`:

- "Menu bar shows": all `Metric.allCases`; selection = first selected metric
  (or `.session` when empty); set via `setPrimaryMetric`.
- "Second metric": "None" (tag `nil`) plus every metric except the first;
  set via `setSecondaryMetric`.

Keep the existing `.disabled(!usageQuotaStore.showAIUsageQuotas || !usageQuotaStore.isProviderEnabled(providerID))`.
Update the file's doc comment.

**Verify**: `make build` → exit 0

### Step 4: Split the group into four sections

Make `UsageQuotaSettingsSection` return the four `Section`s itself. In
`SettingsPage.swift:204-211`, remove the wrapping `Section` and call
`UsageQuotaSettingsSection()` directly; move the
`SettingsFormSectionHeader(title: "Quotas", icon: "gauge.with.dots.needle.33percent")`
into the first section's header.

1. **Quotas**: "Show AI usage quotas" switch. When on, a "Preview" row with
   `UsageQuotaMenuBarStrip(groups: UsageQuotaMenuPresentation.groups(snapshots: usageQuotaStore.visibleSnapshots, preferences: preferences), style: preferences.meterStyle)`,
   sized like the status item (see `StatusBarController+UsageQuotaMenu.swift`).
   If `groups` is empty, show secondary text "No quota data yet". If
   `menuBarVisibility == .menuOnly`, show secondary text "Shown only inside the menu".
2. **Menu bar** (only when quotas are on):
   - `Toggle("Show in menu bar")` bound to `menuBarVisibility == .always`
     (on → `.always`, off → `.menuOnly`), caption
     "When off, quotas appear only inside the menu."
   - `Picker("Style")` over `MeterStyle`, `.segmented` (the only segmented control left).
   - `Picker("Show")` over `ValueStyle`, `.menu`. Both are disabled when
     "Show in menu bar" is off.
3. **Providers** (only when quotas are on): the provider rows (Step 5).
4. **Pace and warnings** (only when quotas are on):
   - `Toggle("Show pace marker")` bound to `showsPace`, caption
     "Marks where usage should be at this point in the period."
   - `Picker("Workdays per week")` with `.menu` over `1 ... 7`, and
     `Toggle("Show workday ticks")` bound to `workdayTickAppearance == .subtle`.
     Indent both labels with `WorkbenchMetrics.rowContentInset` and disable
     them when `showsPace` is false.
   - `TextField("Warn during session at")` and `TextField("Warn during week at")`
     with `.textFieldStyle(.roundedBorder)` and trailing alignment. Commit on
     submit **and** on focus loss (`@FocusState` + `onChange`), using the
     existing `commitSessionWarnings` / `commitWeeklyWarnings`. Caption under
     the first field: "Percent used, separated by commas." Remove the
     "Press Return to apply" caption.
   - Footer: `Text("Updated \(date, format: .relative(presentation: .named))")`
     from `usageQuotaStore.visibleSnapshots.map(\.fetchedAt).max()` (omit when
     nil), `Button("Refresh now")` (`.link` or `.borderless`) calling
     `usageQuotaStore.refresh(reason: .manual)`, and a trailing
     `Button { } label: { Image(systemName: "info.circle") }` with
     accessibility label "Quota privacy" that opens a `.popover` holding the
     existing privacy text verbatim.

Remove the old `.disabled(!usageQuotaStore.showAIUsageQuotas)` modifiers that
the hidden sections make redundant.

**Verify**: `make build` → exit 0; `make check-preview` → exit 0

### Step 5: Reorder providers inline

In the Providers section, add `.onMove { preferences.moveProvider(from: $0, to: $1) }`
to the `ForEach` and section header caption "Drag to set menu bar order".
Move the "Move <name> up/down" accessibility actions from
`QuotaStripOrderSheetView.orderRow` onto `QuotaProviderRowView`. Delete
`QuotaStripOrderSheetView.swift`, the "Strip order" row, `orderSummary`, and
`showingOrderSheet`.

**Fallback**: if drag reorder does not work inside the grouped `Form` on the
running macOS (row does not move with the pointer), keep
`QuotaStripOrderSheetView`, drop only the "Strip order" summary row, and place
a `Button("Reorder")` in the Providers section header that opens the sheet.
Report which path you took. Do not build a custom drag implementation.

**Verify**: `make install-app`; in Settings → Quotas, drag a provider; the
order persists after reopening Settings and matches the menu-bar strip.

### Step 6: Full gate and visual proof

**Verify**: `make lint` → exit 0; `make test` → exit 0; `git diff --check` → no output;
`make guidance-check` → exit 0. Capture light and dark screenshots of
Settings → Quotas with quotas on, plus one with quotas off, and attach them to
the handoff.

## Test plan

Covered by the Step 1 and Step 2 unit tests (pure preference and status
logic). Layout and interaction proofs are the screenshots and the manual
reorder check in Step 5; no UI test harness is added.

## Done criteria

- [ ] Every step's verification passed.
- [ ] One segmented control remains in the group (Style).
- [ ] No chips; each provider shows "Menu bar shows" and "Second metric" menus.
- [ ] "In strip" and "Hidden" pills no longer render; other states still do.
- [ ] Changing Style or Show updates the Preview row immediately.
- [ ] Warning fields are bordered and apply on focus loss.
- [ ] Existing users keep their settings (no stored key or raw value changed).
- [ ] No files outside the in-scope list changed.
- [ ] Light, dark, and quotas-off screenshots attached.
- [ ] `plans/README.md` row updated.

## STOP conditions

- Drift check shows a mismatch with the excerpts above.
- The preview needs changes to `StatusBarController` or the strip renderer.
- A stored preference key or enum raw value would have to change.
- Removing the outer `Section` in `SettingsPage` breaks another section's layout.
- The same verification fails twice.

## Maintenance notes

- `toggleMetric` is gone; future metric UI must use `setPrimaryMetric` /
  `setSecondaryMetric`.
- Reviewers: check VoiceOver order across the four sections, and that the
  reorder actions still work by keyboard.
- Deferred: shortening the privacy copy (moved verbatim here).
