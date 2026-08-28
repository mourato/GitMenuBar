# AGENTS.md - GitMenuBar Development Guide

## Identity

GitMenuBar is a native macOS menu bar app for day-to-day Git workflows.

## Command Surface

`Makefile` is the command authority. Use `make validate` as the canonical
changed-surface entry (it delegates to `agent-check`), `make check-preview` for
UI work, and `make lint && make test` before merge.

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
Use global `agent-ops` for delegation and profile selection; re-evaluate the
profile against the live diff before execution. Use
`delivery-workflow` for risk, lanes, validation, and Git.

Use CLI-first verification and keep checks scoped to the touched surface.

When behavior changes, run focused tests; the full test gate belongs before
merge. Remove orphaned UI, logic, and assets in the same change when their
runtime path is demonstrably gone.

## Delivery lifecycle

The global `core/policies/worktrees.md` is authoritative for isolation and
delivery order. Follow `create → work → commit → review → remediation → merge
→ validate → push → cleanup`; this file and the project overlay supply
GitMenuBar facts and commands only. Never merge, push, or clean up from an
implementation worktree without explicit authorization.

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
- Behavior changes pass `make test` and `make validate`; UI changes also pass `make check-preview`.
- Before merge, `make lint && make test` passes.
- The handoff records commands and results, assumptions, screenshots for UI changes, and known baseline failures.

## Skills

Global skill routing is defined by the global agent configuration. Use global
routes and load the matching project overlay after its global skill.

Choose the narrowest global skill, then load its matching project overlay and
any local specialist skill. The project-only review profile is
`.agents/review-profiles/thermo-gitmenubar.md`; overlays and local skills own
GitMenuBar-specific invariants.

Run `make guidance-check` after changing plans, routing, or skill metadata. It
validates required execution profiles, local structure, global references, and
Markdown links without treating global references as local files.
