# Plan 087: Close preview gaps and cover key UI states

> **Executor instructions**: Read this brief, `AGENTS.md`,
> [project workflow facts](../docs/agents/project-workflow.md),
> [architecture guide](../docs/ARCHITECTURE.md), and [UI contract](../docs/ui.md)
> before editing. Work in a dedicated worktree. Follow the steps in order and
> run each verification command. On a STOP condition, stop and report; do not
> widen scope. Leave merge and push to the operator.

## Status

- **Priority**: P3
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none (Plans 082–086 merged)
- **Category**: dx (item 4: previews)
- **Planned at**: commit bc0522a, 2026-10-08
- **Integration**: main; merge and push require explicit operator authorization

## Execution profile

- **Recommended profile**: Fast/inline per slice
- **Risk/lane**: LOW
- **Parallelizable**: Yes, by folder (`Pages/MainMenu`, `Components/History`, `Components/WorkingTree`, `Components/Branches`, `Components/UsageQuota`)
- **Reviewer required**: No for preview-only slices; Yes if a slice changes a production initializer or view signature
- **Rationale**: After the MainMenu decomposition, sections take values and closures, so previews are cheap. `scripts/check-preview.sh --all` reports two files with no coverage, and most existing previews show one happy-path state. Dense Git surfaces regress in empty, error, long-name, and accessibility states that previews never render.
- **Escalate when**: A preview needs a new production protocol, a live Git repository, network, or Keychain access; or a view needs a signature change beyond adding a preview-only initializer default.

## Problem

- `scripts/check-preview.sh --all` fails on
  `Pages/MainMenu/MainMenuBranchSelectorOverlay.swift` and
  `Pages/MainMenu/MainMenuTransientOverlay.swift`.
- About 86 files declare SwiftUI views; most previews render one state.
- Accessibility behavior the app supports (Reduce Motion, Reduce
  Transparency, Increase Contrast, dark/light) is not visible in previews.

## Scope

1. **Close gaps.** Add `#Preview` (or a same-directory `*Preview.swift`
   companion, per `check-preview.sh`) for the two failing files.
2. **State matrices for dense surfaces**, one preview per meaningful state:
   - Working tree (`WorkingTreeSectionView`, `WorkingTreeDiffTreeViews`):
     empty, staged + unstaged, conflicts, very long paths, many files.
   - History (`HistorySidePanelView`, `CommitDetailPageView`,
     `ChangedFilesSummaryView`): empty, unpublished commits, long messages.
   - Branches (`BranchManagementModeContentViews`): worktrees, cleanup
     units (eligible/blocked/protected), error banner.
   - Side panel (`SidePanelCommitWorkspaceView`, `SidePanelBranchManagementView`):
     idle, busy (actions disabled), error.
   - Banners and command palette: each `InlineStatusBanner` style;
     palette with results, no results, disabled commands.
   - Usage quota (`UsageQuotaStripView`): normal, near limit, stale.
3. **Accessibility variants** on the three primary surfaces (working tree,
   side panel, command palette): dark and light, Increase Contrast
   (`.environment(\.colorSchemeContrast, .increased)`), Reduce Transparency,
   Dynamic Type at a large size.
4. **Sample data.** Extend `Support/PreviewDoubles.swift` with fixtures
   (files, commits, branches, worktrees, quota snapshots) shared by previews.
   Keep it `#if DEBUG`. No live Git, network, or Keychain.

Out of scope: snapshot or image-diff testing, visual changes, new UI, new
dependencies, previews for AppKit shell types (`StatusBarController`,
`MainWindowController`) and the full `MainMenuView`.

## Invariants

- Production behavior and visuals unchanged; preview code compiles only in DEBUG.
- No production protocol added for previews; prefer existing doubles and plain values.
- Previews render offline and deterministically (fixed dates, no randomness).

## Steps

1. Drift check: `git diff --stat <planned-commit>..HEAD -- GitMenuBar/Pages GitMenuBar/Components GitMenuBar/Support`.
2. Run `scripts/check-preview.sh --all`; record the failing list.
3. Slice 1: close the two gaps; `scripts/check-preview.sh --all` passes.
4. Slice 2: fixtures in `PreviewDoubles.swift`.
5. Slices 3+: state matrices per folder (one commit per folder).
6. Final slice: accessibility variants on the three primary surfaces.
7. Optional, operator decision: make `check-preview --all` part of
   `make lint` or `make validate`. Propose; do not change gates unasked.

## Verification

- `scripts/check-preview.sh --all` exits 0.
- `make build`, `make lint`, `make test`.
- Manual: open each new preview in Xcode Canvas; confirm it renders without
  crashing and shows the intended state. Record any preview that cannot render.

## STOP conditions

- A preview requires a production signature change beyond a defaulted parameter.
- A preview requires live Git, network, or Keychain.
- Canvas cannot render a view because of AppKit-only dependencies; record it and skip that view.
