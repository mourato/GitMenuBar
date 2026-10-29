# ADR 0022: Unified branch list and cleanup review

Status: Accepted
Date: 2026-10-29
Supersedes: the work-unit list part of the Branch Health cleanup contract
(the separate Cleanup list described in ADR 0016)

## Context

The Cleanup work-unit list ran beside the Branches list. A branch with a
worktree appeared in both, so the same object was listed twice. The list
truncated long branch sets, and its dense rows made cleanup state and branch
actions hard to scan.

## Decision

- Side Panel Branches shows one unified local branch list. Each local branch
  is one row, and its linked worktree shows as that row's status badge.
  Detached worktrees stay in the Worktrees section.
- Filter chips (All, Mergeable, Dirty, Stale) select one filter. The search
  field applies alongside the chip. Each chip carries its count.
- Stale means the last commit is more than 10 days old on a non-current local
  branch.
- A dirty worktree badge wins over the merged badge.
- A cleanup review banner shows `N ready to clean` and `M blocked`. Review
  opens `CleanupConfirmationView` with Ready and Blocked sections, a checked
  subset of ready units, and the existing risk-review step. With no ready
  units, Review is hidden and the banner states the blocked count.
- Row actions are `Clean <branch>` (safe unit cleanup), `Remove Worktree for
  <branch>` (worktree-only), and `Delete Branch` (branch-only). Branch-only
  deletion runs through the same sheet and risk gate. It is hidden while the
  branch is checked out in a worktree.
- The Worktrees section (footer toggle) offers Remove Worktree when the
  worktree-only unit is allowed, Reveal in Finder, Copy Path, and Force
  Remove Worktree for dirty linked worktrees.
- Cleanup execution semantics stay as defined in ADR 0016.

## Consequences

- Each branch appears once. Counts appear once: filter chips carry them, and
  section headers do not repeat them.
- Unmerged branch deletion always passes the risk-review step, including
  branch-only deletion from a row.
- Branches without a management unit keep the legacy Delete Branch
  confirmation.
- The sheet header still describes paired removal. Branch-only and
  worktree-only units need their own copy; that is follow-up work.
- Chips, the footer toggle, and banner and empty-state buttons use a 32-point
  hit area (`WorkbenchMetrics.minimumHitTarget`).

## Rejected or deferred

- Keeping the Cleanup list beside the unified list: duplicate rows and
  truncation remain.
- Counts on section headers beside filter chip counts: the same number shows
  twice.
- A disabled Review button when nothing is ready: hidden instead, per
  `docs/ui.md`.
- A configurable stale threshold: fixed at 10 days until a user need appears.

## Affected surfaces

- `GitMenuBar/Pages/MainMenu/SidePanelBranchManagementView.swift`
- `GitMenuBar/Components/Branches/BranchFilterChipsView.swift`
- `GitMenuBar/Components/Branches/BranchManagementRowView.swift`
- `GitMenuBar/Components/Branches/BranchManagementModeContentViews.swift`
- `GitMenuBar/Components/Branches/WorktreeManagementRowView.swift`
- `GitMenuBar/Components/Branches/CleanupConfirmationView.swift`
- `GitMenuBar/Models/BranchListModel.swift`
- `GitMenuBar/Models/WorktreeCleanupModels.swift`
- `GitMenuBar/Components/Common/WorkbenchMetrics.swift`
- `docs/ui.md`
