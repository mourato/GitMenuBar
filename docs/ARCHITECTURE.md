# GitMenuBar Architecture and Naming Guide

This document defines how UI code is organized to keep AI-assisted edits and Xcode Canvas previews fast and predictable.

## Folder Conventions

- `GitMenuBar/App/`: app bootstrap, AppKit shell (`StatusBarController`,
  `MainWindowController`), command routing, and coordinators.
- `GitMenuBar/Pages/`: top-level routes and their composition, one folder per
  page (`MainMenu`, `Settings`, `CreateRepository`).
- `GitMenuBar/Components/<Feature>/`: feature UI used by pages (`AI`,
  `Branches`, `History`, `Projects`, `Settings`, `UsageQuota`, `WorkingTree`).
- `GitMenuBar/Components/Common/`: UI shared across features, including the
  design tokens (`WorkbenchMetrics`, `WorkbenchMotion`, and related types).
- `GitMenuBar/Services/`: Git, GitHub, AI, credentials, persistence, platform,
  and usage-quota infrastructure. No SwiftUI views.
- `GitMenuBar/Models/`: value types shared by services and UI.
- `GitMenuBar/Utils/`: small helpers without feature ownership.
- `GitMenuBar/Support/`: preview doubles (`PreviewDoubles.swift`).
- `GitMenuBar/Resources/`: bundled icons and assets beyond the asset catalog.

## Naming Conventions

- Prefer semi-explicit names inside a feature folder.
- Keep the feature context in the filename when helpful: `MainMenuContent.swift`, `MainMenuActions.swift`.
- For local feature components, shorter names are acceptable when folder context is obvious.
- Avoid creating long prefix chains like `MainMenuView+Something+Else.swift`.

## Preview Conventions

- Keep `#Preview` blocks in the same file as the view whenever practical.
- Keep page preview harnesses near the page (`Pages/MainMenu/MainMenuPreviewHarness.swift`).
- For shared components, include focused previews with realistic sample data
  from `Support/PreviewDoubles.swift`.
- Run `make check-preview` after UI changes.

## Where New UI Should Go

Use this rule order:

1. If the UI composes a route, place it in that page folder under `Pages/`.
2. If the UI belongs to one feature, place it in `Components/<Feature>/`.
3. If the UI is reused by multiple features, move it to `Components/Common/`.
4. If the code is not UI (Git operations, API, persistence, app lifecycle),
   keep it in `Services/`, `Models/`, or `App/`.

## State and ownership

- Observable state uses Swift Observation (`@Observable`), not
  `ObservableObject`/`@Published`. Views read stores with
  `@Environment(Type.self)` and bind with `@Bindable`; mark non-UI state
  (tasks, caches, services, closures) `@ObservationIgnored`.
- AppKit consumers (today `StatusBarController`) observe
  stores with a `withObservationTracking` loop that re-arms on every change on
  the main actor and captures `self` weakly.
- `StatusBarController` owns the single `NSStatusItem`, context menu, and
  shortcuts. `MainWindowController` (`NSWindowController`) owns the main
  window lifecycle, placement, and frame autosave.
- `GitManager` is the observable facade for the selected repository: it keeps
  published state and delegates Git work to services
  (`GitBranchService`, `GitCommitHistoryService`, `GitRepositoryInitService`,
  `GitWorkingTreeService`). Git operations never live in views.
- `MainMenuActionCoordinator` owns commit and sync flows; side-panel actions
  live in `SidePanelActionCoordinator`, reached as
  `actionCoordinator.sidePanel`.
- `AppCommandRouter` routes menu-bar and palette `AppCommandID`
  invocations; `StatusBarController` wires it to `AppCommandCenter`.
- Main-menu features own their state and actions in feature models
  (`MainMenuWorkspaceState`, `MainMenuBranchDialogs`, `MainMenuSyncSheetState`,
  `MainMenuErrorCenter`, `MainMenuRepositoryOptionsState`,
  `MainMenuRepositoryConfirmations`, `MainMenuSnapshotModel` for recent projects
  and the render snapshot); `MainMenuView` is composition, command-palette
  execution, and focus.

## Change Strategy

- Keep file moves and behavioral changes in separate commits when possible.
- Validate each slice with `make build && make test`.
- Before merge, run `make lint && make test` (lint is cheap and fails fast; test already builds).

## Worktree and cleanup semantics

- A working tree is the files and Git status for one checkout.
- A worktree is one checkout managed by `git worktree`; linked worktrees have
  their own directory while sharing the repository's object database and refs.
- A branch is considered merged for cleanup when its tip is reachable from the
  selected local default branch or Git reports its commits as
  cherry-equivalent. Remote
  status uses the last fetched remote-tracking refs and does not imply a
  network fetch.
- Only local branches and clean, linked, attached worktrees can be eligible
  for safe cleanup. Unknown, dirty, locked, prunable, detached, current,
  protected, stale, or blocked checked-out-elsewhere state is never eligible;
  an eligible checked-out-elsewhere branch is represented only by a paired
  Cleanup Unit.
- A merged branch checked out in an eligible linked worktree is represented by
  one paired Cleanup Unit; safe cleanup removes the worktree first and then
  the branch. A branch without a linked worktree is a branch-only unit.
- A worktree path explicitly monitored as a project is protected from safe
  cleanup. Remote deletion remains outside Cleanup Units and requires an
  explicit selection and a fresh validation of the remote-tracking ref.
- Cleanup revalidates each item immediately before mutation, runs serially,
  skips unsafe or stale items individually, and reports every outcome. It
  never stashes changes, checks out another branch, or mutates the current
  worktree implicitly. An explicitly confirmed force-removal unit may remove a
  dirty, non-current, non-main, non-monitored linked worktree with
  `git worktree remove --force`; it keeps the branch and reports the result.
