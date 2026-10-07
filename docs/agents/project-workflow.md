# Project workflow facts

Read before implementation, validation, or delivery. Paths below name repository-root facts; links resolve from this document. Shared project conventions (UI contract, reference apps, lint baseline, `validate-lane`) live in `${AGENT_CONFIG_HOME:-$HOME/.agents}/core/policies/project-context.md`.

## Identity

GitMenuBar is a native macOS menu bar app for day-to-day Git workflows.

## Command Surface

`make validate` delegates to `agent-check`; `make validate-lane` supports `VALIDATE_BASE` (default merge-base `origin/main HEAD`) and `VALIDATE_TARGET=test-focused TEST_FILTER=...`. Run root: ignored `.xcode-build/validate-lane.*`; watch `Build/` and remove run root. Focused tests: `make test-focused TEST_FILTER='GitMenuBarTests/Name'`; UI: `make check-preview`; pre-merge: `make lint` and `make test`.

The Swift 6.4 toolchain and concurrency baseline is documented in
[`docs/adr/0007-swift-6-4-agent-baseline.md`](../../docs/adr/0007-swift-6-4-agent-baseline.md).
`make agent-check` is fast changed-scope feedback; full lint/build/test are the
merge gate.

## UI invariants

GitMenuBar is a menu-bar Git workflow app; favor calm, direct feedback in
compact popovers, panels, repository pickers, and branch/worktree surfaces.
Keep popover and panel transitions anchored to their status-item or action
origin and avoid layout churn in dense Git lists.
Do not use ellipses in visible interface labels. Actions that open another
panel, popover, sheet, or confirmation should be clear from placement,
grouping, iconography, or helper text instead of a trailing three-dot suffix.
GitMenuBar has one `NSStatusItem` owner; preserve intentional left-click,
right-click, modifier-click, activation-policy, settings, outside-click,
focus-change, and `Esc` dismissal behavior without orphaned windows or
duplicate controllers. Repository, branch, settings, and worktree-cleanup
surfaces remain within their existing feature ownership boundaries.
Before changing animation or motion, read [docs/agents/motion.md](../../docs/agents/motion.md).

## Code ownership

Preserve clear ownership between Git services, menu-bar controllers,
SwiftUI views, and AppKit adapters; do not move Git operations into views.
Keep feature-specific UI near its owning feature and keep Git infrastructure
out of view files; shared UI belongs in the shared layer only when reuse is
established. Use Swift 6 language mode with the Swift 6.4 compiler baseline in
`docs/adr/0007-swift-6-4-agent-baseline.md`; run SwiftFormat against the app,
tests, and companion CLI.

## Accessibility invariants

Treat the status item, repository picker, branch lists, working-tree rows,
history actions, command palette, and settings panes as primary surfaces.
Branch, file, repository, and worktree-cleanup actions use labels that name
the affected GitMenuBar object. Popovers and transient actions preserve
predictable outside-click, focus, and `Esc` dismissal across repository and
branch workflows. Preserve status, selection, focus, and completion feedback
when Reduce Motion is enabled; motion must remain supplemental to keyboard and
VoiceOver cues.

## Delivery commands

`make build` runs `scripts/run-build.sh`; `make build-release` runs it with
`--configuration Release`. `make test` runs `scripts/run-tests-xcode.sh`;
pass `TEST_FILTER='GitMenuBarTests/Name'` for one XCTest target, or use
`make test-focused TEST_FILTER='GitMenuBarTests/Name'`. `make lint` runs
`scripts/lint.sh`; `make lint-changed` and `make lint-fix` use their matching
scripts. Debug and release build logs are `/tmp/gitmenubar-build-debug.log`
and `/tmp/gitmenubar-build-release.log`; test logs are
`/tmp/gitmenubar-test.log`. Before merge/push, run `git diff --check`,
`make guidance-check`, `make lint`, and `make test`. Never delete `main`,
unmerged branches, or worktrees containing other work.

## SwiftUI Preview Policy

- Run `make check-preview` before closing UI work. It checks changed Swift UI candidates under `GitMenuBar/Components` and `GitMenuBar/Pages`; use `./scripts/check-preview.sh --all` for a full project audit.
- Main-window previews must mirror the transparent full-size titlebar setup. Use `MainMenuPreviewHarness(showsTransparentTitlebar: true)` for previews that render `MainMenuView`, main menu chrome, or other top-of-window surfaces so header controls do not overlap the macOS traffic-light area.
- Component-only previews should not simulate the full window/titlebar unless they render main-window chrome.
