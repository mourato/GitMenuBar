---
kind: project-overlay
extends: macos-app-engineering
project: GitMenuBar
precedence: project
---

# GitMenuBar macOS app-engineering overlay

- GitMenuBar is a native macOS menu-bar app with status-item-driven popovers,
  repository and branch workflows, settings, and worktree cleanup surfaces.
- Keep lifecycle and UI ownership explicit; `menubar` owns status-item,
  activation, popover dismissal, and menu-bar invariants.
- Repository, branch, settings, and worktree-cleanup surfaces remain within
  their existing feature ownership boundaries.
