# Code review: Plan 019

- **Reviewed scope**: conservative branch deletion, serial cleanup API, revalidation, confirmation flow, worktree/remote selection, and regression tests
- **Reviewer**: thermo-nuclear-code-quality-review with GitMenuBar review profile
- **Final verdict**: APPROVED after fixes

## Findings

### [CRITICAL] Never reuse the old force-delete path for cleanup

- **Area**: data safety
- **Issue**: the existing local branch deletion and merged-branch cleanup used `git branch -D`.
- **Resolution**: both ordinary local deletion and merged-branch cleanup now use `git branch --delete`; an unmerged-branch regression test proves the branch remains intact when Git rejects deletion. The separate repository-wipe flow still has its intentionally forceful history replacement behavior and is outside cleanup scope.

### [HIGH] Revalidate every selected item immediately before mutation

- **Area**: stale state and concurrent changes
- **Issue**: a snapshot can become stale between display, confirmation, and execution.
- **Resolution**: the serial batch API verifies repository identity, item existence, analyzed HEAD hash, current/default/protected status, merge reachability, worktree registration, lock/prunable state, cleanliness, and remote-tracking state before each command. Stale or unsafe items are skipped individually and later items continue.

### [HIGH] Keep worktree and remote deletion explicit

- **Area**: destructive scope
- **Issue**: selecting a local branch must not implicitly remove a worktree directory or remote branch.
- **Resolution**: `GitCleanupTarget` has separate local-branch, worktree, and remote-branch cases. The UI selects local branches/worktrees independently; remote targets require an explicit API target and are listed separately in confirmation. Worktree or remote targets require an additional review step.

### [HIGH] Report partial batch outcomes

- **Area**: recoverability
- **Issue**: a batch may contain a mix of successful, stale, and failed items.
- **Resolution**: mutations run serially in one background operation and return a `GitCleanupItemResult` for every target. The UI clears selections, refreshes once through the existing path, and presents per-item completed/skipped/failed reasons.

### [MEDIUM] Keep cleanup controls disabled while running

- **Area**: concurrency and duplicate mutation prevention
- **Issue**: repeated clicks could otherwise start overlapping repository mutations.
- **Resolution**: the Cleanup action is disabled while loading, while confirmation has no selected eligible targets, or while a batch is running. The confirmation flow is separate and has a second review for directory/remote removal.

## Safety invariants verified

- Cleanup paths contain no `git branch -D` or `git worktree remove --force`.
- Dirty, locked, prunable, detached, current, protected, unknown, stale, missing, and no-longer-merged items are never treated as safe.
- Worktree deletion uses `git worktree remove <path>` without force and only after a clean status check.
- Remote deletion is authenticated, explicit, hash-checked, and based on the last fetched remote-tracking refs; no automatic fetch is performed.
- No stash, checkout, or current-worktree mutation is introduced by cleanup.

## Validation

- `make agent-check`: passed; changed files have no serious SwiftLint violations. Existing line-length warnings in `GitManager.swift` remain baseline warnings.
- `make test`: passed, including all new cleanup tests.
- `git diff --check`: passed.
- `make lint`: blocked by pre-existing SwiftFormat violations in untouched `GitMenuBarTests/MainMenuCommandPaletteResolverTests.swift`, `GitMenuBar/Pages/MainMenu/HistorySectionView.swift`, `GitMenuBar/Pages/Settings/SettingsPage.swift`, and `GitMenuBar/Pages/MainMenu/WorkingTreeSectionView.swift`.

No unresolved Critical, High, Medium, or Low findings remain in the Plan 019 diff.
