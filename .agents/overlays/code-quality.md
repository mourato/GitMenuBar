---
kind: project-overlay
extends: code-quality
project: GitMenuBar
precedence: project
---

# GitMenuBar code-quality overlay

- Preserve clear ownership between Git services, menu-bar controllers,
  SwiftUI views, and AppKit adapters; do not move Git operations into views.
- When guidance changes remove a duplicate or stale skill, prove that the
  replacement overlay/reference exists and that specialist skills remain.
- Keep this migration guidance-only: Swift source, Xcode settings, assets,
  tests, and runtime behavior are outside its scope.
