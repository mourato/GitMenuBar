# ADR 0020: Repository actions in the toolbar and a plain history list

Status: Accepted
Date: 2026-10-28

## Context

The main window put Commit and Sync inside the Working Tree card. The branch
picker sat in a footer below the history. The toolbar held only the sidebar
toggle and Back. The history drew a vertical line through the commit dots.
That line looked like a commit graph but always drew one straight column, even
for merges. The result spread primary actions across three places and showed
decoration that looked like data.

## Decision

- The unified toolbar owns the repository-level actions: the branch picker,
  the ahead/behind indicator, Fetch, Sync, and Commit. This replaces the rule
  in `docs/ui.md` that the toolbar keeps only route-specific controls.
- Commit shows the change count and opens the existing Working Tree side panel.
  The commit composer stays in the side panel.
- Sync appears only when the branch is ahead or behind. Fetch is always
  available.
- The branch footer is removed. The branch picker uses the existing branch
  selector overlay.
- The history is a plain list without a connecting line. A dot marks state:
  filled accent for the selection, outline for an ordinary commit, smaller and
  dimmed for a merge commit (`Commit.isMergeCommit`).

## Alternatives

- A real commit graph with one column per branch and merge curves. Rejected:
  it needs parent topology layout, custom drawing, and performance work for
  large histories. GitMenuBar is a daily-workflow tool, not a topology
  explorer.
- Keep the actions in the card. Rejected: the card mixed one action surface
  with two status surfaces, and the disabled Sync button looked broken.

## Consequences

- `MainWindowToolbarController` grows items and needs state updates from the
  selected repository.
- The overview becomes status only.
- Keyboard shortcuts and command palette entries for these actions keep
  working and do not depend on the toolbar.
