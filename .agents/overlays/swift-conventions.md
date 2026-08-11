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
- Use Swift 6 language mode with the Swift 6.4 compiler baseline in
  `docs/adr/0007-swift-6-4-agent-baseline.md`; run SwiftFormat against the app,
  tests, and companion CLI.
