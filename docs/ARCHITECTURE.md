# GitMenuBar Architecture and Naming Guide

This document defines how UI code is organized to keep AI-assisted edits and Xcode Canvas previews fast and predictable.

## Folder Conventions

- `GitMenuBar/Features/`: feature-specific UI and view composition.
- `GitMenuBar/Shared/UI/`: reusable UI components shared by multiple features.
- Root `GitMenuBar/`: app bootstrap, platform services, managers, and non-feature infrastructure.

Current feature folders:

- `Features/MainMenu`
- `Features/Settings`
- `Features/Branches`
- `Features/Projects`
- `Features/CreateRepository`

## Naming Conventions

- Prefer semi-explicit names inside a feature folder.
- Keep the feature context in the filename when helpful: `MainMenuContent.swift`, `MainMenuActions.swift`.
- For local feature components, shorter names are acceptable when folder context is obvious.
- Avoid creating long prefix chains like `MainMenuView+Something+Else.swift`.

## Preview Conventions

- Keep `#Preview` blocks in the same file as the view whenever practical.
- Keep feature preview harnesses near the feature (`Features/MainMenu/MainMenuPreviewHarness.swift`).
- For shared components, include focused previews with realistic sample data.

## Where New UI Should Go

Use this rule order:

1. If the UI is used in exactly one feature, place it in that feature folder.
2. If the UI is reused by multiple features, move it to `Shared/UI`.
3. If the code is not UI (Git operations, API, persistence, app lifecycle), keep it at the root infrastructure layer.

## Change Strategy

- Keep file moves and behavioral changes in separate commits when possible.
- Validate each slice with `make build && make test`.
- Before merge, run `make build && make test && make lint`.
