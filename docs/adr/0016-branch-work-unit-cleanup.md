# ADR 0016: Branch and worktree cleanup as one work unit

Status: Accepted
Date: 2026-09-07

## Context

Branch and worktree cleanup were presented as separate lists even though the
common operation is to remove the pair. The previous cleanup model also
treated ancestry as the only merge signal and excluded clean unmerged or
detached worktrees.

## Decision

- Model a local branch and its linked worktree as one cleanup unit in Side
  Panel Branch Health → Cleanup.
- Make the primary unit action remove the worktree first and then the branch.
- Offer branch-only and worktree-only actions from the unit ellipsis menu.
- Keep branch-only deletion unavailable while Git still has the branch checked
  out in a worktree; the user must remove that worktree first.
- Treat Git cherry-equivalent commits as merged for cleanup analysis.
- Allow clean unmerged branches and clean detached worktrees to be explicitly
  removed, with a risk review before unmerged branch deletion.
- Enumerate and delete remote-tracking branches from any configured remote,
  including `upstream`.

## Consequences

The cleanup list explains a complete unit of work instead of duplicating
branch/worktree rows. Unmerged branch deletion uses `git branch --force` only
after the UI confirmation and revalidates the branch hash, current branch, and
worktree state. Project Cleanup keeps its previous safe-only behavior.

## Rejected or deferred

- Automatically detaching a worktree to make branch-only deletion possible
  was rejected because it silently changes the worktree's checkout state.
- Force removal of dirty detached worktrees remains unavailable; the requested
  behavior covers clean detached worktrees.

## Affected surfaces

- `GitMenuBar/Components/Branches/BranchManagementModeContentViews.swift`
- `GitMenuBar/Pages/MainMenu/SidePanelBranchManagementView.swift`
- `GitMenuBar/Services/Git/GitCleanupRepository.swift`
- `GitMenuBar/Models/WorktreeCleanupModels.swift`
- [`docs/ui.md`](../ui.md)
