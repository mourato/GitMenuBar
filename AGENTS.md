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
- `make lint-changed`
- `make lint-fix`
- `make agent-check`
- `make dmg`
- `make clean`
- `make setup`

## Execution Policy

- Prefer CLI-first verification and reproducible commands.
- Keep changes small and validated incrementally.
- Every implementation plan must contain an `## Execution profile` section with
  a recommended profile, risk/lane, parallelization decision, reviewer decision,
  rationale, and escalation condition. Re-evaluate that profile immediately
  before execution against the current diff and live scope; the live decision
  overrides stale plan text.
- Use `implementer-fast` only for deterministic, tightly bounded `Low/Fast`
  work. Use `implementer` for ambiguous, `Medium`, or `High` work. Add a
  reviewer for high-risk architecture, security, persistence, concurrency, or
  release work.
- Root-only execution is the default for simple, serial, or narrow-diff work.
  For broad independent work, start with at most one read-only explorer, then
  use one writer in one isolated worktree. Do not use mixed orchestration by
  default, and never allow more than one writer.
- Model identifiers belong only in global Codex configuration or custom agent
  files; do not put them in this repository's skills, plans, or documentation.
- When working from a branch, PR, or local diff, inspect the touched files first and treat lint findings in modified code as mandatory work for the same change.
- Resolve critical lint violations in the diff before running full-project verification; do not defer issues introduced or exposed by the current change.
- During implementation, prefer `make agent-check` for changed Swift lint plus a Debug build.
- Before merge, run: `make lint && make test`.
  Lint runs first — it is cheap and fails fast. The `make test` command already compiles the project via `build-for-testing`, so a separate `make build` is redundant.
- Tests are not required before every commit by default. Run targeted tests when behavior changes and the full test gate before merge/push.
- When UI/logic/assets become unused, sanitize in the same PR: remove orphan files, dead helpers, and stale resources safely.
- Treat code sanitization as mandatory maintenance, not optional cleanup; include objective evidence (`rg`, target wiring, runtime path) for each removal.

## SwiftUI Preview Policy

- Any new Swift file that renders interface (`View`, `NSViewRepresentable`, `NSViewControllerRepresentable`) must include at least one `#Preview`.
- Previews can live in the same file or a dedicated `*Preview.swift` companion file, but every UI-rendering file must be covered.
- Pull requests that introduce UI files without preview coverage are incomplete.

## Skills

Choose the narrowest relevant skill from its description. Keep routing policy
in this file and domain-specific guidance in the owning skill.

Global skills are referenced with the `global:<name>` form and must not be
copied into `.agents/skills/`. The canonical global routes are:

- `global:improve` for read-only audits and implementation plans
- `global:thermo-nuclear-code-quality-review` for strict reviews

`delivery-workflow` owns risk lanes, validation, gates, and Git mechanics.
Domain skills own GitMenuBar technical invariants. The project-only review
profile at `.agents/review-profiles/thermo-gitmenubar.md` adds only this
repository's rules to the global thermo review.

Primary skills in this repo:

- `delivery-workflow`
- `apple-design`
- `macos-app-engineering`
- `menubar`
- `swift-conventions`
- `code-quality`
- `thermo-nuclear-code-quality-review`

Run `make guidance-check` after changing plans, routing, or skill metadata. It
validates required execution profiles, local structure, global references, and
Markdown links without treating global references as local files.
