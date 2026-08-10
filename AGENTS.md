# AGENTS.md - GitMenuBar Development Guide

## Identity

GitMenuBar is a native macOS menu bar app for day-to-day Git workflows.

## Command Surface

`Makefile` is the command authority. Use `make agent-check` during
implementation, `make check-preview` for UI work, and `make lint && make test`
before merge.

## UI design gate

Before changing native UI, read [`.interface-design/system.md`](.interface-design/system.md).
It is the canonical active design contract for visual hierarchy, Workbench
tokens, scroll ownership, motion, accessibility, and surface exclusions. When
an interface change intentionally changes a locked decision, update that
system document and record the rationale in the relevant ADR before shipping.

## Execution Policy

Every implementation plan must contain an `## Execution profile` section.
Use global `agent-ops` for delegation and profile selection; re-evaluate the
profile against the live diff before execution. Use
`delivery-workflow` for risk, lanes, validation, and Git.

Use CLI-first verification and keep checks scoped to the touched surface. Use
global `agent-ops` for delegation and execution profiles, and
`delivery-workflow` for risk, lanes, validation, and Git. Re-evaluate any plan
profile against the live diff before execution.

When behavior changes, run focused tests; the full test gate belongs before
merge. Remove orphaned UI, logic, and assets in the same change when their
runtime path is demonstrably gone.

## SwiftUI Preview Policy

- Any new Swift file that renders interface (`View`, `NSViewRepresentable`, `NSViewControllerRepresentable`) must include at least one `#Preview`.
- Previews can live in the same file or a dedicated `*Preview.swift` companion file, but every UI-rendering file must be covered.
- Preview companions should live in the same directory as the rendered view and reference at least one view type from the covered source file.
- Run `make check-preview` before closing UI work. It checks changed Swift UI candidates under `GitMenuBar/Components` and `GitMenuBar/Pages`; use `./scripts/check-preview.sh --all` for a full project audit.
- Main-window previews must mirror the transparent full-size titlebar setup. Use `MainMenuPreviewHarness(showsTransparentTitlebar: true)` for previews that render `MainMenuView`, main menu chrome, or other top-of-window surfaces so header controls do not overlap the macOS traffic-light area.
- Component-only previews should not simulate the full window/titlebar unless they render main-window chrome.
- Pull requests that introduce UI files without preview coverage are incomplete.

## Completion

A task is complete when:

- The changed surface, risk/lane, and `reuse → extend → create` decision are recorded.
- Behavior changes pass `make test` and `make agent-check`; UI changes also pass `make check-preview`.
- Before merge, `make lint && make test` passes.
- The handoff records commands and results, assumptions, screenshots for UI changes, and known baseline failures.

## Skills

Choose the narrowest relevant skill. Global skills use the `global:<name>`
form and must not be copied into `.agents/skills/`. For overlay-backed skills,
load the global core, then `.agents/overlays/<skill-name>.md`, then any local
specialist skill. The project-only review profile is
`.agents/review-profiles/thermo-gitmenubar.md`.

Routes:

- `global:swiftui-accessibility-audit` + `.agents/overlays/swiftui-accessibility-audit.md`
- `global:apple-design` + `.agents/overlays/apple-design.md`
- `global:benchmarking` + `.agents/overlays/benchmarking.md`
- `global:code-quality` + `.agents/overlays/code-quality.md`
- `global:delivery-workflow` + `.agents/overlays/delivery-workflow.md`
- `global:macos-app-engineering` + `.agents/overlays/macos-app-engineering.md`
- `global:swift-conventions` + `.agents/overlays/swift-conventions.md`

Use `global:improve` for audits and plans and
`global:thermo-nuclear-code-quality-review` for strict reviews. Overlays and
local skills own GitMenuBar-specific invariants.

Run `make guidance-check` after changing plans, routing, or skill metadata. It
validates required execution profiles, local structure, global references, and
Markdown links without treating global references as local files.
