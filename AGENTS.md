# AGENTS.md - GitMenuBar Development Guide

## Identity

GitMenuBar is a native macOS menu bar app for day-to-day Git workflows.

## Core Values & Precedence

1. **Performance** and **Reliability** first.
2. Keep **behavior predictable** under load and during failures.
3. **Safety** — memory safety, data integrity, security first
4. **Completeness** — feature-complete, no silent failures
5. **Helpfulness** — clear guidance, actionable advice

If a tradeoff is required, choose **correctness and robustness** over short-term convenience.

## Command Surface

- `make build`
- `make build-release`
- `make test`
- `make lint`
- `make lint-fix`
- `make dmg`
- `make clean`
- `make setup`

## Execution Policy

- Prefer CLI-first verification and reproducible commands.
- Keep changes small and validated incrementally.
- When working from a branch, PR, or local diff, inspect the touched files first and treat lint findings in modified code as mandatory work for the same change.
- Resolve critical lint violations in the diff before running full-project verification; do not defer issues introduced or exposed by the current change.
- Before merge, run: `make build && make test && make lint`.
- When UI/logic/assets become unused, sanitize in the same PR: remove orphan files, dead helpers, and stale resources safely.
- Treat code sanitization as mandatory maintenance, not optional cleanup; include objective evidence (`rg`, target wiring, runtime path) for each removal.

## SwiftUI Preview Policy

- Any new Swift file that renders interface (`View`, `NSViewRepresentable`, `NSViewControllerRepresentable`) must include at least one `#Preview`.
- Previews can live in the same file or a dedicated `*Preview.swift` companion file, but every UI-rendering file must be covered.
- Pull requests that introduce UI files without preview coverage are incomplete.

## Skills

Use `.agents/SKILLS_INDEX.md` as the local skill registry.

Primary skills in this repo:

- `build-macos-apps`
- `quality-assurance`
- `macos-development`
- `menubar`
- `swift-conventions`
- `code-quality`
