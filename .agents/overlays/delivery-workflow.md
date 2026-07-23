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
- `make guidance-check` runs `scripts/validate-agent-guidance.sh` for plans,
  routing, overlays, and skill metadata.
- Debug and release build logs are `/tmp/gitmenubar-build-debug.log` and
  `/tmp/gitmenubar-build-release.log`; test logs are `/tmp/gitmenubar-test.log`.
- Before merge/push, run `git diff --check`, `make guidance-check`,
  `make lint`, and `make test`.
- Preserve unrelated changes and never delete `main`, unmerged branches, or
  worktrees containing other work. Use one isolated writer worktree.
- Delivery is isolated branch → review → commit → push/PR → approved merge;
  branch and worktree cleanup waits until the PR is merged.
