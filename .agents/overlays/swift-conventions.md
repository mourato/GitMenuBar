---
kind: project-overlay
extends: swift-conventions
project: GitMenuBar
precedence: project
---

# GitMenuBar Swift-conventions overlay

- Keep feature-specific UI near its owning feature and keep Git infrastructure
  out of view files; shared UI belongs in the shared layer only when reuse is
  established.
