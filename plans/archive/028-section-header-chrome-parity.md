# Plan 028: Unify Working Tree and History section header chrome

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat bb03dcc..HEAD -- .interface-design/system.md GitMenuBar/Components/WorkingTree/WorkingTreeSectionHeaderView.swift GitMenuBar/Components/History/HistorySectionHeaderView.swift GitMenuBar/Pages/MainMenu/HistorySectionView.swift GitMenuBar/Pages/MainMenu/WorkingTreeSectionView.swift plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: plans/027-working-tree-actions-hit-targets.md
- **Category**: dx
- **Planned at**: commit `bb03dcc`, 2026-07-25

## Execution profile

- **Recommended profile**: `implementer-fast`
- **Risk/lane**: `Low/Fast`
- **Parallelizable**: `no`
- **Reviewer required**: `no`
- **Rationale**: Narrow visual/structural dedupe after Plan 027’s WT header behavior is settled.
- **Escalate when**: extraction turns into main-panel layout redesign or footer/quota changes.

## Why this matters

Working Tree and History section headers are twin chrome with divergent hover fills and border helpers (`WorkbenchPalette` vs raw `Color.primary.opacity(0.08)`). Users perceive one scroll surface; inconsistent headers read as unfinished. This plan aligns chrome only — History does **not** gain Stage actions.

## Current state

After Plan 027, `WorkingTreeSectionHeaderView` always shows Stage/Unstage when applicable.

History still diverges (pre-025 names shown; expect `Workbench*` at execution):

```47:53:GitMenuBar/Components/History/HistorySectionHeaderView.swift
        .background(isHovered ? Color.primary.opacity(0.08) : Color.clear)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.secondary.opacity(colorSchemeContrast == .increased ? 0.45 : 0), lineWidth: 1)
        )
```

WT header uses `WorkbenchPalette.hoverFill()` / `neutralBorder` patterns (see live `WorkingTreeSectionHeaderView` after 025–027).

system.md: “Working Tree and History headers must share the same chrome primitive.”

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift | `git diff --stat bb03dcc..HEAD -- GitMenuBar/Components/WorkingTree/WorkingTreeSectionHeaderView.swift GitMenuBar/Components/History/HistorySectionHeaderView.swift` | understood |
| Incremental | `make agent-check` | exit 0 |
| Full | `make lint && make test` | exit 0 |
| Palette use | `rg -n 'Color\.primary\.opacity\(0\.08\)' GitMenuBar/Components/History/HistorySectionHeaderView.swift` | no match after fix |

## Suggested executor toolkit

- `code-quality`, `swift-conventions`, `apple-design`
- New shared view file needs `#Preview`

## Scope

**In scope**

- Create `GitMenuBar/Components/Common/WorkbenchSectionHeaderChrome.swift` (name OK if adjusted) that owns:
  - collapse chevron + title button
  - hover background via `WorkbenchPalette.hoverFill()`
  - contrast border via `WorkbenchPalette.neutralBorder`
  - shared padding / radius (`rowCornerRadius` or named micro radius — **not** raw `4` if a metric exists)
  - trailing `ViewBuilder` slot for meta/actions
- Refactor `WorkingTreeSectionHeaderView` to use chrome + WT trailing (diffs, always-visible Stage/Unstage, hover Discard all)
- Refactor `HistorySectionHeaderView` to use chrome + count trailing only
- Previews for both headers

**Out of scope**

- Footer / Commit / quota hierarchy
- History row styling beyond the section header
- Changing collapse persistence keys
- Button kit work unrelated to the collapse control

## Git workflow

- Branch: `feat/028-section-header-parity`
- Commit example: `refactor(ui): share Workbench section header chrome`
- No push unless asked

## Steps

### Step 1: Confirm Plan 027 behavior on WT header

Stage/Unstage all visible at rest; Discard all hover-gated.

**Verify**: read `WorkingTreeSectionHeaderView.swift` and confirm; else STOP

### Step 2: Extract shared chrome

Implement shared header; wire WT + History; delete duplicated hover/border code.

**Verify**: `make agent-check` → exit 0

### Step 3: Full gate + index

**Verify**: `make lint && make test` → exit 0; README 028 DONE

## Test plan

- Previews: History header + WT header (with actions) side by side if useful.
- Manual: hover fill matches; Increase Contrast borders appear on both; History count still animates with numeric transition if previously present.

## Done criteria

- [ ] Shared chrome component exists with `#Preview`
- [ ] History header uses `WorkbenchPalette` (no `primary.opacity(0.08)` one-off)
- [ ] WT Plan 027 action policy preserved
- [ ] `make lint && make test` exit 0
- [ ] README 028 DONE

## STOP conditions

- Extracting chrome seems to require rewriting `WorkingTreeSectionView` / `HistorySectionView` beyond header call sites
- Any request to demote footer actions “while aligning headers”

## Maintenance notes

- New section types (e.g. future “Stashes”) should use the same chrome.
- Reviewers: ensure History did not accidentally inherit Stage controls.
