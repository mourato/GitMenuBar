---
kind: project-overlay
extends: code-quality
project: GitMenuBar
precedence: project
---

# GitMenuBar code-quality overlay

- Preserve clear ownership between Git services, menu-bar controllers,
  SwiftUI views, and AppKit adapters; do not move Git operations into views.
