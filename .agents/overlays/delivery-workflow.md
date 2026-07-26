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
- `make install-cli` symlinks the app bundle’s `gitmenubar` to `~/.local/bin`
  (see `scripts/install-cli.sh`). Settings → AI → **Install CLI** runs the same
  install path for the running app.
- **Companion CLI (Soft dependency)** — when an agent commits on user request
  (ADR 0003; handoff: `docs/companion-cli-agent-soft-dep.md`):
  1. If `command -v gitmenubar` and the CLI is ready → Propose with
     `gitmenubar message|commit|atomic`; use `--apply` only when the user asked
     to commit.
  2. If the CLI is missing or not ready → fall back to plain `git` and an
     agent-authored message; mention `make install-cli` or Settings install.
  3. If the CLI is ready but AI/Message policy fails → **fail closed** (no
     harness-invented commit message); do not `--apply`.
  Surfaces: global `ship-ship`, `delivery-workflow`, and Cursor commit-on-request
  rules (paste from the handoff doc; do not hard-require CLI in CI).
- Before merge/push, run `git diff --check`, `make guidance-check`,
  `make lint`, and `make test`.
- Preserve unrelated changes and never delete `main`, unmerged branches, or
  worktrees containing other work. Use one isolated writer worktree.
- Delivery is isolated branch → review → commit → push/PR → approved merge;
  branch and worktree cleanup waits until the PR is merged.
