# AGENTS.md

GitMenuBar: native macOS menu-bar app for day-to-day Git workflows; Swift 6
language mode, Swift 6.4 compiler.

Commands: [Makefile](Makefile) is canonical. Run `make guidance-check` after
changing plans, routing, or skill metadata.

Project facts for global skills live in this file and in the `docs/agents/` files linked below.

## Execution Policy

Every implementation plan must contain an `## Execution profile` section.

## Local routing

| Before | Read |
|---|---|
| Implementation, validation, or delivery | [Project workflow facts](docs/agents/project-workflow.md) |
| Review or retro | [Coding standards](CODING_STANDARDS.md), then the [project review profile](.agents/review-profiles/thermo-gitmenubar.md) |
| Changing animation or motion | [docs/agents/motion.md](docs/agents/motion.md) |
| Choosing or studying a reference app | [docs/agents/reference-apps.md](docs/agents/reference-apps.md) |
| Toolchain or concurrency questions | [ADR 0007](docs/adr/0007-swift-6-4-agent-baseline.md) |
