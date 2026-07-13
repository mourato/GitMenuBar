# Plan 003: Implement dedicated branch management CRUD UI

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: no; this plan is serial unless a named independent workstream is added during reclassification.
- **Reviewer required**: yes; the plan has high-risk architectural, operational, or integration impact.
- **Rationale**: UI nova integrada a operações Git e múltiplos estados; exige revisão de comportamento e arquitetura.
- **Escalate when**: Se tocar persistência, credenciais, concorrência, release ou alterar o contrato público de GitManager.

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
- **Effort**: L
- **Risk**: MED
- **Depends on**: none
- **Category**: direction
- **Planned at**: commit `1a9e012`, 2026-07-08

## Why this matters

The app currently exposes branch operations (create, rename, delete, merge) only
through a compact popover (`BranchSelectorPopoverView`) and context menus on
`BranchRowView`. There is no way to view remote branches separately, push a
local branch to remote, or see tracking status. Users need a full branch
management screen that shows local and remote branches side by side with
create/rename/delete/push/track operations all in one place.

## Current state

- `GitManager.swift:2191` — contains all branch methods: `fetchBranches()` (line 1687),
  `createBranch()` (line 2017), `deleteBranch()` (line 2104), `renameBranch()` (line 2157),
  `mergeBranch()` (line 2071), `switchBranch()` (line 1951),
  `createBranchFromCurrentHead()` (line 1920), `pullToNewBranch()` (line 1894).
  `fetchBranchesAsync()` (line 1729) currently lists remote branches mixed with local
  ones and deduplicates them — it loses the local-vs-remote distinction.
- `BranchSelectorPopoverView.swift:123` — popover listing branches with
  switch/merge/rename/delete via `BranchRowView`.
- `BranchRowView.swift:99` — single row with context menu (Rename, Merge, Delete).
- `BranchMenuRowAdapter.swift` — adapter model for branch display.
- `BottomBranchSelector.swift:104` — footer button that opens the branch popover.
- `GitModels.swift:154` — data models (Commit, WorkingTreeFile, etc.). No
  branch-specific models exist yet.
- `MainMenuContent.swift:74` — the existing BranchSelectorPopoverView integration
  in the footer.

**Key gap**: `fetchBranchesAsync()` merges local and remote into a single
deduplicated list. There is no way to:
- See which branches exist only locally vs. only remotely
- Push a local branch to the remote
- Delete a remote branch independently of its local counterpart
- View tracking status (which local branch tracks which remote)

## What we're building

A new **Branch Management screen** accessible from the footer or command palette:
- Lists local branches and remote branches in separate sections
- Shows tracking status (local → remote)
- Actions per branch: Create, Rename, Delete (local only, remote only, or both),
  Push to remote, Set upstream
- Full screen popover (like the current branch selector but larger)

GitManager additions:
- `fetchLocalBranchesAsync()` — returns only local branches
- `fetchRemoteBranchesAsync()` — returns only remote branches (origin/*)
- `pushBranchToRemoteAsync(branchName:)` — push a local branch to origin
- `deleteRemoteBranchAsync(branchName:)` — delete a branch on remote only
- `setUpstreamAsync(branchName:)` — set upstream tracking for a branch
- `getDefaultBranchNameAsync() -> String` — detect main/master/default branch

New models:
- `BranchInfo` — represents a branch with name, isLocal, isRemote, trackingStatus,
  isCurrent, lastCommitDate

## Commands you will need

| Purpose   | Command                     | Expected on success |
|-----------|-----------------------------|---------------------|
| Build     | `make build`                | Build Succeeded     |
| Test      | `make test`                 | All tests pass      |
| Lint      | `make lint`                 | No violations       |

## Suggested executor toolkit

- macOS development skill: `macos-development`
- Swift conventions skill: `swift-conventions`
- SwiftUI performance: `swiftui-performance-audit`

## Scope

**In scope** (the only files you should create/modify):
- `GitMenuBar/Services/Git/GitManager.swift` — add new branch methods
- `GitMenuBar/Models/GitModels.swift` — add `BranchInfo` model
- `GitMenuBar/Pages/MainMenu/MainMenuContent.swift` — integrate new view
- `GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift` — handle branch management sheet
- `GitMenuBar/Pages/MainMenu/MainMenuView.swift` — add state for branch management sheet
- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift` — add branch management action wiring
- `GitMenuBar/Pages/MainMenu/MainMenuComputed.swift` — add branch management computed props
- `GitMenuBar/Components/Branches/BranchManagementSheet.swift` — **CREATE** the new screen
- `GitMenuBar/Components/Branches/BranchManagementRowView.swift` — **CREATE** row component
- `GitMenuBarTests/` — add tests for new `GitManager` branch methods

**Out of scope** (do NOT touch):
- `MainMenuCommandPalette*` — will be updated in plan 006
- Existing `BranchSelectorPopoverView` and `BranchRowView` — keep them working
- AI commit message code (`AICommit*`, `AIProvider*`)

## Git workflow

- Branch: `advisor/003-branch-management-crud`
- Commit per step; message style matches existing commits from `git log`:
  "Add BranchInfo model", "Add GitManager remote branch operations",
  "Create BranchManagementSheet view", "Wire branch management into MainMenu"
- Do NOT push

## Steps

### Step 1: Add `BranchInfo` model to `GitModels.swift`

Add a new struct after the existing `WorkingTreeSectionSummary`:

```swift
struct BranchInfo: Identifiable, Hashable {
    let name: String
    let isLocal: Bool
    let isRemote: Bool
    let isCurrent: Bool
    let trackingStatus: BranchTrackingStatus
    let lastCommitDate: Date?

    var id: String { "\(isLocal ? "local" : "remote")/\(name)" }

    var displayName: String {
        isRemote ? "origin/\(name)" : name
    }
}

enum BranchTrackingStatus: Hashable {
    case upToDate
    case ahead(Int)
    case behind(Int)
    case diverged(ahead: Int, behind: Int)
    case noRemote
    case unknown
}
```

**Verify**: `make build` succeeds.

### Step 2: Add remote branch methods to `GitManager.swift`

Add these methods to `GitManager`:

1. `fetchLocalBranchesAsync() async -> [String]` — runs `git branch --format=%(refname:short)`
2. `fetchRemoteBranchesAsync() async -> [String]` — runs `git branch -r --format=%(refname:short)`,
   filters to `origin/*`, strips `origin/` prefix
3. `pushBranchToRemoteAsync(branchName: String) async -> Result<Void, Error>` —
   runs `git push -u origin <branchName>`, uses existing `useAuth`
4. `deleteRemoteBranchAsync(branchName: String) async -> Result<Void, Error>` —
   runs `git push origin --delete <branchName>`, uses existing `useAuth`
5. `getDefaultBranchNameAsync() async -> String` — tries `git symbolic-ref refs/remotes/origin/HEAD`,
   parses result to extract branch name; falls back to `main`, then `master`
6. `increaseCommitHistoryLimit()` — existing method, add a companion
   `resolveBranchInfoAsync() async -> [BranchInfo]` that:
   - Fetches local and remote branches
   - Fetches current branch name
   - For each local branch, checks tracking status via `git rev-list --left-right --count`
   - Returns merged `[BranchInfo]`

Follow the existing patterns in `GitManager.swift`:
- Use `runOnBackground` for async work
- Use `publishOnMainActor` only when updating `@Published` properties
- Error handling via `Result<Void, Error>`
- Reuse `executeGitCommand(in:args:useAuth:)`

**Verify**: `make build` succeeds.

### Step 3: Create `BranchManagementSheet.swift`

Create `GitMenuBar/Components/Branches/BranchManagementSheet.swift`:

A SwiftUI view that presents as a sheet (`macPanelSurface()` styling):
- **Two sections**: "Local Branches" and "Remote Branches"
- Each branch row shows: name, current indicator, tracking status icon, last commit date
- Actions per branch (via context menu or inline buttons):
  - Local: Switch, Rename, Delete, Push to Remote, Merge into Current
  - Remote: Delete Remote, Checkout Locally
- "New Branch" button at the bottom
- Search/filter field at the top
- Loading state while fetching

Wire action callbacks to `GitManager` methods (passed in via closures).
Follow the existing pattern of `BranchSelectorPopoverView`.

Include `#Preview`.

**Verify**: `make build` succeeds.

### Step 4: Create `BranchManagementRowView.swift`

Create `GitMenuBar/Components/Branches/BranchManagementRowView.swift`:

A reusable row component similar to `BranchRowView` but with richer info:
- Branch name
- Tracking status indicator (ahead/behind/upToDate icons)
- Last commit relative date
- Checkmark for current branch
- Context menu with CRUD actions based on local/remote type

Include `#Preview`.

**Verify**: `make build` succeeds.

### Step 5: Wire into MainMenuView/MainMenuContent

In `MainMenuView.swift`:
- Add `@State var showBranchManagement = false`
- Add to overlays: `.sheet(isPresented: $showBranchManagement)` with the new sheet
- Pass git manager actions to the sheet

In `MainMenuContent.swift`:
- Add a "Manage Branches…" button in the footer or in the branch popover's "New Branch…" section
- The branch management sheet should also be opened from the `BottomBranchSelectorView`

**Verify**: Build succeeds; "Manage Branches…" appears in UI.

### Step 6: Add `fetchBranches` separation in `GitManager`

Modify `fetchBranches()` and `fetchBranchesAsync()` to also populate
separate `@Published` properties for local-only and remote-only branches.
Add:
- `@Published var localBranches: [String] = []`
- `@Published var remoteBranches: [String] = []`

Update `refreshAsync` to call the new fetch methods.

Expose `@Published var branchInfos: [BranchInfo] = []` computed from the
above, updated in `resolveBranchInfoAsync()`.

**Verify**: `make build && make test` passes.

### Step 7: Add tests

In `GitMenuBarTests/`, create `GitManagerBranchOperationsTests.swift`:
- Test that `getDefaultBranchNameAsync()` returns a string
- Test `fetchLocalBranchesAsync` and `fetchRemoteBranchesAsync` on test repo
- Mock `GitCommandRunner` and verify correct git commands are constructed

Model after existing test patterns in `GitWorkingTreeStateTests.swift`
and `GitCommandRunnerTests.swift`.

**Verify**: `make test` passes, all new tests pass.

## Test plan

- Unit tests for new GitManager methods in `GitManagerBranchOperationsTests.swift`
- Snapshot/preview test for `BranchManagementSheetView`
- Smoke test: open branch management, see local/remote lists, perform rename

## Done criteria

- [ ] `make build` exits 0
- [ ] `make test` exits 0; new tests exist and pass
- [ ] `make lint` exits 0
- [ ] Branch management sheet shows local and remote branches separately
- [ ] Can create, rename, delete (local & remote), push to remote from the sheet
- [ ] Default branch name can be detected per repository
- [ ] `plans/README.md` status row updated for this plan

## STOP conditions

Stop and report back (do not improvise) if:
- The code at the locations in "Current state" doesn't match the excerpts
- A step's verification fails twice after a reasonable fix attempt
- The fix appears to require touching an out-of-scope file
- The branch management sheet becomes too complex for a single file — split if needed

## Maintenance notes

- `BranchManagementSheet.swift` will grow; consider extracting sub-views
  (search bar, section list, action sheet) when it exceeds ~400 lines
- The `BranchInfo` model feeds into the command palette (plan 006)
- Future: add column sorting, batch operations
