# Plan 041: Migrate Staged/Unstaged working tree to Diff Trees

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 42cde45..HEAD -- GitMenuBar/Pages/MainMenu/WorkingTreeSectionView.swift GitMenuBar/Components/WorkingTree/ GitMenuBar/Pages/MainMenu/MainMenuContent.swift GitMenuBar/Pages/MainMenu/MainMenuKeyboardNavigation.swift GitMenuBar/Components/History/ChangedFilesSummaryView.swift GitMenuBar/Utils/DiffTree/ plans/039-changed-files-diff-tree-foundation.md plans/040-commit-details-changed-files-summary.md plans/041-working-tree-diff-tree.md plans/README.md CONTEXT.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MED
- **Depends on**: plans/039-changed-files-diff-tree-foundation.md, plans/040-commit-details-changed-files-summary.md
- **Category**: direction
- **Planned at**: commit `42cde45`, 2026-07-26
- **Completed at**: commit pending, 2026-07-26

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: `no`
- **Reviewer required**: `yes` — staging/discard actions + keyboard selection are product-critical
- **Rationale**: Touches the primary daily working-tree surface; interaction regressions are costly.
- **Escalate when**: Staging semantics change, discard confirmation flow is rewritten, or Staged/Unstaged are merged into one list.

## Why this matters

After Commit Details gains a Changed Files Summary, the main panel still shows
flat Staged/Unstaged rows. Users asked to replace that presentation with the
same Diff Tree language while **keeping** separate Staged and Unstaged
sections and the existing stage/unstage, discard, and open actions (reveal in
Finder stays context-menu-only; Open Diff is additive).

## Current state

- `WorkingTreeSectionView` renders a header + flat `WorkingTreeFileRowView`
  list (`GitMenuBar/Pages/MainMenu/WorkingTreeSectionView.swift`).
- Rows expose hover actions (open/discard/stage), status letter `M`/`D`/`U`,
  swipe actions, and selection hooks used by
  `MainMenuKeyboardNavigation.swift`.
- Section headers use `WorkbenchSectionHeaderChrome` via
  `WorkingTreeSectionHeaderView` with always-visible Stage/Unstage (Plan 027).
- Plan 040 introduced Diff Tree UI for commits — reuse row/header patterns
  rather than copying T3 chat-card chrome.
- Locked decisions: working tree **starts expanded** (not T3 auto-collapse);
  keep trailing **Working Tree Status Letters**; do not unify Staged/Unstaged.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift check | `git diff --stat 42cde45..HEAD -- <in-scope paths>` | empty or understood drift |
| Debug build | `make build` | exit 0 |
| Tests | `make test` | `Tests passed` |
| Agent gate | `make agent-check` | pass |

## Suggested executor toolkit

- `global:macos-app-engineering`, `global:menubar`, `global:accessibility-audit`,
  `global:apple-design` (+ overlays).
- Local `swiftui-performance-audit` if the tree causes noticeable menu-open jank
  with large dirty trees — measure before adding caches.

## Scope

**In scope**:
- `GitMenuBar/Pages/MainMenu/WorkingTreeSectionView.swift`
- `GitMenuBar/Components/WorkingTree/WorkingTreeFileRow.swift` (adapt or
  introduce tree-aware row; keep `WorkingTreeLineDiffView`)
- `GitMenuBar/Components/WorkingTree/WorkingTreeSectionHeaderView.swift`
  (only if header must show aggregate + Hide/Show without breaking Stage All)
- `GitMenuBar/Pages/MainMenu/MainMenuContent.swift` — wiring only
- `GitMenuBar/Pages/MainMenu/MainMenuKeyboardNavigation.swift` — preserve
  selection/open/discard behavior for file rows (directories are not
  selectable staging targets)
- Shared extraction from Plan 040 components **only if required** to avoid
  duplication (prefer small shared row chrome under
  `GitMenuBar/Components/WorkingTree/` or `Components/History/` — pick one
  owner and document it in the PR)
- `#Preview` updates for touched UI files
- `plans/README.md` status row

**Out of scope**:
- Merging Staged and Unstaged into one section
- Colored language icons (042)
- Changing Git staging/discard command implementations in `GitManager`
- Commit Details behavior (040) except unavoidable shared extractions
- In-app diff viewer

## Git workflow

- Continue on `feat/t3code-changed-files-summary` (or sequential PR after 040).
- Do not push/PR unless asked.

## Steps

### Step 1: Map interactions before editing

Inventory current callbacks from `WorkingTreeSectionView` /
`MainMenuContent`: select, stage toggle, open, discard, reveal, stage-all,
discard-all. List how keyboard navigation addresses `MainMenuSelectableItem`
for files. STOP if Plan 040’s summary view cannot be adapted without dropping
stage/discard — plan a working-tree-specific tree container instead of forcing
commit-only API.

**Verify**: `rg -n "WorkingTreeSectionView|WorkingTreeFileRowView|MainMenuSelectableItem" GitMenuBar/Pages/MainMenu GitMenuBar/Components/WorkingTree` → understand call sites

### Step 2: Tree-aware working-tree section

For each Staged/Unstaged section:

- Build a Diff Tree from that section’s `[WorkingTreeFile]` via Plan 039
  builder (map `lineDiff` → `DiffTreeStat`).
- Default UI: **expanded** (ignore Commit Details auto-expand thresholds).
- Directory rows: toggle expand; show folder icon + compacted name +
  aggregated `+N/-M`.
- File rows: File Type Icon (reuse Plan 040 `FileTypeSymbol`), name,
  trailing status letter, diff stats; hover reveals open/discard/stage like
  today.
- Preserve context menu (Open, Discard, Stage/Unstage, Reveal in Finder).
- Preserve swipe actions where SwiftUI list/stack still supports them; if the
  new structure breaks swipe, STOP and report rather than silently dropping
  discard/stage gestures.
- Section header: keep Stage All / Discard All hit targets (Plan 027). You may
  add Hide/Show / expand-all **without** removing those actions.

**Verify**: `make build` → exit 0

### Step 3: Selection + keyboard parity

Ensure file rows remain selectable via existing
`MainMenuSelectableItem` IDs. Directory rows must not steal stage/discard
keyboard actions. Update navigation helpers if IDs or focus order change.
Add/adjust unit tests only if keyboard resolver logic is pure and already
tested; otherwise document a manual keyboard checklist.

**Verify**: `make test` → `Tests passed`  
**Verify**: `make agent-check` → pass

### Step 4: Previews + manual checklist

Update `#Preview`s for staged/unstaged trees with nested paths. Manual:

- [ ] Nested paths compact correctly
- [ ] Stage/unstage single file still works
- [ ] Discard still confirms as before (do not change confirmation policy)
- [ ] Expand-all / per-folder toggle works
- [ ] Large dirty trees (~50+ files) still open the menu without multi-second hitch
- [ ] VoiceOver announces status letter + diff stats

## Test plan

- Prefer extending existing working-tree tests only if pure helpers are
  extracted.
- Do not add flaky UI tests.
- Regression: `WorkingTreeParserTests` remain green (untouched parser).

## Done criteria

- [ ] Staged and Unstaged each render Diff Trees
- [ ] Stage/unstage, discard, open preserved; reveal context-menu-only
- [ ] Status letters remain visible on file rows
- [ ] Sections default expanded
- [ ] `#Preview` coverage on touched UI files
- [ ] `make build`, `make test`, `make agent-check` pass
- [ ] `plans/README.md` 041 → DONE

## STOP conditions

- Requirement appears to force a single unified changed-files section.
- Keyboard staging/discard selection breaks and cannot be restored without
  redesigning `MainMenuKeyboardNavigation`.
- Swipe/context actions would be removed without operator approval.
- Plan 039/040 dependencies missing.

## Maintenance notes

- Performance: if rebuild-on-every-keystroke appears, memoize tree build by
  file identity + diff stats, not by view refresh churn.
- Reviewer focus: action affordances at ≥32pt hit targets, status letter
  contrast, no accidental discard of directory rows.
