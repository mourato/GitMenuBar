---
kind: project-overlay
extends: delivery-workflow
project: GitMenuBar
precedence: project
---

# GitMenuBar delivery overlay

- `make build` runs `scripts/run-build.sh`; `make build-release` runs it with
  `--configuration Release`.
- `make test` runs `scripts/run-tests-xcode.sh`; `make lint` runs
  `scripts/lint.sh`; `make lint-changed` and `make lint-fix` use their matching
  scripts; `make agent-check` combines changed-file lint and a Debug build.
- `make validate` is the canonical changed-surface entry and delegates to
  `make agent-check`.
- `make guidance-check` runs `scripts/validate-agent-guidance.sh` for plans,
  routing, overlays, and skill metadata.
- The Swift 6.4 baseline requires strict full lint (`make lint`) and changed
  lint/build feedback (`make agent-check`); see ADR 0007.
- Debug and release build logs are `/tmp/gitmenubar-build-debug.log` and
  `/tmp/gitmenubar-build-release.log`; test logs are `/tmp/gitmenubar-test.log`.
- Before merge/push, run `git diff --check`, `make guidance-check`,
  `make lint`, and `make test`.
- Preserve unrelated changes and never delete `main`, unmerged branches, or
  worktrees containing other work. Use one isolated writer worktree.
- Follow the global `core/policies/worktrees.md` lifecycle:
  `create → work → commit → review → remediation → merge → validate → push →
  cleanup`. This overlay supplies commands only; cleanup waits until a
  successful push and remains separately authorized.
