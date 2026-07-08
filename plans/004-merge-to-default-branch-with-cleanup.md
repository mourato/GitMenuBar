# Plan 004: Merge feature branch into default branch with cleanup options

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
- **Risk**: MED
- **Depends on**: plans/003-branch-management-crud-ui.md (for `getDefaultBranchNameAsync`)
- **Category**: direction
- **Planned at**: commit `1a9e012`, 2026-07-08

## Why this matters

Currently the app supports merging *into the current branch* via `BranchRowView`
context menu → "Merge into [current]". But there's no streamlined workflow to:
1. Switch to the default branch (main/master)
2. Merge the feature branch into it
3. Offer to delete the feature branch (local, remote, or both)

This is the most common Git workflow (feature branch → main → cleanup). Making
it a single guided flow saves steps and reduces errors.

## Current state

- `GitManager.swift:2071-2102` — `mergeBranch(fromBranch:completion:)` merges
  a branch into the *currently checked out* branch. It does not handle switching
  to the target branch first.
- `GitManager.swift:1951-2015` — `switchBranch(branchName:completion:)` switches
  branches with auto-stash.
- `GitManager.swift:2104-2155` — `deleteBranch(branchName:completion:)` deletes
  both local and remote. The user has no control over which is deleted.
- `GitManager.swift:` — no `getDefaultBranchNameAsync()` method exists yet
  (will be added in plan 003).
- `MainMenuOverlays.swift:134-151` — merge confirmation alert: "Merge into
  [currentBranch]?" with simple Merge/Cancel.
- `MainMenuOverlays.swift:167-183` — delete branch confirmation alert.
- `MainMenuView.swift` — `mergeBranchName`, `mergeTargetBranch`,
  `showMergeConfirmation` states exist.
- `MainMenuContent.swift:104-117` — the onMergeBranch handler in the branch
  popover: when current branch IS main/master, it shows merge confirmation;
  otherwise calls `mergeBranch()` directly.

## What we're building

A new **Merge to Default** guided flow:

1. **Initiation**: User can trigger from:
   - Branch right-click context menu: "Merge into default branch"
   - Command palette (future, plan 006)
   - Branch management sheet (future, plan 003)
2. **Stash check**: If there are uncommitted changes, stash them first
   (with auto-stash notification)
3. **Switch to default**: `switchBranch(getDefaultBranchName())`
4. **Merge feature branch**: `mergeBranch(featureBranchName)`
5. **Success dialog**: After merge, show a confirmation dialog asking:
   - "Merge complete! Delete the feature branch?"
   - Options: "Delete Locally", "Delete Locally & Remotely", "Keep Branch",
     "Delete Remotely Only"
6. **Execute cleanup**: Based on user choice, delete local and/or remote
   - If remote deletion fails (branch doesn't exist on remote), silently skip
7. **Switch back**: Optionally switch back to the feature branch or stay on default

GitManager additions:
- `mergeDefaultBranchAsync(featureBranch: String, deleteLocal: Bool, deleteRemote: Bool) async -> Result<MergeResult, Error>` — orchestrates the full flow
- `MergeResult` struct — tracks what happened (switchedToDefault, didMerge, didDeleteLocal, didDeleteRemote)

## Commands you will need

| Purpose   | Command                     | Expected on success |
|-----------|-----------------------------|---------------------|
| Build     | `make build`                | Build Succeeded     |
| Test      | `make test`                 | All tests pass      |
| Lint      | `make lint`                 | No violations       |

## Scope

**In scope**:
- `GitMenuBar/Services/Git/GitManager.swift` — add `mergeDefaultBranchAsync`,
  `MergeResult`, and `getDefaultBranchNameAsync` (if not already added by plan 003)
- `GitMenuBar/Models/GitModels.swift` — add `MergeResult`, `CleanupOption` enums
- `GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift` — add cleanup confirmation
  dialog after merge
- `GitMenuBar/Pages/MainMenu/MainMenuView.swift` — add state for merge-to-default flow
- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift` — add action wiring
- `GitMenuBar/Pages/MainMenu/MainMenuContent.swift` — wire context menu action
- `GitMenuBar/Components/Branches/BranchRow.swift` — add "Merge into default" context menu item
- `GitMenuBar/Components/Branches/BranchSelectorPopover.swift` — pass the new callback
- `GitMenuBarTests/GitManagerMergeTests.swift` — **CREATE** tests

**Out of scope**:
- Command palette integration (plan 006)
- AI atomic commits (plan 005)
- Branch management sheet redesign (plan 003) — use existing `getDefaultBranchNameAsync`

## Git workflow

- Branch: `advisor/004-merge-to-default-branch`
- Commit per step
- Do NOT push

## Steps

### Step 1: Add `MergeResult` and `CleanupOption` models

In `GitModels.swift`, add after existing models:

```swift
struct MergeToDefaultResult: Equatable {
    let didSwitchToDefault: Bool
    let didMerge: Bool
    let didDeleteLocal: Bool
    let didDeleteRemote: Bool
    let defaultBranchName: String
    let featureBranchName: String
}

enum BranchCleanupOption: String, CaseIterable {
    case deleteLocal = "Delete Local Only"
    case deleteLocalAndRemote = "Delete Local & Remote"
    case deleteRemoteOnly = "Delete Remote Only"
    case keep = "Keep Branch"
}
```

**Verify**: `make build` succeeds.

### Step 2: Add `getDefaultBranchNameAsync` to `GitManager`

If not already added by plan 003, add this method:

```swift
func getDefaultBranchNameAsync() async -> String {
    let repositoryPath = storedRepoPath
    guard !repositoryPath.isEmpty else { return "main" }

    return await runOnBackground {
        // Try upstream HEAD symbolic ref first
        let result = self.executeGitCommand(
            in: repositoryPath,
            args: ["symbolic-ref", "refs/remotes/origin/HEAD"]
        )
        if !result.failure {
            let ref = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if let lastComponent = ref.split(separator: "/").last {
                return String(lastComponent)
            }
        }

        // Fallback: check common branch names
        for candidate in ["main", "master"] {
            let check = self.executeGitCommand(
                in: repositoryPath,
                args: ["show-ref", "--verify", "--quiet", "refs/heads/\(candidate)"]
            )
            if !check.failure {
                return candidate
            }
        }

        return "main"
    }
}
```

**Verify**: `make build` succeeds.

### Step 3: Add `mergeToDefaultBranchAsync` to `GitManager`

Add this method:

```swift
func mergeToDefaultBranchAsync(
    featureBranch: String,
    cleanupOption: BranchCleanupOption
) async -> Result<MergeToDefaultResult, Error> {
    // 1. Detect default branch
    let defaultBranch = await getDefaultBranchNameAsync()

    // 2. Check for uncommitted changes and stash if needed
    let hasChanges = await hasUncommittedChangesAsync()
    var stashed = false
    if hasChanges {
        let stashResult = await runOnBackground {
            self.executeGitCommand(in: self.storedRepoPath, args: ["stash", "push", "-u", "-m", "GitMenuBar auto-stash for merge"])
        }
        guard !stashResult.failure else {
            return .failure(NSError(domain: "GitManager", code: 20, userInfo: [NSLocalizedDescriptionKey: "Failed to stash changes: \(stashResult.output)"]))
        }
        stashed = true
    }

    // 3. Switch to default branch
    let currentWasDefault = currentBranch == defaultBranch
    if !currentWasDefault {
        _ = await runOnBackground {
            self.executeGitCommand(in: self.storedRepoPath, args: ["checkout", defaultBranch])
        }
    }

    // 4. Merge feature branch
    let mergeResult = await runOnBackground {
        self.executeGitCommand(in: self.storedRepoPath, args: ["merge", featureBranch])
    }
    guard !mergeResult.failure else {
        // On failure, switch back
        if !currentWasDefault {
            _ = self.executeGitCommand(in: self.storedRepoPath, args: ["checkout", currentBranch])
        }
        if stashed {
            _ = self.executeGitCommand(in: self.storedRepoPath, args: ["stash", "pop"])
        }
        let isConflict = mergeResult.output.contains("CONFLICT") || mergeResult.output.contains("Automatic merge failed")
        return .failure(NSError(domain: "GitManager", code: 21, userInfo: [NSLocalizedDescriptionKey: isConflict ? "Merge conflict! Please resolve manually." : "Merge failed: \(mergeResult.output)"]))
    }

    // 5. Handle cleanup
    let deleteLocal: Bool
    let deleteRemote: Bool
    switch cleanupOption {
    case .deleteLocal:
        deleteLocal = true; deleteRemote = false
    case .deleteLocalAndRemote:
        deleteLocal = true; deleteRemote = true
    case .deleteRemoteOnly:
        deleteLocal = false; deleteRemote = true
    case .keep:
        deleteLocal = false; deleteRemote = false
    }

    var didDeleteLocal = false
    var didDeleteRemote = false

    if deleteLocal && featureBranch != defaultBranch {
        let localResult = await runOnBackground {
            self.executeGitCommand(in: self.storedRepoPath, args: ["branch", "-D", featureBranch])
        }
        didDeleteLocal = !localResult.failure
    }

    if deleteRemote {
        let remoteResult = await runOnBackground {
            self.executeGitCommand(in: self.storedRepoPath, args: ["push", "origin", "--delete", featureBranch], useAuth: true)
        }
        didDeleteRemote = !remoteResult.failure
    }

    // 6. Restore stash if needed
    if stashed {
        _ = await runOnBackground {
            self.executeGitCommand(in: self.storedRepoPath, args: ["stash", "pop"])
        }
    }

    // 7. Refresh
    await refreshAsync()
    await checkRemoteStatusAsync()

    return .success(MergeToDefaultResult(
        didSwitchToDefault: !currentWasDefault,
        didMerge: true,
        didDeleteLocal: didDeleteLocal,
        didDeleteRemote: didDeleteRemote,
        defaultBranchName: defaultBranch,
        featureBranchName: featureBranch
    ))
}
```

**Verify**: `make build` succeeds.

### Step 4: Add merge-to-default flow to `BranchRowView` context menu

In `BranchRowView.swift`:
- Add `let onMergeToDefault: (() -> Void)?` parameter
- In the `.contextMenu`, add a new Button "Merge into default branch" that calls `onMergeToDefault`
- Only show this option when `!isCurrentBranch && onMergeToDefault != nil`

**Verify**: Build succeeds; context menu shows "Merge into default branch".

### Step 5: Wire the flow through `BranchSelectorPopoverView` and `MainMenuContent`

In `BranchSelectorPopoverView.swift`:
- Add `let onMergeToDefaultBranch: ((String) -> Void)?` parameter
- In the branch row construction, pass `onMergeToDefault: row.canMerge ? { onMergeToDefaultBranch?(row.branchName) } : nil`

In `MainMenuContent.swift`, in the `BranchSelectorPopoverView` construction:
- Pass `onMergeToDefaultBranch` callback that:
  1. Closes the popover
  2. Sets merge state with the feature branch name
  3. Shows the cleanup option dialog

**Verify**: Build succeeds.

### Step 6: Add cleanup option dialog in `MainMenuOverlays`

In `MainMenuOverlays.swift`, add a new confirmation dialog:

```swift
.confirmationDialog(
    "Merge Complete",
    isPresented: $showMergeCleanupDialog,
    titleVisibility: .visible
) {
    Button("Delete Local Only") {
        performMergeCleanup(option: .deleteLocal)
    }
    Button("Delete Local & Remote") {
        performMergeCleanup(option: .deleteLocalAndRemote)
    }
    Button("Delete Remote Only") {
        performMergeCleanup(option: .deleteRemoteOnly)
    }
    Button("Keep Branch", role: .cancel) {
        performMergeCleanup(option: .keep)
    }
} message: {
    Text("'\(featureBranchName)' was merged into \(defaultBranchName). What should happen to the feature branch?")
}
```

Add state to `MainMenuView.swift`:
- `@State var showMergeCleanupDialog = false`
- `@State var featureBranchName = ""`
- `@State var defaultBranchName = ""`

Add `performMergeCleanup(option:)` in `MainMenuActions.swift`:
```swift
func performMergeCleanup(option: BranchCleanupOption) {
    Task {
        let result = await gitManager.mergeToDefaultBranchAsync(
            featureBranch: featureBranchName,
            cleanupOption: option
        )
        switch result {
        case .success(let mergeResult):
            // Show success banner
            defaultBranchName = ""
            featureBranchName = ""
        case .failure(let error):
            mergeError = error.localizedDescription
        }
        showMergeCleanupDialog = false
    }
}
```

**Verify**: Build succeeds; full merge flow works end-to-end.

### Step 7: Add tests

In `GitMenuBarTests/GitManagerMergeTests.swift`:
- Test `getDefaultBranchNameAsync()` returns expected results
- Test merge flow detects conflicts
- Mock `GitCommandRunner` and verify the correct sequence of git commands
  is called for each `CleanupOption`

**Verify**: `make test` passes.

## Test plan

- Unit tests for `getDefaultBranchNameAsync` with mocked git responses
- Unit tests for `mergeToDefaultBranchAsync` with each `CleanupOption`
- Test merge conflict detection
- Test stash/unstash during merge flow

## Done criteria

- [ ] `make build` exits 0
- [ ] `make test` exits 0; new tests exist and pass
- [ ] `make lint` exits 0
- [ ] Right-click a non-current branch → "Merge into default branch"
- [ ] Flow: stashes changes → switches to default → merges → shows cleanup dialog
- [ ] Cleanup options correctly delete local/remote/both/none
- [ ] App refreshes state after merge completes
- [ ] `plans/README.md` status row updated for this plan

## STOP conditions

Stop and report back if:
- The code at the locations in "Current state" doesn't match the excerpts
- `getDefaultBranchNameAsync` from plan 003 has a different signature — adapt
- A step's verification fails twice after a reasonable fix attempt

## Maintenance notes

- The merge flow is synchronous within the async method; if users have large
  repos, consider progress reporting
- Conflict handling currently delegates to manual resolution; future: integrate
  a merge conflict resolver view
- The cleanup dialog currently blocks the UI; future: make it a non-blocking
  notification with a time delay
