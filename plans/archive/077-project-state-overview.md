# Plan 077: Add the central project-state overview

> **Executor instructions**: Read this brief and Plan 076 completely before
> editing. Follow the steps in order and verify each one. Changes from Plan
> 076 in shared MainMenu files are expected; unexplained changes are a STOP
> condition. Update only the Plan 077 bookkeeping row when complete.
>
> **Drift check (run first)**: git diff --stat 2118aad..HEAD -- GitMenuBar/Pages/MainMenu/MainMenuComputed.swift GitMenuBar/Pages/MainMenu/MainMenuInteractionModels.swift GitMenuBar/Pages/MainMenu/MainMenuView.swift GitMenuBar/Pages/MainMenu/MainMenuContent.swift GitMenuBar/Pages/MainMenu/MainMenuInspectorView.swift GitMenuBar/Pages/MainMenu/RepositoryOverviewView.swift GitMenuBarTests/MainMenuRenderSnapshotTests.swift GitMenuBarTests/RepositoryOverviewSnapshotTests.swift

## Status

- **Priority**: P0
- **Effort**: M
- **Risk**: MED
- **Depends on**: [Plan 076](076-workbench-inspector-shell.md)
- **Category**: direction
- **Planned at**: commit 2118aad, 2026-09-03
- **Finding ID**: central-project-state-overview
- **Publication**: local
- **Parent issue**: none
- **Issue**: none
- **Integration**: main; merge and push require explicit operator authorization

## Execution profile

- **Recommended profile**: implementer
- **Risk/lane**: Medium/Full
- **Parallelizable**: no — it extends the Plan 076 selection and render paths and must integrate with the shell before action work starts
- **Reviewer required**: yes — counts and unavailable states are user-facing Git information, and the plan changes central workbench hierarchy and accessibility
- **Rationale**: Existing monitor snapshots and selected GitManager state already contain almost all summary data. The safe implementation is a pure render snapshot plus native buttons, not new Git queries, a cache, or a charting layer.
- **Escalate when**: a summary requires a new Git process, automatic fetch, a second monitor/store, a chart/graph, or a persisted overview layout.

## Why this matters

The Projects sidebar correctly answers that a repository needs attention, but
its truncated one-line summary is not a useful workspace for understanding
why. The central area should make the selected repository's working tree,
remote sync, branch health, stashes, and loaded history legible at a glance.
Each summary must be actionable: selecting it opens the corresponding right
inspector from Plan 076 without duplicating the underlying Git state.

This plan adds a compact overview above the existing commit/worktree content.
It does not remove the existing working-tree renderer or move history yet;
Plan 079 owns the history migration.

## Current state

- MainMenuView.refreshRenderSnapshot at :398-413 builds one
  MainMenuRenderSnapshot from selected GitManager state. It currently
  refreshes for working-tree, history, branch, remote, and repository changes.
- MainMenuComputed.swift:8-92 owns the immutable render snapshot and currently
  has row adapters, history sections, keyboard items, branch menu rows, and
  project identity.
- ProjectMonitorStore.snapshots is a published path-keyed dictionary.
  ProjectStatusSnapshot contains branchesWithoutUpstreamCount,
  unpushedBranchCount, unmergedBranchCount, stashCount, aheadCount, and
  behindCount. Lookup must use the normalized repository path.
- GitManager already publishes exact selected-project staged/unstaged files,
  commitCount (current branch commits ahead of upstream when available),
  behindCount, branchInfos, current branch, detached state, and loaded
  commitHistory. Do not call a Git command from the overview view.
- MainMenuInspectorSelection from Plan 076 contains section selections for
  workingTree, branches, unpushedCommits, stashes, and history. Use those
  cases as the overview card destinations.
- The main route keeps CommitWorkflowView outside its main ScrollView and puts
  mainScrollContent in the scroll owner at MainMenuContent.swift:123-173.
  Place the overview in that existing scroll owner so the composer and footer
  remain fixed as required by docs/ui.md.
- The existing WorkbenchMetrics, WorkbenchTypography, WorkbenchPalette, and
  native Button patterns are the visual owners. Do not introduce a new color
  system, card dependency, or hover-only action.

Use explicit unavailable values. A missing monitor snapshot or a selected
repository that is still loading must not appear as zero branches or zero
stashes. The overview model should distinguish a known zero from unavailable
or refreshing data, for example with a small Equatable metric value enum.
Keep the model pure and cheap to build.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Drift | git diff --stat 2118aad..HEAD -- [the paths in the drift check] | Empty or explained Plan 076/077 changes only |
| Focused model tests | make test-focused TEST_FILTER='GitMenuBarTests/MainMenuRenderSnapshotTests' | Existing and new render snapshot cases pass |
| Overview tests | make test-focused TEST_FILTER='GitMenuBarTests/RepositoryOverviewSnapshotTests' | All pure overview cases pass |
| Changed-surface check | make agent-check | Changed Swift lint and Debug build pass |
| Preview coverage | ./scripts/check-preview.sh GitMenuBar/Pages/MainMenu/RepositoryOverviewView.swift GitMenuBar/Pages/MainMenu/MainMenuInspectorView.swift | All supplied UI candidates have previews |
| UI gate | make check-preview | Passes, or the known clean-tree baseline is recorded with explicit candidates |
| Hygiene | git diff --check | No whitespace errors |

## Suggested executor toolkit

- Use swiftui-expert-skill for render snapshots, stable Button identity,
  state updates, previews, and scroll ownership.
- Use apple-design and the GitMenuBar apple-design overlay for calm compact
  hierarchy and reduced-motion behavior.
- Use better-accessibility only if available for the overview's labels/values;
  otherwise follow swiftui-accessibility-audit.
- Use ux-writing for card titles, unavailable/loading copy, and action labels.
- Use test-hygiene and test-strategy for quiet pure tests; do not render a
  window from XCTest.
- Use delivery-workflow before all validation commands.

## Scope

**In scope:**

- GitMenuBar/Pages/MainMenu/MainMenuComputed.swift
- GitMenuBar/Pages/MainMenu/MainMenuInteractionModels.swift
- GitMenuBar/Pages/MainMenu/MainMenuView.swift
- GitMenuBar/Pages/MainMenu/MainMenuContent.swift
- GitMenuBar/Pages/MainMenu/MainMenuInspectorView.swift
- GitMenuBar/Pages/MainMenu/RepositoryOverviewView.swift (create)
- GitMenuBarTests/MainMenuRenderSnapshotTests.swift
- GitMenuBarTests/RepositoryOverviewSnapshotTests.swift (create)
- plans/README.md — only the Plan 077 bookkeeping row

**Out of scope:**

- GitManager, ProjectMonitorStore, ProjectStatusReader, GitBranchService, or
  any new Git command
- branch lists, file detail, push, stage/unstage, discard, switch, merge,
  delete, stash apply/drop, or any other mutation (Plan 078)
- moving the full history list into the inspector or deleting historyDetail
  (Plan 079)
- automatic fetch, live polling, cached metrics, charts, graphs, drag/drop
  layout, user-configurable cards, or new toolbar controls

## Git workflow

- Use the isolated implementation worktree/branch required by
  core/policies/worktrees.md.
- Reclassify risk against the live Plan 076 diff before editing shared files.
- Keep Plan 077 serial after Plan 076; leave the branch intact for review.
- Do not merge, push, amend, or clean up worktrees without authorization.

## Steps

### Step 1: Add a pure overview snapshot

Extend MainMenuComputed.swift with a small Equatable overview value model and
builder. Feed it only existing selected GitManager values and the normalized
ProjectMonitorStore snapshot. Include:

- staged, unstaged, and untracked file counts plus line totals;
- current-branch commits pending push and remote-behind count when known;
- branches without upstream, unpushed branches, unmerged branches, and retained
  stash count when the monitor snapshot is available;
- loaded history count and current branch/detached state;
- loading/unavailable state and last checked time for monitor-derived values.

Use a named metric state such as known(value), loading, and unavailable rather
than converting missing data to zero. Keep selected exact data separate from
monitor-derived compact data so the UI can explain stale or not-yet-checked
values. Do not add a second repository reader.

Update MainMenuRenderSnapshot.build and MainMenuView.refreshRenderSnapshot with
the smallest additional inputs necessary. Add onChange for
projectMonitor.snapshots so the overview updates after path-scoped monitor
refreshes. Keep derived arrays stable and use stable IDs.

**Verify**: MainMenuRenderSnapshotTests and
RepositoryOverviewSnapshotTests cover known, loading, unavailable, clean,
dirty, detached, ahead/behind, and nonzero branch/stash states; the focused
test commands pass without starting a Git process.

### Step 2: Render the central overview

Create RepositoryOverviewView.swift with a compact vertical overview, not a
large dashboard. Use native Button cards or rows with one primary selection
target each:

- Working Tree — staged/unstaged/untracked counts and line summary;
- Push and Sync — current branch ahead/behind state;
- Branch Health — unmerged, unpushed, and no-upstream counts;
- Stashes — retained stash count and last-checked state;
- History — loaded commit count and current branch context.

Show known zero values, loading values, and unavailable values distinctly.
Avoid ellipses in visible labels. Add accessibility labels, values, and hints
that state what opens in the inspector. Ensure each card remains usable with
keyboard focus and VoiceOver; do not make only a colored dot clickable.

Use Workbench tokens and the existing native material/border treatment. Honor
Reduce Motion by using the existing adaptive motion helpers or no layout
animation. Do not nest a ScrollView inside the main scroll owner.

**Verify**: ./scripts/check-preview.sh
GitMenuBar/Pages/MainMenu/RepositoryOverviewView.swift passes. The preview
shows dirty, clean, loading, and unavailable states without live services.

### Step 3: Place cards in the main route and open the inspector

Place RepositoryOverviewView at the top of mainScrollContent, below transient
banners/loading and above the working-tree sections. Keep the CommitWorkflowView
outside the scroll and the BranchManagementControlsView footer unchanged.

Wire each button to set the matching MainMenuInspectorSelection section. The
right panel must reuse the optional selection and presentation owner from Plan
076. Do not add per-card sheets, popovers, or navigation stacks. Preserve
existing row selection and route behavior while Plan 079 is pending.

If the current repository is absent, show the existing select-project state and
do not present overview cards with fabricated zeros. When the selected path
changes, rebuild the snapshot from the new path and clear the old inspector
selection as defined by Plan 076.

**Verify**: a preview/manual check confirms the overview stays in the central
scroll region, the left sidebar remains unchanged, each card opens exactly one
inspector selection, and project switching does not show the previous
repository's counts.

### Step 4: Verify hierarchy and accessibility

Review the overview against docs/ui.md and the accepted ADR from Plan 076.
Check Light/Dark, increased contrast, Reduce Transparency, Reduce Motion,
empty repository, loading repository, no remote, detached HEAD, clean
repository, and stale/missing monitor snapshot. If a status is unknown, use
plain language such as Not checked yet or Unavailable and expose the same
state through accessibilityValue.

**Verify**: make agent-check, explicit preview coverage, and git diff --check
pass. Record any native-only manual checks in the handoff.

## Test plan

- Extend MainMenuRenderSnapshotTests.swift for overview inclusion, stable
  derived values, normalized monitor lookup, and updates when monitor
  snapshots change.
- Add RepositoryOverviewSnapshotTests.swift for known zero versus unavailable,
  loading state, dirty/clean counts, ahead/behind, detached HEAD, and branch/
  stash counts.
- Tests must be pure or use existing in-memory model values. Do not launch
  MainMenuView, create a visible window, or invoke PreviewProvider code.
- Manual UI checks cover card focus, keyboard activation, VoiceOver labels,
  increased contrast, reduced transparency, and reduced motion.

Focused verification:

    make test-focused TEST_FILTER='GitMenuBarTests/MainMenuRenderSnapshotTests'
    make test-focused TEST_FILTER='GitMenuBarTests/RepositoryOverviewSnapshotTests'

## Done criteria

- [ ] The center shows a compact repository overview above the existing
      working-tree/history content without changing the fixed composer/footer
      ownership.
- [ ] Overview values come from existing selected state or monitor snapshots;
      no new Git process, fetch, cache, or polling path exists.
- [ ] Unknown/loading values are not represented as false zeroes.
- [ ] Every overview item is a native keyboard/VoiceOver-accessible Button and
      opens the matching Plan 076 inspector selection.
- [ ] New RepositoryOverviewView has a self-contained preview.
- [ ] Focused tests, make agent-check, preview coverage, and git diff --check
      pass.
- [ ] No files outside Scope are modified; plans/README.md has the Plan 077
      status/evidence row only.

## STOP conditions

Stop and report if:

- Plan 076's selection/presentation owner is missing or has been replaced by
  a second coordinator;
- a requested metric cannot be obtained from existing published state without
  adding a Git command;
- a missing monitor snapshot would be silently rendered as zero;
- the overview requires a nested ScrollView, a fourth column, a charting
  dependency, or a persistent layout preference;
- the live code differs from the Current state in an unexplained way;
- preview coverage needs credentials, a live repository, or a visible window;
- a verification command fails twice after a scoped fix; or
- an out-of-scope file must be modified.

## Maintenance notes

- Plan 078 should replace the section-only inspector bodies with detailed
  content while reusing these section selection cases.
- Plan 079 should use the History overview button as the entry point after the
  full history list leaves the center.
- Do not turn this snapshot into a general dashboard model. If a future view
  needs a metric not already published, first document the data owner and
  latency cost.
- Reviewers should inspect stale/unavailable semantics, count provenance,
  keyboard activation, accessible values, and whether the center still feels
  like a Git workbench rather than a card dashboard.
