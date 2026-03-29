---
name: build-macos-apps
description: Build, test, lint, and packaging reproduction workflow for GitMenuBar, including script entrypoints and log locations.
---

# Build macOS Apps

Use this skill when the task is to reproduce a failure, route a build command, or inspect packaging artifacts.

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

## Triage Flow

1. Reproduce with the narrowest `make` target that matches the failure.
2. Inspect the owning script in `scripts/` before guessing at Xcode behavior.
3. Read the generated log and surface the first actionable failure, not the last cascade.
4. Only escalate to broader verification after the narrow reproduction is stable.

## Notes

- This skill is for reproduction and routing, not release sign-off.
- If the task is about verification depth or merge readiness, use `quality-assurance`.
