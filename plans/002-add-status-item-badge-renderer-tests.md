# Plan 002: Add status item badge renderer tests

> Executor instructions: follow the steps, run every verification command, and stop on drift. Include a code review step before committing.
>
> Drift check: `git diff --stat dbdd40e..HEAD -- GitMenuBar/App GitMenuBarTests`

## Status

- Priority: P1
- Effort: S
- Risk: LOW
- Depends on: none
- Category: tests
- Planned at: commit `dbdd40e`, 2026-07-02

## Why this matters

The Thermo Nuclear app-shell review extracted status badge drawing from `StatusBarController` into `StatusItemBadgeRenderer`. That brought the controller under 1k lines and isolated drawing logic, but the renderer has no direct regression coverage. Add focused tests for the extracted behavior so badge rendering remains stable.

## Current state

- `GitMenuBar/App/StatusItemBadgeRenderer.swift` owns base icon creation and badged-image drawing.
- `GitMenuBar/App/StatusBarController.swift` calls the renderer from the status item lifecycle.
- There are no renderer-specific tests in `GitMenuBarTests/`.

## Scope

In scope:
- `GitMenuBar/App/StatusItemBadgeRenderer.swift`
- `GitMenuBarTests/StatusItemBadgeRendererTests.swift`

Out of scope:
- Manual menu bar launch testing.
- Status item click/window behavior.

## Steps

1. Add tests that create a simple template `NSImage` and call `makeBadgedImage(count:baseStatusImage:iconSize:)`.
2. Assert the returned image preserves the expected size and is non-template, including the `99+` path for counts above 99.
3. Add a test that `makeBadgedImage` returns nil when no base image is available.
4. Code review step: inspect the diff and confirm no AppKit lifecycle or status item ownership moved.

## Verification

- `xcodebuild test -project GitMenuBar.xcodeproj -scheme GitMenuBar -only-testing:GitMenuBarTests/StatusItemBadgeRendererTests -derivedDataPath .xcode-build-tests` exits 0.
- `make build` exits 0.
- `make lint` exits 0.

## STOP conditions

- If headless AppKit image rendering fails on this machine, stop and report.
- If tests require launching the app or creating a real `NSStatusItem`, stop and report.
