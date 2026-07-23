---
kind: project-overlay
extends: menubar
project: GitMenuBar
precedence: project
---

# GitMenuBar menu-bar overlay

- GitMenuBar has one explicit `NSStatusItem` owner; opening it must not create
  duplicate controllers, work, or stale repository state.
- Left-click, right-click, modifier-click, activation policy, and settings
  entry points must remain intentional and consistent.
- Verify outside-click, focus-change, and `Esc` dismissal, then close and
  reopen after branch, repository, sync, or cleanup actions.
- The app remains menu-bar style: no unexpected Dock presence or orphaned
  windows/popovers.
