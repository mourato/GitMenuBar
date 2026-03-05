# AGENTS.md - GitMenuBar Development Guide

## Identity
GitMenuBar is a native macOS menu bar app for day-to-day Git workflows.

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
