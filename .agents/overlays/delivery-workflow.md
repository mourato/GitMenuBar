---
kind: project-overlay
extends: delivery-workflow
project: GitMenuBar
precedence: project
---

# GitMenuBar delivery overlay

- Run `make guidance-check` for plans, routing, overlays, or skill metadata.
- Before merge/push, run `git diff --check`, `make lint`, and `make test`.
  Guidance-only changes still use the normal project gate.
- Preserve unrelated changes and never delete `main`, unmerged branches, or
  worktrees containing other work. Use one isolated writer worktree.
- Delivery is isolated branch → review → commit → push/PR → approved merge;
  branch and worktree cleanup waits until the PR is merged.
