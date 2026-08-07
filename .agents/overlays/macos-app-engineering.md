---
kind: project-overlay
extends: macos-app-engineering
project: GitMenuBar
precedence: project
---

# GitMenuBar macOS app-engineering overlay

- GitMenuBar is a native macOS menu-bar app with status-item-driven popovers,
  repository and branch workflows, settings, and worktree cleanup surfaces.
- Keep lifecycle and UI ownership explicit. GitMenuBar has one `NSStatusItem`
  owner; preserve intentional left-click, right-click, modifier-click,
  activation-policy, settings, outside-click, focus-change, and `Esc`
  dismissal behavior without orphaned windows or duplicate controllers.
- Repository, branch, settings, and worktree-cleanup surfaces remain within
  their existing feature ownership boundaries.
