# Plan 081: Replace the workbench inspector with a contextual side panel

> **Executor instructions**: Read this brief and the linked project documents
> before editing. Follow the steps in order and run each verification command.
> If a STOP condition occurs, stop and report it; do not widen the scope.
> When complete, update the Plan 081 row in plans/README.md with implementation,
> review, integration, and main-validation evidence separately. Leave merge and
> push to the operator.
>
> **Drift check (run first)**: git diff --stat 0ec899c..HEAD -- GitMenuBar/Components/Common/WorkbenchMetrics.swift GitMenuBar/App/MainMenuPresentationModel.swift GitMenuBar/App/MainWindowPreferences.swift GitMenuBar/App/StatusBarController.swift GitMenuBar/Services/Persistence/AppPreferences.swift GitMenuBar/Pages/MainMenu/MainMenuInteractionModels.swift GitMenuBar/Pages/MainMenu/MainMenuView.swift GitMenuBar/Pages/MainMenu/MainMenuContent.swift GitMenuBar/Pages/MainMenu/MainMenuKeyboardNavigation.swift GitMenuBar/Pages/MainMenu/MainMenuCommandPaletteActions.swift GitMenuBar/Pages/MainMenu/RepositoryOverviewView.swift GitMenuBar/Pages/MainMenu/HistoryInspectorView.swift GitMenuBar/Pages/MainMenu/InspectorHeaderView.swift GitMenuBar/Pages/MainMenu/InspectorDetailView.swift GitMenuBar/Pages/MainMenu/InspectorDetailView+Preview.swift GitMenuBar/Pages/MainMenu/InspectorCommitWorkspaceView.swift GitMenuBar/Pages/MainMenu/InspectorBranchManagementView.swift GitMenuBar/Pages/MainMenu/InspectorHistoryBrowserView.swift GitMenuBar/Pages/MainMenu/InspectorHistoryModel.swift GitMenuBar/App/MainMenuActionCoordinator.swift GitMenuBarTests/MainMenuInspectorSelectionTests.swift GitMenuBarTests/MainMenuPresentationModelTests.swift GitMenuBarTests/MainWindowPreferencesTests.swift docs/ui.md docs/adr/0010-contextual-workbench-inspector.md docs/adr/0011-commit-workspace-in-inspector.md docs/adr/0012-always-open-inspector.md docs/adr/0013-hsplitview-inspector-fallback.md docs/adr/0014-compact-inspector-sheet.md .agents/overlays/reference-apps.md
>
> Files changed by an earlier execution of this plan are expected only after
> the executor has started. Before editing, unexplained changes in the listed
> paths are a STOP condition.

## Status

- **Priority**: P0
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: Plans 076–080 (REVIEWED inspector wave; content already lives in the inspector)
- **Category**: direction
- **Planned at**: commit 0ec899c, 2026-09-07
- **Finding ID**: contextual-side-panel-overlay
- **Publication**: local
- **Parent issue**: none
- **Issue**: none
- **Integration**: main; merge and push require explicit operator authorization

## Execution profile

- **Recommended profile**: implementer
- **Risk/lane**: High/Full
- **Parallelizable**: no — one presentation owner, one rename sweep, one docs contract
- **Reviewer required**: yes — reverses ADRs 0012/0014, changes main-window shell, focus/dismiss, and durable UI docs
- **Rationale**: The product decision retires the always-open `HSplitView` inspector and compact sheet in favor of a VoiceInk-inspired trailing overlay. Incorrect ownership can duplicate surfaces, dismiss the Working Tree commit flow on accidental outside taps, or leave docs/ui.md contradicting the shipped shell.
- **Escalate when**: a second presentation coordinator is proposed, tap-outside cannot be gated per selection without a second overlay stack, window minimums become unusable without the third column, or Xcode project membership for renames cannot stay mechanical.

## Why this matters

The current workbench keeps a permanent trailing inspector column (empty state
when nothing is selected) and falls back to a sheet below a compact width
threshold. That model consumes width, fights the center-pane max-width rule,
and treats primary commit work as a permanent third surface.

VoiceInk’s `sidePanel` pattern presents detail as a trailing overlay only while
a contextual selection exists: fixed width, slide+opacity motion with Reduce
Motion, optional tap-outside dismiss, and an explicit close control. Adopting
that pattern makes every detail surface — including Working Tree — contextual
and temporary, returns width to the overview, and aligns dismiss discovery with
transient overlays already used elsewhere in the app.

## Confirmed product decisions (grill 2026-09-07)

These are locked for this plan. Do not re-litigate them during implementation.

| Decision | Choice |
|---|---|
| Reference | VoiceInk at `~/Documents/Projects/References/VoiceInk` @ `8f089cb` (`upstream/main`, `v2.13-10-g8f089cb`) |
| License | GPL-3.0 — **inspiration / independent reimplementation only**; do not copy `SidePanel.swift` or assets |
| Shell | Retire always-open third column and compact inspector sheet |
| Content | All current inspector content moves into the side panel, including Working Tree / commit workspace |
| Narrow windows | Same overlay always; **no** compact sheet |
| Width | Fixed Workbench token (use the former `inspectorDefaultWidth` value **560** as `sidePanelWidth`; drop resize persistence for the panel) |
| Dismiss | Tap-outside + Escape + close for most selections; **Working Tree disables tap-outside** (Escape + close only) |
| Draft commit | `commentText` on `MainMenuView` already survives panel close; do not clear it on dismiss |
| Host | Attach overlay to the **detail** column only; Projects sidebar stays outside the dismiss layer |
| Center pane | Remove `centralMaximumWidth` (500) so the overview grows with the window |
| Close control | Explicit close button on every side-panel surface |
| Naming | Rename product and code vocabulary from Inspector → Side Panel in this plan |
| Docs / catalog | Same plan: update `docs/ui.md`, supersede/align ADRs 0010–0014, register VoiceInk in the reference overlay |

## Current state

- `MainMenuContent` builds `NavigationSplitView` + `HSplitView` with an always-present trailing `inspectorContent` when `!presentationModel.isInspectorCompact`, and a `.sheet` when compact and a selection exists (`docs/ui.md`, ADR 0012/0014).
- `MainMenuPresentationModel.isInspectorCompact` is driven by `NSWindow` content width via `StatusBarController` with hysteresis; window minimum swaps between three-column and two-column floors.
- Selection owner is `MainMenuView.selectedInspectorSelection: MainMenuInspectorSelection?`. Escape clears selection first; the column stays open today.
- Content routers already exist: `InspectorCommitWorkspaceView` (`.workingTree`), `HistoryInspectorView` (`.history` / `.commit`), `InspectorDetailView` (other cases + empty state).
- Width tokens live in `WorkbenchMetrics` (`inspectorMinimumWidth` 320, `inspectorDefaultWidth` 560, `centralMaximumWidth` 500, compact threshold = three-column minimum).
- `AppPreferences.Keys.inspectorColumnWidth` / `MainWindowPreferences.inspectorColumnWidth()` seed ideal split width; session divider is not written back from SwiftUI (ADR 0013).
- Reference behavior to study (do not copy):  
  `~/Documents/Projects/References/VoiceInk/VoiceInk/DesignSystem/Overlays/SidePanel.swift`  
  Call sites: Modes (`ModeView`), Model Library (`ModelManagementView`), History, Dictionary, Dashboard.

## Target state

- Two inline surfaces while no selection: Projects sidebar + repository overview (center grows).
- Selecting a central topic/item presents one trailing **side panel** overlay over the detail column.
- Nil selection means no panel (no empty permanent column).
- One optional `MainMenuSidePanelSelection` (renamed from `MainMenuInspectorSelection`) remains the only presentation owner.
- Compact-sheet path, `isInspectorCompact`, and three-column window minimum derived from an inspector column are removed or reduced to the two-column floor.
- User-facing and code names use Side Panel; ADRs and `docs/ui.md` match the shipped shell.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Drift | `git diff --stat 0ec899c..HEAD --` [paths in the drift check] | Empty or explained changes from this plan only |
| Focused implementation check | `make agent-check` | Changed Swift lint and Debug build pass |
| Focused tests | `make test-focused TEST_FILTER='GitMenuBarTests/MainMenuSidePanelSelectionTests'` (and presentation/window preference tests renamed as needed) | Pass |
| Preview coverage | `./scripts/check-preview.sh` on every new/renamed UI Swift file under `GitMenuBar/Pages/MainMenu` touched by this plan | Pass |
| UI gate | `make check-preview` | Passes, or documented clean-tree baseline |
| Guidance | `make guidance-check` | Guidance and local plan profiles pass |
| Hygiene | `git diff --check` | No whitespace errors |

## Suggested executor toolkit

- Read [docs/ui.md](../docs/ui.md) before changing native UI; update it in the same change set as the shell.
- Study VoiceInk `SidePanel.swift` locally for behavior only; reimplement with Workbench tokens/materials.
- Use `apple-design` for materials, hierarchy, motion, and native macOS surface decisions.
- Use `macos-app-shell` / `swiftui-expert-skill` for overlay ownership, Escape, and scroll owners.
- Use `swiftui-accessibility-audit` for close labels, focus, Reduce Motion, Reduce Transparency.
- Use `reference-apps` + project overlay when registering VoiceInk.
- Use `ui-documentation` when superseding ADRs and rewriting the three-surface contract.
- Use `test-hygiene` before creating or running tests; keep tests nonvisual.
- Use `delivery-workflow` before build, test, lint, preview, or guidance gates.
- Use `ux-writing` for the close control’s accessible label and any empty-state copy removal.

## Scope

**In scope — the only product/document files this plan may modify** (plus renames of the listed Inspector/HistoryInspector paths to SidePanel equivalents, and Xcode project membership updates required by those renames):

- `GitMenuBar/Components/Common/WorkbenchMetrics.swift`
- `GitMenuBar/Components/Common/SidePanel.swift` (create — independent reimplementation)
- `GitMenuBar/App/MainMenuPresentationModel.swift`
- `GitMenuBar/App/MainWindowPreferences.swift`
- `GitMenuBar/App/StatusBarController.swift`
- `GitMenuBar/App/MainMenuActionCoordinator.swift` (rename-only call sites if needed)
- `GitMenuBar/Services/Persistence/AppPreferences.swift` (stop using / document unused `inspectorColumnWidth` key; do not invent a new persisted panel width)
- `GitMenuBar/Pages/MainMenu/MainMenuInteractionModels.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuView.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuContent.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuKeyboardNavigation.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuCommandPaletteActions.swift`
- `GitMenuBar/Pages/MainMenu/RepositoryOverviewView.swift`
- All current `Inspector*` / `HistoryInspector*` MainMenu files listed in the drift check (rename + close control + any host API adjustments)
- Matching `GitMenuBarTests/*Inspector*` / presentation / window preference tests listed in the drift check
- `docs/ui.md`
- `docs/adr/0010-contextual-workbench-inspector.md` through `docs/adr/0014-compact-inspector-sheet.md` (status + superseding ADR)
- `docs/adr/0015-contextual-side-panel.md` (create — records this decision)
- `.agents/overlays/reference-apps.md`
- `plans/README.md` — only the Plan 081 bookkeeping row

**Out of scope:**

- Copying VoiceInk source, assets, trademarks, or GPL-tainted verbatim code
- New Git queries, monitor behavior, or commit-message persistence redesign
- Resizable side panel / restoring divider persistence
- Reintroducing a compact sheet or a permanent empty third column
- Fourth `NavigationSplitView` column or a separate detail window
- Unrelated transient overlays (command palette, branch selector, projects popover)
- Changing status-item click/dismissal or Settings IA

## Git workflow

- Implement on the isolated worktree and branch assigned by the operator,
  following `core/policies/worktrees.md`.
- The plan-authoring base is `0ec899c`. Reclassify the live implementation
  against the actual post-plan base before editing.
- Prefer reviewable commits: (1) metrics + overlay primitive, (2) MainMenu host
  + dismiss rules, (3) rename sweep, (4) docs/ADR/catalog, (5) tests/validation.
- Do not merge, push, amend, or clean up worktrees without authorization.

## Steps

### Step 1: Metrics and window contract

In `WorkbenchMetrics`:

- Add `sidePanelWidth` (fixed **560**, matching today’s `inspectorDefaultWidth`).
- Remove or stop using `centralMaximumWidth` for the main overview pane.
- Retire compact-inspector tokens that only exist for the sheet threshold
  (`compactInspectorThresholdWidth`, `compactInspectorHysteresis`) once callers
  are gone.
- Redefine `mainWindowMinimumWidth` / initial width for a **two-column**
  workbench (sidebar + center). Drop the three-column floor that assumed an
  always-open inspector.
- Rename leftover `inspector*` width tokens to `sidePanel*` where still needed
  (e.g. preview frame helpers), or delete if unused.

Update `StatusBarController` / `MainMenuPresentationModel` to stop driving
`isInspectorCompact` and to stop swapping compact vs three-column minimums.
Delete dead compact presentation API rather than leaving stubs.

Stop reading `inspectorColumnWidth` for layout. Leaving the unused defaults key
in place is acceptable; do not add a new persisted side-panel width key.

**Verify**: `make agent-check` still type-checks after presentation-model API
removal, or proceed immediately to Step 2 in the same commit if the host still
references compact APIs.

### Step 2: Reimplement the side panel overlay

Create `GitMenuBar/Components/Common/SidePanel.swift` as an independent
Workbench-token implementation inspired by VoiceInk:

- `View` modifier `sidePanel(isPresented:width:dismissOnOutsideTap:content:)`
  (names may match local Swift style; behavior must match the table below).
- Trailing `ZStack` overlay; panel does **not** push layout.
- Fixed width from `WorkbenchMetrics.sidePanelWidth`.
- Dismiss layer: clear hit-testable full detail area when
  `dismissOnOutsideTap == true`.
- Motion: slide from trailing + opacity; honor `accessibilityReduceMotion`
  with a shorter opacity-only transition (VoiceInk uses ~0.32s smooth /
  ~0.12s reduced).
- Background: Workbench / native material consistent with existing panels
  (sidebar material or shared workbench surface) — not a copied VoiceInk theme
  color.
- Leading edge separator only as needed for hierarchy; no card chrome in the
  hero sense — keep workbench density.

Add `#Preview` coverage for the modifier host.

**Verify**: preview check on the new file; build includes the new source in the
app target.

### Step 3: Host the panel from MainMenu detail

In `MainMenuContent`:

- Remove the trailing `HSplitView` inspector column and the compact `.sheet`.
- Keep `NavigationSplitView` sidebar + detail; detail is overview/`routeContent`
  only when the panel is closed.
- Apply `sidePanel` to the **detail** subtree (not the whole window), bound to
  `selectedSidePanelSelection != nil`.
- Route the same content that `inspectorContent` routes today into the panel
  body (Working Tree / History / Detail).
- Pass `dismissOnOutsideTap: selection != .workingTree` (and any associated
  file-drill cases that still live inside the Working Tree workspace should
  follow the Working Tree policy while that root selection is `.workingTree`).
- Escape / `onExitCommand`: clearing side-panel selection closes the panel;
  preserve the existing dismiss priority chain (selection → palette →
  transient overlays → close window).
- Repo switch / leaving `.main` continues to clear selection (existing
  behavior).

Restore an explicit close control on the panel chrome (header). Accessible
label e.g. “Close details”. Close clears selection.

Remove empty-state “No details selected” UI that only existed for the
always-open column.

**Verify**: manual checklist below; focused selection tests still compile
against temporary names if rename is deferred to Step 4 in the same PR.

### Step 4: Rename Inspector → Side Panel

Mechanical but mandatory in this plan:

- `MainMenuInspectorSelection` → `MainMenuSidePanelSelection`
- `selectedInspectorSelection` / `clearInspectorSelection` /
  `prepareInspectorSelection` → Side Panel equivalents
- Types/files: `Inspector*` / `HistoryInspector*` → `SidePanel*` /
  `HistorySidePanel*` (choose consistent prefix; prefer `SidePanel` for the
  shell chrome and keep history browser naming coherent)
- Tests and comments/docs strings in touched Swift files
- Update Xcode project file membership for renames

Do not leave dual typealiases as a permanent API; a short-lived internal
typealias during the commit series is OK if the final tree has one name.

**Verify**: `rg -n 'Inspector' GitMenuBar GitMenuBarTests` shows only
historical ADR filenames, plan archives, or intentional “superseded inspector”
doc references — not live type names.

### Step 5: Documentation and VoiceInk catalog

- Rewrite the three-surface / inspector sections of `docs/ui.md` for:
  sidebar + overview + **contextual side panel overlay**; fixed width; no
  compact sheet; Working Tree dismiss exception; Escape clears selection;
  center grows without the 500pt cap.
- Add `docs/adr/0015-contextual-side-panel.md` capturing the trade-off vs
  always-open inspector.
- Mark ADRs 0010–0014 superseded or partially superseded with pointers to 0015
  (preserve history; do not delete).
- Register **VoiceInk** in `.agents/overlays/reference-apps.md`:

  | Attribute | Value |
  |---|---|
  | Canonical name | VoiceInk |
  | Classification | UI/UX + Engineering |
  | Local path | ~/Documents/Projects/References/VoiceInk |
  | Cloned? | Yes |
  | Remote | https://github.com/Beingpax/VoiceInk |
  | Reference revision | `8f089cb` (`v2.13-10-g8f089cb`, `upstream/main`) |
  | License | GPL-3.0 |
  | Reuse decision | Inspiration and independent reimplementation only; do not copy source, assets, trademarks, or brand identity. No README credit required. |
  | Description | Native macOS dictation app; trailing `sidePanel` overlay for mode editing and cloud model configuration. |

  Add touchpoints pointing at `VoiceInk/DesignSystem/Overlays/SidePanel.swift`
  and the Modes / ModelLibrary call sites.

**Verify**: `make guidance-check`; docs cross-links resolve.

### Step 6: Tests and closeout

- Rename/update selection tests for Side Panel identity and dismiss bindings.
- Replace compact-inspector presentation tests with assertions that compact
  sheet APIs are gone and that window minimums use the two-column contract.
- Keep tests nonvisual (no XCUIApplication side-panel animation asserts).
- Run `make agent-check`, focused tests, `make check-preview` (or explicit
  candidates), `make guidance-check`, `git diff --check`.
- Update the Plan 081 row in `plans/README.md`.

## Manual verification checklist

- [ ] Wide window: overview uses extra width; no empty third column.
- [ ] Select Working Tree: panel opens; click overview behind panel does
      **not** dismiss; Escape and Close do.
- [ ] Select Branches/Stashes/History: tap outside dismisses; Escape/Close too.
- [ ] Type a commit message, close panel, reopen Working Tree: draft still
      present (`commentText`).
- [ ] Switch project while panel open: selection clears / panel closes.
- [ ] Narrow window: same overlay (no sheet); sidebar remains usable.
- [ ] Reduce Motion: panel appears/disappears without long slide.
- [ ] VoiceOver: close control labeled; panel title reflects selection.

## Acceptance criteria

- No always-open trailing inspector column and no compact inspector sheet.
- One selection-gated trailing side panel overlay hosts all former inspector
  content, including Working Tree.
- Working Tree disables outside-tap dismiss; other selections keep it.
- Fixed `sidePanelWidth` token; center pane no longer capped at 500pt for
  feeding an inspector.
- Inspector vocabulary renamed to Side Panel in product code/tests.
- `docs/ui.md` + ADR 0015 (+ superseded 0010–0014) and VoiceInk catalog entry
  match the shipped behavior.
- Validation commands above pass; manual checklist completed or gaps reported.

## STOP conditions

- Unexplained drift on listed paths before editing.
- Proposal to copy VoiceInk GPL sources into the tree.
- Second presentation owner or simultaneous sheet + overlay.
- Restoring always-open empty column or compact sheet “temporarily”.
- Clearing `commentText` on panel dismiss.
- Scope expansion into Git/monitor/settings work.
- Unexpected changed paths outside the allow-list.

## Handoff

Return: absolute worktree path, branch, commit SHAs, validation evidence,
manual checklist results, residual risks, and whether merge/push remain blocked
for the operator.
