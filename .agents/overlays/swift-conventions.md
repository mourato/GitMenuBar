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
- Preserve the repository's `make lint` and `make lint-fix` tooling and the
  required `#Preview` coverage for UI-rendering files.
- This overlay does not authorize Swift edits for Plan 021; source, tests, and
  Xcode files remain unchanged.
