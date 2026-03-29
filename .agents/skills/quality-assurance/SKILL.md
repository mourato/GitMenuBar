---
name: quality-assurance
description: Verification policy and scope-based sign-off guidance for GitMenuBar changes.
---

# Quality Assurance

Use this skill to decide how much verification is required for a change.

## Merge Gate

- Minimum before merge: `make build && make test && make lint`

## Scope Matrix

- Pure refactor with unchanged behavior: run the merge gate and target affected tests.
- Git logic, parsing, or persistence changed: add or update regression tests.
- Menu bar or window behavior changed: manually verify status item, activation, dismissal, and repo/branch actions.
- Credentials or AI provider flows changed: include secure-storage and migration checks.
- Packaging changed: run `make build-release`, `make dmg`, and validate the DMG manually.

## Manual Sign-Off Focus

- Opening the app from the menu bar
- Switching repositories
- Branch actions
- Commit flow and sync flow
- Settings and account panes when touched

## Notes

- Keep checks deterministic and CLI-first where possible.
- Validation should match the blast radius of the change; do not stop at the global gate when the risk is higher.
