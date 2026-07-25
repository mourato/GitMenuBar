# Plan 027: Enlarge working-tree hit targets and always-show section Stage/Unstage

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat bb03dcc..HEAD -- .interface-design/system.md GitMenuBar/Components/WorkingTree/ GitMenuBar/Pages/MainMenu/MainMenuKeyboardNavigation.swift plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/025-workbench-system-and-token-rename.md, plans/026-workbench-button-variants-main-panel.md
- **Category**: direction
- **Planned at**: commit `bb03dcc`, 2026-07-25

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: `no` — layout + discoverability on the same headers/rows
- **Reviewer required**: `yes` — accessibility / hit-target / accidental discard risk
- **Rationale**: Product policy change on section actions plus interactive geometry; needs judgment beyond mechanical edits.
- **Escalate when**: adding new keyboard shortcuts for stage, or changing per-file hover-reveal policy to always-visible icons.

## Why this matters

Per-file and section icon hit frames are ~18×16 pt — easy to miss-click Discard vs Stage. Section Stage/Unstage all are hover-gated behind a diff↔actions swap, which hurts discoverability. Product decision (grill): keep **per-file** hover icons (density signature), but **always show** section Stage/Unstage all, enlarge hit areas, keep Discard all hover+confirm, keep swipe/context menu, and **do not** add a new per-file stage key this wave.

## Current state

Policy source: `.interface-design/system.md` § Working-tree actions.

```3:7:GitMenuBar/Components/WorkingTree/WorkingTreeFileRow.swift
enum WorkingTreeLayoutMetrics {
    static let actionWidth: CGFloat = 18
    static let diffColumnWidth: CGFloat = 72
    static let statusColumnWidth: CGFloat = 14
    static let trailingContentPadding: CGFloat = 12
}
```

```147:186:GitMenuBar/Components/WorkingTree/WorkingTreeFileRow.swift
                HStack(spacing: 4) {
                    // Open / Discard / Stage buttons
                    // .frame(width: WorkingTreeLayoutMetrics.actionWidth, height: 16)
                }
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
```

```43:76:GitMenuBar/Components/WorkingTree/WorkingTreeSectionHeaderView.swift
            ZStack(alignment: .trailing) {
                WorkingTreeLineDiffView(...)
                    .opacity(isHovered && showsAction ? 0 : 1)

                HStack(spacing: 4) {
                    if let onDiscardAll { /* Discard all — hover */ }
                    Button(action: onAction) { /* Stage/Unstage all */ }
                }
                .opacity(isHovered && showsAction ? 1 : 0)
                .allowsHitTesting(isHovered && showsAction)
            }
```

Keyboard today (`MainMenuKeyboardNavigation.swift`): ↑/↓, Return opens file, Delete discards unstaged. **No** stage toggle key — leave unchanged.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift | `git diff --stat bb03dcc..HEAD -- GitMenuBar/Components/WorkingTree/` | understood |
| Incremental | `make agent-check` | exit 0 |
| Full | `make lint && make test` | exit 0 |
| Policy grep | `rg -n 'opacity\(isHovered && showsAction' GitMenuBar/Components/WorkingTree/WorkingTreeSectionHeaderView.swift` | Stage/Unstage path no longer hover-gated (Discard all may still be) |

## Suggested executor toolkit

- `accessibility-audit`, `apple-design`, `swiftui-performance-audit` (avoid layout thrash), `swift-conventions`
- Prefer Plan 026 Icon style for header/row icon buttons when wiring

## Scope

**In scope**

- `WorkingTreeLayoutMetrics` — introduce hit size (≥ `WorkbenchMetrics.iconHitTarget`, prefer 32) while allowing compact glyph; keep column layout readable
- `WorkingTreeFileRowView` — enlarge hit/`contentShape` for Open/Discard/Stage; **keep** hover-only visibility for the triad; keep swipe + context menu
- `WorkingTreeSectionHeaderView` — **always** show Stage all / Unstage all when `showsAction`; keep line-diff summary visible (do not zero it to reveal the primary bulk action); keep Discard all on hover (or secondary disclosure) + existing confirmation pipeline
- Previews updated for header with always-visible bulk action
- Accessibility labels remain meaningful when controls are always visible

**Out of scope**

- New keyboard shortcut for stage/unstage (`MainMenuKeyboardNavigation.swift` — do not add Space/S)
- Always-showing per-file Open/Discard/Stage triad
- History header work (Plan 028)
- Footer / Commit hierarchy
- Changing discard confirmation copy/flow beyond what’s needed to keep Discard all safe

## Git workflow

- Branch: `feat/027-working-tree-actions-hit-targets`
- Commit example: `fix(ui): always show section stage actions and enlarge hit targets`
- No push unless asked

## Steps

### Step 1: Confirm dependencies

025 + 026 landed (`WorkbenchMetrics.iconHitTarget`, button kit available).

**Verify**: `rg -n 'iconHitTarget' --glob '*.swift' GitMenuBar` → match; button styles file exists

### Step 2: Metrics + file row hit areas

Raise actionable hit targets without forcing the whole row to 44pt tall if avoidable — use expanded `contentShape` / padding around glyphs. Keep hover reveal for per-file actions.

**Verify**: `make agent-check` → exit 0

### Step 3: Section header always-visible Stage/Unstage

Restructure so diffs and Stage/Unstage can coexist (HStack/priority), not ZStack hover swap for the primary bulk action. Discard all remains hover-gated.

**Verify**: preview + `make agent-check` → exit 0

### Step 4: Full gate

**Verify**: `make lint && make test` → exit 0; README 027 DONE

## Test plan

- Update/extend Working Tree section header preview: action visible without hover.
- Manual: Unstaged section shows Stage all at rest; diffs still readable; Discard all not easy to hit accidentally; per-file icons still hover-only; swipe still stages; Return/Delete keyboard unchanged.
- Optional XCTest only if there is an existing view-model hook; do not force UI tests.

## Done criteria

- [ ] Section Stage/Unstage all visible without hover when `showsAction`
- [ ] Line-diff summary remains visible alongside those actions
- [ ] Discard all not always-visible
- [ ] Per-file action hit areas ≥ 28×28 effective
- [ ] Per-file actions still hover-revealed
- [ ] No new stage keyboard shortcut
- [ ] `make lint && make test` exit 0
- [ ] README 027 DONE

## STOP conditions

- Layout cannot fit always-visible Stage all without truncating filenames badly — STOP and report options (icon-only vs text) rather than hiding diffs again
- Accidental overlap of Discard all and Stage all hit areas
- Pressure to always-show per-file icons or add Space-to-stage

## Maintenance notes

- Plan 028 will share header chrome with History — keep Stage actions in a WT-only trailing slot.
- Reviewers: verify Reduce Motion still OK; VoiceOver can focus always-visible bulk actions.
