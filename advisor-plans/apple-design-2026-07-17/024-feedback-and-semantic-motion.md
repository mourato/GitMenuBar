# Plan 024: Complete press feedback and semantic content motion

> **Executor instructions**: Execute only after plans 016–020 are complete and
> plan 021 is stable. Do not touch branch/worktree files owned by the active
> worktree sequence unless the drift check proves they are unchanged and this
> plan explicitly lists them.
>
> **Drift check**: `git diff --stat e9be124..HEAD -- GitMenuBar/Components/Common/MacChromeMetrics.swift GitMenuBar/Components/WorkingTree GitMenuBar/Components/History GitMenuBar/Components/Projects/RecentProjectsSection.swift GitMenuBar/Components/Branches/BottomBranchSelector.swift`

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: 021; plans 016–020 complete
- **Category**: dx
- **Planned at**: commit `e9be124`, 2026-07-17

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: no; press, hover, swipe, and content transitions share gesture arbitration
- **Reviewer required**: no; behavior is bounded to existing rows and controls, with manual UI verification
- **Rationale**: the changes are repetitive but can interfere with double-click and swipe recognition
- **Escalate when**: a new gesture recognizer, reorder interaction, or change to selection/keyboard navigation is needed

## Why this matters

Only file and history rows currently use the custom `.pressable()` modifier.
Other interactive controls use plain button styles, and numeric/icon changes
have no semantic content transition. The project motion reference requires
touch-down feedback, animated hover changes, stable layout slots, and
`numericText`/symbol replacement where appropriate.

## Current state

- `WorkingTreeFileRow.swift:60-100` combines tap, double-tap, swipe actions,
  and the custom zero-distance press gesture.
- `HistoryTimelineSectionView.swift:145-221` has the same interaction mix.
- `HistorySectionHeaderView.swift:18-35` changes chevron and commit count
  without content transitions.
- `WorkingTreeSectionHeaderView.swift:24-75` changes chevron, counts, and
  hover actions without shared motion tokens.
- `RecentProjectsSection.swift:19` still uses a raw
  `.easeInOut(duration: 0.2)`.
- `BottomBranchSelector.swift:22-35` changes numeric badges while explicitly
  disabling animation.

## Commands

| Purpose | Command | Expected |
|---|---|---|
| Agent loop | `make agent-check` | lint and Debug build pass |
| Merge gate | `make lint && make test` | both commands pass |

## Scope

In scope:

- `GitMenuBar/Components/WorkingTree/WorkingTreeFileRow.swift`
- `GitMenuBar/Components/History/HistoryTimelineSectionView.swift`
- `GitMenuBar/Components/History/HistorySectionHeaderView.swift`
- `GitMenuBar/Components/WorkingTree/WorkingTreeSectionHeaderView.swift`
- `GitMenuBar/Components/Projects/RecentProjectsSection.swift`
- `GitMenuBar/Components/Branches/BottomBranchSelector.swift`
- `GitMenuBar/Components/Common/MacChromeMetrics.swift` only for the shared
  press API established by plan 021

Out of scope:

- `Components/Branches/BranchManagement*` and worktree UI from plans 016–020.
- Git selection models, keyboard navigation, and mutation callbacks.
- New swipe actions or drag/reorder features.

## Steps

### Step 1: Apply press feedback to eligible controls

Use the canonical press implementation from plan 021 for primary buttons and
rows. Keep layout bounds stable. For rows with both double-tap and swipe,
verify that press feedback does not execute actions, delay selection, or steal
the swipe gesture. If a row needs a separate gesture modifier, document the
arbitration reason.

**Verify**: manual preview/runtime check confirms touch-down feedback, tap selection, double-click activation, and swipe actions all remain distinct; `make agent-check` passes.

### Step 2: Animate hover and content swaps with tokens

Use `micro` for hover/press release and `swap` for fixed-slot content changes.
Do not animate layout dimensions on every frame. Preserve baseline alignment
when path text changes in recent projects.

**Verify**: `rg -n "easeInOut\(duration: 0\.2\)|spring\(response:" GitMenuBar/Components/Projects GitMenuBar/Components/History GitMenuBar/Components/WorkingTree GitMenuBar/Components/Branches/BottomBranchSelector.swift` returns no unreviewed raw values; `make agent-check` passes.

### Step 3: Add semantic numeric and symbol transitions

Use `.contentTransition(.numericText())` for counts and
`.contentTransition(.symbolEffect(.replace))` for chevrons or other semantic
icon replacements where supported by the deployment target. Keep transitions
disabled/static under Reduce Motion while retaining the changed value.

**Verify**: `rg -n "contentTransition|symbolEffect" GitMenuBar/Components/History GitMenuBar/Components/WorkingTree GitMenuBar/Components/Branches/BottomBranchSelector.swift` shows the intended call sites; `make lint && make test` passes.

## Test plan

- Test selected/unselected file and history rows.
- Test tap, double-click, swipe, context menu, and keyboard selection.
- Test collapsing/expanding headers and changing counts.
- Test recent-project path toggle with short and long paths.
- Test branch selector badge changes without layout jumps.
- Verify Reduce Motion and increased contrast in previews/runtime.

## Done criteria

- [ ] Interactive primary controls provide touch-down feedback.
- [ ] Swipe and double-click behavior remain unchanged.
- [ ] Raw motion values in scope are replaced by named tokens or documented exceptions.
- [ ] Numeric and semantic icon changes use content transitions where useful.
- [ ] Reduce Motion retains readable state changes.
- [ ] `make agent-check` and `make lint && make test` pass.
- [ ] No worktree-plan source files are modified.

## STOP conditions

- Press feedback delays or changes selection/double-click behavior.
- Swipe recognition conflicts with the shared press gesture.
- The deployment SDK does not support a semantic transition used by the plan.
- A fix requires changing selection models or keyboard routing.

## Maintenance notes

Every future interactive row must state whether it uses a ButtonStyle or a
gesture-based press modifier and how that choice interacts with swipe,
double-click, VoiceOver, and keyboard focus.

