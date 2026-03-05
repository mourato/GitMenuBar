---
name: quality-assurance
description: Verification policy and merge gates for GitMenuBar.
---

# Quality Assurance

## Core Gate
- Minimum gate before merge: `make build && make test && make lint`

## Scope-based checks
- UI/menu bar behavior changed: manually verify status-item interaction, popover, and branch/repo actions.
- Packaging changed: run `make dmg` and mount DMG.

## Notes
- Keep checks deterministic and CLI-first.
- Prefer small, isolated changes with verification after each slice.
