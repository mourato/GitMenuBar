---
name: delivery-workflow
description: Delivery, verification, command routing, git evidence, and merge-readiness workflow for GitMenuBar changes.
---

# Delivery Workflow

## When to Use

Use this skill when the task involves reproducing a build/test/lint failure, routing a command, defining verification scope, or assessing merge readiness.

## Command Routing

- `make build`: Debug build through `scripts/run-build.sh`
- `make build-release`: Release build through `scripts/run-build.sh --configuration Release`
- `make test`: XCTest flow through `scripts/run-tests-xcode.sh`
- `make lint`: SwiftFormat + SwiftLint checks through `scripts/lint.sh`
- `make lint-fix`: auto-fix pass through `scripts/lint-fix.sh`
- `make dmg`: Release build plus DMG packaging through `scripts/create-dmg.sh`

## Log Locations

- Debug/Release build failures: `/tmp/gitmenubar-build-debug.log` or `/tmp/gitmenubar-build-release.log`
- Test failures: `/tmp/gitmenubar-test.log`

## Validation Scope

### Merge Gate

Minimum before merge: `make build && make test && make lint`

### Scope Matrix

- Pure refactor with unchanged behavior: run the merge gate and target affected tests.
- Git logic, parsing, or persistence changed: add or update regression tests.
- Menu bar or window behavior changed: manually verify status item, activation, dismissal, and repo/branch actions.
- Credentials or AI provider flows changed: include secure-storage and migration checks.
- Packaging changed: run `make build-release`, `make dmg`, and validate the DMG manually.

## Triage Flow

1. Reproduce with the narrowest `make` target that matches the failure.
2. Inspect the owning script in `scripts/` before guessing at Xcode behavior.
3. Read the generated log and surface the first actionable failure, not the last cascade.
4. Only escalate to broader verification after the narrow reproduction is stable.

## Manual Sign-Off Focus

- Opening the app from the menu bar
- Switching repositories
- Branch actions
- Commit flow and sync flow
- Settings and account panes when touched

## Git and Evidence

- Keep checks deterministic and CLI-first where possible.
- Validation should match the blast radius of the change; do not stop at the global gate when the risk is higher.
- When UI/logic/assets become unused, sanitize in the same PR: remove orphan files, dead helpers, and stale resources safely.
- Include objective evidence (`rg`, target wiring, runtime path) for each removal.

## Boundaries

- This skill owns delivery mechanics and merge readiness.
- Release publication and DMG readiness beyond command routing belong to `release-management`.
- Test design details belong to `test-strategy`.
- Menu-bar lifecycle behavior belongs to `menubar`.
- Code structure feedback belongs to `code-quality` and `thermo-nuclear-code-quality-review`.
- Application source changes, Xcode project files, and packaging scripts are not owned here.
