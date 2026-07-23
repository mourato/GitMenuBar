---
kind: project-overlay
extends: accessibility-audit
project: GitMenuBar
precedence: project
---

# GitMenuBar accessibility overlay

- Treat the status item, repository picker, branch lists, working-tree rows,
  history actions, command palette, and settings panes as primary surfaces.
- Branch, file, repository, and worktree-cleanup actions use labels that name
  the affected GitMenuBar object.
- GitMenuBar popovers and transient actions preserve predictable outside-click,
  focus, and `Esc` dismissal across repository and branch workflows.
