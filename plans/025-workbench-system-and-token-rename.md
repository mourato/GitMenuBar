# Plan 025: Lock workbench system.md and rename MacChrome tokens to Workbench

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat bb03dcc..HEAD -- .interface-design/ docs/adr/ GitMenuBar/Components/Common/MacChromeMetrics.swift GitMenuBar/Components/Common/MacChromeMotion.swift GitMenuBar/Components/Common/MacPanelSurface.swift plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MED
- **Depends on**: none
- **Category**: tech-debt
- **Planned at**: commit `bb03dcc`, 2026-07-25

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: `no` — mechanical rename must stay atomic with token extensions
- **Reviewer required**: `no` — broad but deterministic rename; escalate if behavior changes beyond naming/constants
- **Rationale**: Large file touch count and design-doc authority, but no product behavior change if done as pure rename + additive metrics.
- **Escalate when**: rename requires behavior changes to layout, or call-site count balloons into unrelated refactors (buttons, hover policy).

## Why this matters

UI guidance was scattered across `MacChrome*` helpers and oral audit notes. `.interface-design/system.md` and ADR 0001 lock the workbench direction. Renaming tokens to `Workbench*` makes the code match that metaphor and removes generic “chrome template” naming. Extending metrics kills the worst magic numbers so later button/header plans do not invent new literals.

## Current state

- Design docs already authored at grill time (do not rewrite intent; only fix factual drift if needed):
  - `.interface-design/system.md`
  - `docs/adr/0001-workbench-depth-and-token-naming.md`
- Token definitions today:

```64:73:GitMenuBar/Components/Common/MacChromeMetrics.swift
enum MacChromeMetrics {
    static let compactSpacing: CGFloat = 8
    static let sectionSpacing: CGFloat = 12
    static let groupSpacing: CGFloat = 20
    static let panelPadding: CGFloat = 16
    static let windowPadding: CGFloat = 20
    static let rowCornerRadius: CGFloat = 8
    static let cornerRadius: CGFloat = 10
    static let largeCornerRadius: CGFloat = 14
}
```

```3:10:GitMenuBar/Components/Common/MacChromeMotion.swift
enum MacChromeMotion {
    static let micro: Animation = .easeOut(duration: 0.13)
    static let arrive: Animation = .snappy(duration: 0.30, extraBounce: 0.02)
    static let settle: Animation = .smooth(duration: 0.34)
    static let swap: Animation = .easeInOut(duration: 0.20)
    static let press: Animation = .spring(response: 0.15, dampingFraction: 1.0)
    static let route: Animation = .spring(response: 0.35, dampingFraction: 1.0)
    static let reduceMotion: Animation = .easeInOut(duration: 0.20)
```

```3:11:GitMenuBar/Components/Common/MacPanelSurface.swift
enum MacPanelMaterialWeight {
    case thin
    case regular
    case thick
}
```

- ~40 Swift files reference `MacChrome*` / `MacPanel*` / `macPanelSurface` (~244 hits). Xcode uses `PBXFileSystemSynchronizedRootGroup` — renaming files under `GitMenuBar/` does **not** require `project.pbxproj` edits.
- `WorkingTreeLayoutMetrics.actionWidth = 18` stays for Plan 027 (hit targets); do not “fix” row actions here.
- Commit style example: `feat(ui): move Settings to header and reorganize preference panes`

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift check | `git diff --stat bb03dcc..HEAD -- .interface-design/ docs/adr/ GitMenuBar/Components/Common/MacChrome*.swift GitMenuBar/Components/Common/MacPanelSurface.swift` | empty or understood drift |
| Rename sanity | `rg -n 'MacChrome|MacPanel|macPanelSurface' --glob '*.swift' GitMenuBar` | **no matches** after Step 3 |
| Incremental gate | `make agent-check` | lint-changed + Debug build exit 0 |
| Full gate | `make lint && make test` | both exit 0 |

## Suggested executor toolkit

- Skills: `swift-conventions`, `code-quality`, `delivery-workflow`, `apple-design` (overlay)
- Must follow: `.interface-design/system.md`, `docs/adr/0001-workbench-depth-and-token-naming.md`
- Motion reference: `.agents/overlays/references/gitmenubar-motion.md` (values already match `WorkbenchMotion`; update any doc strings that still say `MacChromeMotion`)

## Scope

**In scope**

- Keep / lightly reconcile `.interface-design/system.md` and `docs/adr/0001-workbench-depth-and-token-naming.md` if rename paths differ only by filename
- Rename definition files:
  - `MacChromeMetrics.swift` → `WorkbenchMetrics.swift` (contains `WorkbenchMetrics`, `WorkbenchTypography`, `WorkbenchPalette`, and existing `PressableButtonStyle` / adaptive motion helpers that live in that file today)
  - `MacChromeMotion.swift` → `WorkbenchMotion.swift`
  - `MacPanelSurface.swift` → `WorkbenchPanelSurface.swift`
- Rename symbols:
  - `MacChromeMetrics` → `WorkbenchMetrics`
  - `MacChromeTypography` → `WorkbenchTypography`
  - `MacChromePalette` → `WorkbenchPalette`
  - `MacChromeMotion` → `WorkbenchMotion`
  - `MacPanelMaterialWeight` → `WorkbenchMaterialWeight`
  - `macPanelSurface` → `workbenchPanelSurface`
- Update **all** Swift call sites under `GitMenuBar/` (and tests if any reference old names)
- Add missing named metrics called out by `system.md` if absent: `microSpacing` (4), `chipSpacing` (6), `microCornerRadius` (6), `iconHitTarget` (28), `overlayCornerRadius` (16)
- Replace obvious duplicate literals in files already touched by the rename when they match those values (e.g. command palette `cornerRadius: 16` → `WorkbenchMetrics.overlayCornerRadius`) — do not hunt the whole app for every `4`
- Update `plans/README.md` status for 025
- If overlays/docs mention `MacChromeMotion` as the Swift type name, update those references

**Out of scope**

- Button variant components (Plan 026)
- Working-tree hover/hit-target behavior (Plan 027)
- History/WT header extraction (Plan 028)
- Footer / quota hierarchy redesign
- Confirmation dialog restyle
- Introducing typealiases `typealias MacChromeMetrics = WorkbenchMetrics` (forbidden by ADR)
- Editing `project.pbxproj`

## Git workflow

- Branch: `feat/025-workbench-tokens` (or `advisor/025-workbench-tokens`)
- Commits: conventional, e.g. `refactor(ui): rename MacChrome tokens to Workbench`
- Do NOT push/PR unless asked

## Steps

### Step 1: Drift check + confirm docs present

Run the drift check. Confirm `.interface-design/system.md` and `docs/adr/0001-workbench-depth-and-token-naming.md` exist and describe `Workbench*` naming.

**Verify**: `test -f .interface-design/system.md && test -f docs/adr/0001-workbench-depth-and-token-naming.md` → exit 0

### Step 2: Rename definition files and enum/API names

1. Add new metrics to the metrics enum **before or while** renaming (`microSpacing`, `chipSpacing`, `microCornerRadius`, `iconHitTarget`, `overlayCornerRadius`).
2. Rename files and types as listed in Scope.
3. Update `workbenchPanelSurface` default args to use `WorkbenchMetrics.largeCornerRadius` and `WorkbenchMaterialWeight`.

**Verify**: `rg -n 'enum WorkbenchMetrics|enum WorkbenchMotion|enum WorkbenchMaterialWeight|func workbenchPanelSurface' --glob '*.swift' GitMenuBar` → each appears ≥1

### Step 3: Update all call sites

Replace every `MacChrome*`, `MacPanel*`, `macPanelSurface` reference under `GitMenuBar/` (and tests). Prefer project-wide search/replace carefully (whole-identifier only).

**Verify**: `rg -n 'MacChrome|MacPanel|macPanelSurface' --glob '*.swift' GitMenuBar GitMenuBarTests` → no matches

### Step 4: Build + lint changed

**Verify**: `make agent-check` → exit 0

### Step 5: Full gate + index

**Verify**: `make lint && make test` → exit 0  
Update `plans/README.md` row 025 to DONE (include short SHA if repo convention used for 023/024).

## Test plan

- No new unit tests required for pure rename.
- Rely on `make test` compile + existing UI-adjacent tests.
- Manual: open main panel preview or run app once — materials and spacing should look unchanged aside from any literal→token substitutions that were already equivalent values.

## Done criteria

- [ ] `rg -n 'MacChrome|MacPanel|macPanelSurface' --glob '*.swift' GitMenuBar GitMenuBarTests` returns no matches
- [ ] `WorkbenchMetrics` exposes `microSpacing`, `chipSpacing`, `microCornerRadius`, `iconHitTarget`, `overlayCornerRadius`
- [ ] No `typealias MacChrome` remains
- [ ] `make lint && make test` exit 0
- [ ] `plans/README.md` 025 status DONE
- [ ] No files outside in-scope intent modified (docs/overlays updates for old type names OK)

## STOP conditions

- Drift shows someone already partially renamed tokens differently than ADR/`system.md`
- A call site cannot compile without changing behavior (STOP; do not invent API wrappers)
- Temptation to implement button variants or row hit targets in this PR
- Need to edit `project.pbxproj` for the rename (should be unnecessary)

## Maintenance notes

- Future UI PRs must import vocabulary from `.interface-design/system.md`.
- Reviewers: reject new `MacChrome` names and new raw `cornerRadius: 16` when a metric exists.
- Plans 026–028 assume this rename has landed.
