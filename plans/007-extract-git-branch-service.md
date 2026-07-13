# Plan 007: Decompose GitManager — extract GitBranchService

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `High/Full`
- **Parallelizable**: no; this plan is serial unless a named independent workstream is added during reclassification.
- **Reviewer required**: yes; the plan has high-risk architectural, operational, or integration impact.
- **Rationale**: Refatoração arquitetural de serviço central, mesmo preservando a fachada.
- **Escalate when**: Se mudar contratos públicos, concorrência, persistência ou a ordem de operações Git.

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat bdb2afc..HEAD -- GitMenuBar/Services/Git/GitManager.swift`
> If `GitManager.swift` changed since this plan was written (SHA `bdb2afc`),
> compare the "Current state" excerpts against the live code before proceeding;
> on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: MED
- **Depends on**: none
- **Category**: tech-debt
- **Planned at**: commit `bdb2afc`, 2026-07-08
- **Issue**: (none)

## Why this matters

`GitManager.swift` is a ~2500-line god object responsible for commits, working-tree
state, branch management, remote sync, commit history, and repository wiping. The
most recent feature work (branch management + AI atomic commits) added ~650 lines to
it, pushing it well past a healthy size and making every change harder to scan and
riskier to touch. The thermo-nuclear code-quality review (item 4) flagged this
explicitly.

Extracting the branch-management responsibility into a dedicated `GitBranchService`
removes the single largest self-contained slice (~600 lines) and establishes a
repeatable facade pattern for the remaining slices (atomic commits, commit history).
Critically, the extraction keeps `GitManager`'s public surface identical, so the 37
existing call sites across 4 files do **not** change — only the implementation moves.

## Current state

- `GitMenuBar/Services/Git/GitManager.swift` — the god object. Key collaborators
  created in `init` (lines 50–69):
  - `private let repositoryContext: GitRepositoryContext`
  - `private let commandRunner: GitCommandRunner`
  - `private let commitHistoryParser: CommitHistoryParser`
  - `private let workingTreeParser: WorkingTreeParser`
  - `private var storedRepoPath: String { get { repositoryContext.repositoryPath } ... }`
  - `private func runOnBackground<T>(_:) async -> T` (line 74) — dispatches to a background queue.
  - `private func publishOnMainActor(_:) async` (line 82) — runs an update on the main actor.
  - `private func executeGitCommand(in:args:useAuth:additionalEnvironment:) -> (output:failure:)` (line 1747) — one-line wrapper around `commandRunner.runGitCommand(...)`.
- Branch-related `@Published` state (lines 20–39): `currentBranch`, `isAheadOfRemote`,
  `remoteBranchName`, `behindCount`, `isBehindRemote`, `isRemoteAhead`,
  `availableBranches`, `branchInfos`, `defaultBranchName`.
- Branch methods (the slice to move): `updateBranchInfo` (1177) /
  `updateBranchInfoAsync` (1247), `fetchBranches` (1779) / `fetchBranchesAsync` (1821),
  `fetchLocalBranchesAsync` (1856), `fetchRemoteBranchesAsync` (1871),
  `pushBranchToRemoteAsync` (1889), `deleteRemoteBranchAsync` (1909),
  `getDefaultBranchNameAsync` (1929) / `defaultBranchNameFallback` (1954),
  `resolveBranchInfoAsync` (1971) / `resolveTrackingStatus` (2033) /
  `lastCommitDate` (2072), `checkRemoteStatus` (2080) / `checkRemoteStatusAsync` (2090),
  `switchBranch` (2269), `createBranch` (2335), `createBranchFromCurrentHead` (2238),
  `mergeBranch` (2389), `deleteBranch` (2422), `renameBranch` (2475).
- Callers (do **not** change): 37 sites in `BranchManagementSheet.swift`,
  `MainMenuView.swift`, `MainMenuContent.swift`, `MainMenuOverlays.swift` — all read
  branch state / call branch methods via `gitManager.<branchAPI>`.
- Conventions: services are `ObservableObject` (compare `AICommitCoordinator.swift`,
  `GitManager` itself). Async git work uses `runOnBackground` + `publishOnMainActor`.
  `StatusBarController.swift` already uses Combine to pipe `gitManager.$isRemoteAhead`
  into publishers, so Combine subscriptions are an established pattern here.
- Verification commands (from `AGENTS.md` / `Makefile`): `make build`, `make test`,
  `make lint`. Tests use a real temp git repo via
  `GitManager(repositoryPathOverride:)` — see `GitMenuBarTests/GitManagerBranchOperationsTests.swift`
  as the structural pattern.

## Commands you will need

| Purpose   | Command           | Expected on success |
|-----------|-------------------|---------------------|
| Build     | `make build`      | `Build succeeded`   |
| Test      | `make test`       | `Tests passed`      |
| Lint      | `make lint`       | `Lint checks passed` (warnings allowed; 0 serious) |

## Suggested executor toolkit

- Skill `swift-conventions` for naming / preview conventions if new SwiftUI test
  harnesses are touched (they should not be).
- Read `GitMenuBar/Services/AI/AICommitCoordinator.swift` as the exemplar for an
  `@MainActor ObservableObject` service that owns collaborators and exposes state.

## Scope

**In scope** (the only files you should modify):
- `GitMenuBar/Services/Git/GitBranchService.swift` (create)
- `GitMenuBar/Services/Git/GitManager.swift` (delegate branch APIs to the new service)

**Out of scope** (do NOT touch, even though they look related):
- Atomic-commit methods (`commitAtomicGroupAsync`, `performAtomicCommitsAsync`,
  `diffForChangedFilesAsync`) — separate follow-up slice (`GitAtomicCommitService`).
- Commit-history methods (`fetchCommitHistory`, `loadMoreCommitHistory`,
  `diffForCommit`, `isMergeCommit`, …) — separate follow-up slice.
- Repository wipe (`wipeRepository` + helpers) — high-risk, leave in `GitManager`.
- Working-tree / staging / push / pull methods — leave in `GitManager` for now.
- Any of the 4 caller files — call sites must keep compiling unchanged.

## Git workflow

- Branch: `advisor/007-git-branch-service` (matches repo convention of feature branches).
- Commit per step below; message style: conventional commits
  (example from `git log`: `refactor(git): route refresh entrypoints through async implementations`).
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Create `GitBranchService` with branch state + logic

Create `GitMenuBar/Services/Git/GitBranchService.swift` as
`@MainActor final class GitBranchService: ObservableObject`. It is constructed with
the same collaborators it needs:

```swift
@MainActor
final class GitBranchService: ObservableObject {
    @Published var currentBranch: String = "main"
    @Published var isAheadOfRemote: Bool = false
    @Published var remoteBranchName: String = ""
    @Published var behindCount: Int = 0
    @Published var isBehindRemote: Bool = false
    @Published var isRemoteAhead: Bool = false
    @Published var availableBranches: [String] = []
    @Published var branchInfos: [BranchInfo] = []
    @Published var defaultBranchName: String = "main"

    private let repositoryContext: GitRepositoryContext
    private let commandRunner: GitCommandRunner

    init(repositoryContext: GitRepositoryContext, commandRunner: GitCommandRunner) {
        self.repositoryContext = repositoryContext
        self.commandRunner = commandRunner
    }

    private var storedRepoPath: String { repositoryContext.repositoryPath }

    private func runOnBackground<T>(_ operation: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: operation())
            }
        }
    }

    private func publishOnMainActor(_ update: @escaping @MainActor () -> Void) async {
        await MainActor.run(body: update)
    }

    private func executeGitCommand(
        in directory: String,
        args: [String],
        useAuth: Bool = false
    ) -> (output: String, failure: Bool) {
        commandRunner.runGitCommand(in: directory, args: args, useAuth: useAuth)
    }

    // … move every method listed in "Current state" here, unchanged except for
    // replacing `self.storedRepoPath`/`self.executeGitCommand` (already local)
    // and `self.publishOnMainActor`/`self.runOnBackground` (already local).
}
```

Move the methods verbatim: `updateBranchInfo`, `updateBranchInfoAsync`,
`fetchBranches`, `fetchBranchesAsync`, `fetchLocalBranchesAsync`,
`fetchRemoteBranchesAsync`, `pushBranchToRemoteAsync`, `deleteRemoteBranchAsync`,
`getDefaultBranchNameAsync`, `defaultBranchNameFallback`, `resolveBranchInfoAsync`,
`resolveTrackingStatus`, `lastCommitDate`, `checkRemoteStatus`, `checkRemoteStatusAsync`,
`switchBranch`, `createBranch`, `createBranchFromCurrentHead`, `mergeBranch`,
`deleteBranch`, `renameBranch`. Keep their bodies identical — only the surrounding
class changes. `makeMissingRepositoryError()` is also used by branch methods; move it
(`private func makeMissingRepositoryError() -> NSError`) into the service.

**Verify**: `make build` → `Build succeeded` (the new file compiles with the rest).

### Step 2: Wire `GitBranchService` into `GitManager` and pipe published state

In `GitManager.init` (lines 58–69), after `commandRunner` is created, add:

```swift
let branchService = GitBranchService(
    repositoryContext: repositoryContext,
    commandRunner: commandRunner
)
self.branchService = branchService
pipeBranchServiceState()
```

Add the stored property and the Combine piping (GitManager is a plain
`ObservableObject`; match the existing `StatusBarController` Combine usage):

```swift
private let branchService: GitBranchService

private func pipeBranchServiceState() {
    branchService.$currentBranch.assign(to: &$currentBranch)
    branchService.$isAheadOfRemote.assign(to: &$isAheadOfRemote)
    branchService.$remoteBranchName.assign(to: &$remoteBranchName)
    branchService.$behindCount.assign(to: &$behindCount)
    branchService.$isBehindRemote.assign(to: &$isBehindRemote)
    branchService.$isRemoteAhead.assign(to: &$isRemoteAhead)
    branchService.$availableBranches.assign(to: &$availableBranches)
    branchService.$branchInfos.assign(to: &$branchInfos)
    branchService.$defaultBranchName.assign(to: &$defaultBranchName)
}
```

Keep the `gitManager` `@Published` branch properties declared exactly as today
(lines 20–39) — they remain the public facade and now receive values via the pipe.

**Verify**: `make build` → `Build succeeded`.

### Step 3: Delete the moved branch code from `GitManager` and delegate

For every branch **method** listed in "Current state", replace its body in `GitManager`
with a thin delegate:

```swift
func switchBranch(branchName: String, completion: @escaping (Result<Void, Error>) -> Void) {
    branchService.switchBranch(branchName: branchName, completion: completion)
}
```

Do this for: `updateBranchInfo`, `updateBranchInfoAsync`, `fetchBranches`,
`fetchBranchesAsync`, `fetchLocalBranchesAsync`, `fetchRemoteBranchesAsync`,
`pushBranchToRemoteAsync`, `deleteRemoteBranchAsync`, `getDefaultBranchNameAsync`,
`resolveBranchInfoAsync`, `checkRemoteStatus`, `checkRemoteStatusAsync`,
`createBranchFromCurrentHead`, `switchBranch`, `createBranch`, `mergeBranch`,
`deleteBranch`, `renameBranch`. For `defaultBranchNameFallback`, `resolveTrackingStatus`,
`lastCommitDate` (private helpers used only by the moved methods) — delete them from
`GitManager` entirely (they now live in `GitBranchService`). Also delete
`makeMissingRepositoryError()` from `GitManager` if it is now unused there (verify with
the grep in Done criteria).

`refreshAsync` (line 98) already calls `fetchBranchesAsync()` and
`resolveBranchInfoAsync()` / `getDefaultBranchNameAsync()` / `checkRemoteStatusAsync()`
— these now delegate through `branchService`, so `refreshAsync` needs no change.

**Verify**: `make build` → `Build succeeded`.

### Step 4: Confirm callers are untouched and behavior is identical

Run a grep to prove no branch logic remains in `GitManager` body (only delegates and
the `@Published` declarations):

```
grep -nE "func (switchBranch|createBranch|mergeBranch|deleteBranch|renameBranch|fetchBranches|resolveBranchInfoAsync|getDefaultBranchNameAsync|checkRemoteStatus)" GitMenuBar/Services/Git/GitManager.swift
```

Expected: each match is a one-line delegate body (no `executeGitCommand` / no
`runOnBackground` inside those methods).

**Verify**: `make test` → `Tests passed` (branch ops covered by
`GitManagerBranchOperationsTests`; atomic-commit + history tests unaffected).
`make lint` → `Lint checks passed`.

## Test plan

- No new tests strictly required: `GitMenuBarTests/GitManagerBranchOperationsTests.swift`
  already exercises `fetchLocalBranchesAsync`, `fetchRemoteBranchesAsync`,
  `pushBranchToRemoteAsync`, `deleteRemoteBranchAsync`, `getDefaultBranchNameAsync`,
  `resolveBranchInfoAsync`, `switchBranch`, `createBranch`, `mergeBranch`,
  `deleteBranch`, `renameBranch` against a real temp repo. These must still pass after
  the delegation refactor — same `gitManager.<api>` call sites.
- Add one focused regression test (new `func testBranchServiceStatePipesToManager()` in
  `GitManagerBranchOperationsTests.swift`): after a branch operation, assert
  `gitManager.branchInfos` equals `gitManager.branchService.branchInfos` (access the
  internal `branchService` via `@testable`) to lock in the facade wiring.
- Verification: `make test` → all pass, including the new test.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `make build` exits 0
- [ ] `make test` exits 0; `GitManagerBranchOperationsTests` pass including the new pipe test
- [ ] `make lint` exits 0 (warnings allowed, 0 serious)
- [ ] `grep -rn "func switchBranch\|func createBranch\|func mergeBranch\|func deleteBranch\|func renameBranch\|func fetchBranches\|func resolveBranchInfoAsync\|func getDefaultBranchNameAsync\|func checkRemoteStatus" GitMenuBar/Services/Git/GitManager.swift` shows only delegate bodies (no `executeGitCommand`/git logic inside them)
- [ ] `grep -rn "resolveTrackingStatus\|lastCommitDate\|defaultBranchNameFallback\|makeMissingRepositoryError" GitMenuBar/Services/Git/GitManager.swift` returns no matches (moved/deleted)
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row for 007 updated to DONE

## STOP conditions

Stop and report back (do not improvise) if:

- The code at the locations in "Current state" doesn't match the excerpts (the
  codebase has drifted since `bdb2afc`).
- A step's verification fails twice after a reasonable fix attempt.
- You find a branch `@Published` property that is also written by a non-branch method
  in `GitManager` (would mean the facade pipe is not sufficient) — report which
  property, do not silently drop the write.
- The Combine `assign(to: &$...)` pipe drops updates in a calling view (report which
  view/caller; the fix may require the caller to observe `branchService` directly).

## Maintenance notes

- Future branch work lives in `GitBranchService.swift`, not `GitManager.swift`. Any
  new branch `@Published` must be added to BOTH the service and the `pipeBranchServiceState()`
  mapping, or callers via `gitManager` won't see it.
- Reviewers should scrutinize the `assign(to: &$...)` pipes for retain cycles — they
  are value-type assignments (no capture), so they are safe, but confirm no
  `sink { [weak self] }` was substituted that could drop updates.
- Follow-up slices (deferred, same facade pattern): `GitAtomicCommitService`
  (owns `diffForChangedFilesAsync`, `commitAtomicGroupAsync`, `performAtomicCommitsAsync`
  — pass `changedFiles` in as a parameter since working-tree state stays in
  `GitManager`), and `GitCommitHistoryService` (owns `fetchCommitHistory`,
  `loadMoreCommitHistory`, `diffForCommit`, `isMergeCommit`, …).
- The `runOnBackground` / `publishOnMainActor` / `executeGitCommand` helpers are now
  duplicated in `GitManager` and `GitBranchService`; a later cleanup can lift them into
  a shared `GitExecution` helper used by both.
