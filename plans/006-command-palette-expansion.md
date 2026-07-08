# Plan 006: Expand command palette with all major actions

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 1a9e012..HEAD -- GitMenuBar/`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: plans/003-branch-management-crud-ui.md, plans/004-merge-to-default-branch-with-cleanup.md, plans/005-ai-atomic-commits.md
- **Category**: direction
- **Planned at**: commit `1a9e012`, 2026-07-08

## Why this matters

The command palette is the fastest way to discover and execute actions. Currently
it only exposes Commit, Commit & Push, and Sync. After adding branch management,
merge-to-default, and atomic commits, users need to access all of these from the
palette. This plan adds every major action to the command palette, making the app
keyboard-navigable and discoverable.

## Current state

- `MainMenuCommandPalette.swift:349` — the palette view with `MainMenuCommandPaletteKind`
  enum containing: `.commit`, `.commitAndPush`, `.sync`, `.recentProject`, `.restartApp`, `.quitApp`
- `MainMenuCommandPaletteResolver.swift:129` — `resolveItems()` builds palette items
  from `StatusBarContextMenuActionState`. Only has 3 action items.
- `MainMenuCommandPaletteResolver.swift:121-128` — `executionDecision` maps kinds to
  execution style (`.executeNow` or `.requiresConfirmation`)
- `MainMenuActions.swift:334-401` — `executeCommandPaletteItemImmediately()` handles
  each kind. Currently only handles the 3 actions + recent projects + app actions.
- `MainMenuCommandsPalettePreview.swift` — preview harness
- `AppCommandCenter.swift:254` — command definitions (`AppCommandID`) and keyboard
  shortcuts. Currently includes: openWindow, showSettings, showCommandPalette, commit,
  commitAndPush, sync, chooseRepository, revealInFinder, openOnGitHub, showRepositoryOptions,
  helpRepository, reportIssue, quit.
- `MainMenuComputed.swift:368-391` — `commandPaletteActionState` and
  `commandPaletteAllItems` computed properties derive palette items from
  `StatusBarContextMenuActionState`.
- `StatusBarContextMenuActionState.swift:30` — action state with
  showsCommit/canCommit/showsCommitAndPush/canCommitAndPush/showsSync/canSync.

**Key gap**: `MainMenuCommandPaletteKind` and `MainMenuCommandPaletteResolver` need
new cases and resolution logic for: branch CRUD, merge, atomic commits, push, pull,
create branch, switch branch, branch management sheet.

## What we're building

Add the following new palette actions:

1. **Atomic Commits** — "Create Atomic Commits" when there are changes
2. **Branch Management** — "Manage Branches…" always enabled
3. **Merge to Default** — "Merge into default branch" when on a non-default branch
4. **Create Branch** — "Create Branch…" always enabled
5. **Push** — "Push Changes" when ahead of remote
6. **Pull** — "Pull Changes" when behind remote
7. **Switch Branch** — list of branches as sub-items (or "Switch Branch…" leading to branch selector)

Also add a new `.branches` section in `MainMenuCommandPaletteSection` for
branch-related actions.

## Commands you will need

| Purpose   | Command                     | Expected on success |
|-----------|-----------------------------|---------------------|
| Build     | `make build`                | Build Succeeded     |
| Test      | `make test`                 | All tests pass      |
| Lint      | `make lint`                 | No violations       |

## Scope

**In scope**:
- `GitMenuBar/Pages/MainMenu/MainMenuCommandPalette.swift` — add new `MainMenuCommandPaletteKind` cases
- `GitMenuBar/Pages/MainMenu/MainMenuCommandPaletteResolver.swift` — add items for all new kinds
- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift` — handle execution of new kinds
- `GitMenuBar/Pages/MainMenu/MainMenuComputed.swift` — update `commandPaletteAllItems` logic
- `GitMenuBar/App/AppCommandCenter.swift` — add new `AppCommandID` cases and keyboard shortcuts
- `GitMenuBar/App/StatusBarContextMenuActionState.swift` — expand action state if needed
- `GitMenuBar/Pages/MainMenu/MainMenuView.swift` — add state for any new action triggers
- `GitMenuBarTests/MainMenuCommandPaletteResolverTests.swift` — update tests

**Out of scope**:
- Implementation of the new features themselves (plans 003, 004, 005)
- Changing the palette UI appearance
- Adding keyboard shortcuts for every new action (that's a future refinement)

## Git workflow

- Branch: `advisor/006-command-palette-expansion`
- Commit per step
- Do NOT push

## Steps

### Step 1: Add new `MainMenuCommandPaletteKind` cases

In `MainMenuCommandPalette.swift`, extend the enum:

```swift
enum MainMenuCommandPaletteKind: Hashable {
    // Existing
    case commit
    case commitAndPush
    case sync
    case recentProject(path: String)
    case restartApp
    case quitApp

    // New
    case atomicCommits
    case branchManagement
    case mergeToDefault(featureBranch: String)
    case createBranch
    case push
    case pull
    case switchBranch(branchName: String)
    case switchToBranchList
}
```

Add a new section case in `MainMenuCommandPaletteSection`:
```swift
enum MainMenuCommandPaletteSection: String, CaseIterable {
    case actions
    case branches       // NEW
    case recentProjects
    case app

    var title: String {
        switch self {
        case .actions:
            return "Actions"
        case .branches:
            return "Branches"
        case .recentProjects:
            return "Recent Projects"
        case .app:
            return "App"
        }
    }
}
```

Update `stableID` for each new case with a consistent prefix pattern.

**Verify**: `make build` succeeds.

### Step 2: Update `MainMenuCommandPaletteResolver.resolveItems`

Update `resolveItems()` to accept additional context:
- `availableBranches: [String]`
- `currentBranch: String`
- `canDoAtomicCommits: Bool`
- `isBehindRemote: Bool`
- `isAheadOfRemote: Bool`
- `canShowBranchManagement: Bool`

Add items for the new kinds:

```swift
// Atomic Commits (when there are working tree changes)
if canDoAtomicCommits {
    items.append(MainMenuCommandPaletteItem(
        kind: .atomicCommits,
        section: .actions,
        title: "Create Atomic Commits",
        subtitle: "AI groups changes into logical commits",
        keywords: ["atomic", "commit", "ai", "group", "split"],
        isEnabled: true
    ))
}

// Push (when ahead of remote)
if isAheadOfRemote {
    items.append(MainMenuCommandPaletteItem(
        kind: .push,
        section: .actions,
        title: "Push Changes",
        subtitle: "Push local commits to remote",
        keywords: ["git", "push", "remote"],
        isEnabled: true
    ))
}

// Pull (when behind remote)
if isBehindRemote {
    items.append(MainMenuCommandPaletteItem(
        kind: .pull,
        section: .actions,
        title: "Pull Changes",
        subtitle: "Update from remote",
        keywords: ["git", "pull", "update", "remote"],
        isEnabled: true
    ))
}

// Branch Management (always enabled if repo is open)
items.append(MainMenuCommandPaletteItem(
    kind: .branchManagement,
    section: .branches,
    title: "Manage Branches…",
    subtitle: "View, create, rename, delete branches",
    keywords: ["branch", "manage", "crud", "remote"],
    isEnabled: canShowBranchManagement
))

// Create Branch
items.append(MainMenuCommandPaletteItem(
    kind: .createBranch,
    section: .branches,
    title: "Create Branch…",
    subtitle: "Create a new branch from current HEAD",
    keywords: ["branch", "create", "new"],
    isEnabled: canShowBranchManagement
))

// Merge to default (only when not on default branch)
if !isOnDefaultBranch, let defaultBranchName {
    items.append(MainMenuCommandPaletteItem(
        kind: .mergeToDefault(featureBranch: currentBranch),
        section: .branches,
        title: "Merge '\(currentBranch)' into \(defaultBranchName)",
        subtitle: "Merge current branch into default and clean up",
        keywords: ["merge", "default", "main", "master", "branch"],
        isEnabled: true
    ))
}

// Switch to branch list
items.append(MainMenuCommandPaletteItem(
    kind: .switchToBranchList,
    section: .branches,
    title: "Switch Branch…",
    subtitle: "Check out a different branch",
    keywords: ["switch", "checkout", "branch"],
    isEnabled: canShowBranchManagement
))
```

Note: `isOnDefaultBranch` and `defaultBranchName` should be computed from
`currentBranch` and `availableBranches` (the default is detected by
`getDefaultBranchNameAsync` from plan 003).

Also add `executionDecision` entries for each new kind:
```swift
case .branchManagement, .createBranch, .switchToBranchList:
    return .executeNow     // These open sheets/popovers
case .mergeToDefault:
    return .executeNow     // Shows confirmation dialog inline
case .push, .pull, .atomicCommits:
    return .executeNow
```

**Verify**: `make build` succeeds.

### Step 3: Update `MainMenuComputed.swift`

In `MainMenuComputed.swift`, update the `commandPaletteActionState` and
`commandPaletteAllItems` to pass the new context:

```swift
var commandPaletteAllItems: [MainMenuCommandPaletteItem] {
    MainMenuCommandPaletteResolver.resolveItems(
        actionState: commandPaletteActionState,
        syncActionTitle: actionCoordinator.syncActionTitle,
        recentPaths: recentPaths,
        currentRepoPath: currentRepoPath,
        // New parameters:
        availableBranches: gitManager.availableBranches,
        currentBranch: gitManager.currentBranch,
        canDoAtomicCommits: hasWorkingTreeChanges,
        isBehindRemote: gitManager.isBehindRemote,
        isAheadOfRemote: gitManager.isAheadOfRemote,
        canShowBranchManagement: !currentRepoPath.isEmpty,
        defaultBranchName: gitManager.defaultBranchName // add this to GitManager
    )
}
```

You may need to add a `@Published var defaultBranchName: String = "main"` to
`GitManager` (populated during `getDefaultBranchNameAsync()`) or compute it
synchronously from `availableBranches`.

**Verify**: `make build` succeeds.

### Step 4: Update `MainMenuActions.swift` execution handlers

In `executeCommandPaletteItemImmediately()`, add handlers for each new kind:

```swift
case .atomicCommits:
    Task {
        await startAtomicCommitFlow()    // From plan 005
    }
case .branchManagement:
    showBranchManagement = true          // From plan 003
case .mergeToDefault(let featureBranch):
    // Store featureBranch and show the merge flow (plan 004)
    featureBranchName = featureBranch
    showMergeCleanupDialog = true
case .createBranch:
    showCreateBranch = true              // Already exists
case .push:
    Task {
        _ = await actionCoordinator.performSync()
    }
case .pull:
    // Trigger pull (currently only sync handles both)
    Task {
        _ = await actionCoordinator.syncWithRemote(rebase: false)
    }
case .switchBranch(let branchName):
    gitManager.switchBranch(branchName: branchName) { result in
        if case let .failure(error) = result {
            branchSwitchError = error.localizedDescription
        }
    }
case .switchToBranchList:
    showBranchSelector = true            // Already exists
```

**Verify**: `make build` succeeds.

### Step 5: Update `AppCommandCenter` with new command IDs

Add new `AppCommandID` cases:
```swift
enum AppCommandID: Hashable {
    // Existing
    case openWindow
    case showSettings
    case showCommandPalette
    case commit
    case commitAndPush
    case sync
    case chooseRepository
    case revealRepositoryInFinder
    case openRepositoryOnGitHub
    case showRepositoryOptions
    case helpRepository
    case reportIssue
    case quit

    // New
    case atomicCommits
    case branchManagement
    case push
    case pull
    case createBranch
    case mergeToDefault
}
```

Add fallback titles for each. Update `resolveSnapshot()` to include states for
the new commands based on context.

**Verify**: `make build` succeeds.

### Step 6: Add keyboard shortcuts for new palette actions

In `KeyboardShortcuts+Names.swift`, add new shortcuts:
```swift
extension KeyboardShortcuts.Name {
    static let push = Self("push", default: .init(.p, modifiers: [.option, .command]))
    static let branchManagement = Self("branchManagement", default: .init(.b, modifiers: [.option, .command]))
    static let createBranch = Self("createBranch", default: .init(.n, modifiers: [.option, .command]))
}
```

Wire these in `GitMenuBarApp.swift` using the existing `KeyboardShortcuts` pattern.

**Verify**: `make build` succeeds.

### Step 7: Update tests

Update `MainMenuCommandPaletteResolverTests.swift`:
- Add test cases for each new kind
- Verify items appear in the correct section
- Verify filtering works for new keywords
- Verify `executionDecision` returns expected values

Update `AppCommandResolverTests.swift` if it exists:
- Test new command IDs state resolution

**Verify**: `make test` passes.

## Test plan

- Unit tests for new `MainMenuCommandPaletteResolver` items
- Unit tests for `executionDecision` on new kinds
- Unit tests for `AppCommandResolver` new command states
- Manual: open command palette, type "branch" — see all branch-related actions
- Manual: type "atomic" — see atomic commit action
- Manual: type "push" — see push action (only when ahead)

## Done criteria

- [ ] `make build` exits 0
- [ ] `make test` exits 0; existing and new tests pass
- [ ] `make lint` exits 0
- [ ] Command palette shows: Atomic Commits, Manage Branches, Create Branch,
      Merge to Default, Push, Pull, Switch Branch
- [ ] All new palette items are correctly enabled/disabled based on state
- [ ] Selecting each item triggers the correct action/sheet/dialog
- [ ] Command palette has a "Branches" section
- [ ] `plans/README.md` status row updated for this plan

## STOP conditions

Stop and report back if:
- The code at the locations in "Current state" doesn't match the excerpts
- A step's verification fails twice after a reasonable fix attempt
- Plan 003/004/005 are not yet implemented — the palette items will exist but
  their action handlers should show "not yet implemented" or simply no-op until
  the dependent plans land
- You discover `commandPaletteAllItems` needs significant refactoring to support
  the new context — stop and propose a design

## Maintenance notes

- Each new palette item should be independently enable/disable-able
- The `mergeToDefault` kind takes a `featureBranch` parameter — this means
  an item per feature branch if the user has multiple non-default branches
- As more actions are added, consider grouping palette items by verb
  (branch/*, commit/*, repo/*)
- The `StatusBarContextMenuActionState` may need to be deprecated in favor of
  richer state from `MainMenuActionCoordinator` directly
