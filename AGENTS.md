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
- Before merge, run: `make build && make test && make lint`.

## Skills

Use `.agents/SKILLS_INDEX.md` as the local skill registry.

Primary skills in this repo:

- `build-macos-apps`
- `quality-assurance`
- `macos-development`
- `menubar`
- `swift-conventions`
- `code-quality`
