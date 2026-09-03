# AGENTS.md - GitMenuBar Development Guide

## Identity

GitMenuBar is a native macOS menu bar app for day-to-day Git workflows.

## Command Surface

`Makefile` is the command authority. Use `make validate` as the native
changed-surface entry (it delegates to `agent-check`), and
`make validate-lane` for the global baseline/artifact wrapper. It defaults to
`git merge-base origin/main HEAD`, accepts `VALIDATE_BASE=...`, and can wrap a
focused test with `VALIDATE_TARGET=test-focused TEST_FILTER=...`. The lane uses
a unique ignored `.xcode-build/validate-lane.*` DerivedData root, watches its
`Build/` output, and removes the run root before returning. Use
`make test-focused TEST_FILTER='GitMenuBarTests/Name'` for one XCTest target,
`make check-preview` for UI work, and `make lint && make test` before merge.

The Swift 6.4 toolchain and concurrency baseline is documented in
[`docs/adr/0007-swift-6-4-agent-baseline.md`](docs/adr/0007-swift-6-4-agent-baseline.md).
`make agent-check` is fast changed-scope feedback; full lint/build/test are the
merge gate.

## UI design gate

Before changing native UI, read [`docs/ui.md`](docs/ui.md).
It is the canonical active design contract for visual hierarchy, Workbench
tokens, scroll ownership, motion, accessibility, and surface exclusions. When
an interface change intentionally changes a locked decision, update that
system document and record the rationale in the relevant ADR before shipping.

## Execution Policy

Every implementation plan must contain an `## Execution profile` section.
Use `delivery-workflow` for risk, lanes, validation, and Git.

## SwiftUI Preview Policy

- Any new Swift file that renders interface (`View`, `NSViewRepresentable`, `NSViewControllerRepresentable`) must include at least one `#Preview`.
- Previews can live in the same file or a dedicated `*Preview.swift` companion file, but every UI-rendering file must be covered.
- Preview companions should live in the same directory as the rendered view and reference at least one view type from the covered source file.
- Run `make check-preview` before closing UI work. It checks changed Swift UI candidates under `GitMenuBar/Components` and `GitMenuBar/Pages`; use `./scripts/check-preview.sh --all` for a full project audit.
- Main-window previews must mirror the transparent full-size titlebar setup. Use `MainMenuPreviewHarness(showsTransparentTitlebar: true)` for previews that render `MainMenuView`, main menu chrome, or other top-of-window surfaces so header controls do not overlap the macOS traffic-light area.
- Component-only previews should not simulate the full window/titlebar unless they render main-window chrome.
- Pull requests that introduce UI files without preview coverage are incomplete.

## Local routing

Global skill routing is defined by the global agent configuration. Use global
routes and load the matching project overlay after its global skill.

The project-only review profile is
`.agents/review-profiles/thermo-gitmenubar.md`; overlays and local skills own
GitMenuBar-specific invariants. Run `make guidance-check` after changing plans,
routing, or skill metadata.
