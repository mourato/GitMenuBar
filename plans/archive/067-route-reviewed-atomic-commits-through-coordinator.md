# Plan 067: Route reviewed Atomic Commits through the action coordinator

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the **STOP conditions** section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat b3c1bf2..HEAD -- GitMenuBar/App/MainMenuActionCoordinator.swift GitMenuBar/App/MainMenuActionCoordinator+AtomicCommits.swift GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift GitMenuBarTests/MainMenuActionCoordinatorTests.swift GitMenuBarTests/MainMenuActionCoordinatorAtomicCommitTests.swift`
> If any in-scope file changed since this plan was written, compare the
> **Current state** excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: HIGH
- **Depends on**: Plan 064 (DONE); reconcile Plan 057's Swift 6.4 toolchain baseline before execution
- **Category**: tech-debt
- **Planned at**: commit `b3c1bf2`, 2026-08-10

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `High/Full`
- **Parallelizable**: `no` — reviewed-sheet execution, automatic execution, status publication, refresh, and commit completion must share one mutation path.
- **Reviewer required**: `yes` — review failure/rollback visibility, push-versus-local semantics, MainActor task ownership, and exactly-once monitor refresh.
- **Rationale**: Plan 064 already provides the hunk snapshot and temporary-index safety boundary. This plan is a narrow orchestration fix, but it changes a destructive commit path and must prove that the reviewed and automatic entry points do not diverge in alerts, progress, refresh, or completion callbacks.
- **Escalate when**: the fix needs to reimplement hunk staging, change the snapshot/index safety contract, alter Companion CLI JSON, add a second commit service, or change reviewed commits from local-only to push.
- **Reuse → extend → create**: reuse `GitManager.performHunkCommitsAsync`, `MainMenuCommitExecutionResult`, `executeCommitOperation`, `onCommitCompleted`, and existing alert/success state; extend the coordinator with one local-only reviewed entry point; create no new workflow service, queue, or mutation protocol.

## Why this matters

The reviewed Atomic Commit sheet currently calls `GitManager.performHunkCommitsAsync` directly. That bypasses `MainMenuActionCoordinator`, so the reviewed path does not publish the normal operation status, failure alert, success message, or centralized `onCommitCompleted` callback that refreshes monitored-project state. The automatic Commit & Push path already uses the coordinator; routing the reviewed plan through the same helper removes the split ownership without touching the hunk safety implementation landed in Plan 064.

## Current state

The executor must confirm these facts before editing:

- `GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift:393-418` — `atomicCommitSheet()` passes an `onCommit` closure that immediately dismisses the sheet, calls `gitManager.performHunkCommitsAsync(groups:snapshot:)`, and directly calls `projectMonitor.refresh(path:)` only on success. It does not use `actionCoordinator` for execution, status, alert, success, or completion callback.
- `GitMenuBar/Components/AI/AtomicCommitReviewSheet.swift:3-13,299-312` — the sheet validates the edited `AtomicCommitExecutionPlan` against the current snapshot and returns the plan through a synchronous `onCommit` closure. Keep the review/generation and plan-validation responsibilities in the sheet.
- `GitMenuBar/App/MainMenuActionCoordinator.swift:242-267` — `performAtomicCommitsAndPush` and `performAutomaticHunkCommitsAndPush` already enter `executeCommitOperation`, clear action state, publish grouping/commit progress, and call the private atomic helper.
- `GitMenuBar/App/MainMenuActionCoordinator.swift:402-455` — the private helper executes either `gitManager.performHunkCommitsAsync` or `performAtomicCommitsAsync`, publishes failure alerts, marks `commitWasCreated`, checks remote status, pushes, refreshes, and publishes success. Its current behavior always proceeds to push after a successful atomic commit unless remote-ahead handling returns first.
- `GitMenuBar/App/MainMenuActionCoordinator.swift:466-478` — `executeCommitOperation` invokes the injected `onCommitCompleted` callback exactly once when `commitWasCreated` is set. `StatusBarController` wires that callback to `projectMonitor.refresh(path:)`.
- `GitMenuBar/Services/Git/GitManager.swift:366-373` — `performHunkCommitsAsync` delegates to `GitAtomicCommitService` and refreshes selected Git state afterward. Do not add another Git refresh inside the service or bypass its snapshot validation.
- `GitMenuBar/Services/Git/GitAtomicCommitService.swift:207-260,290-375` and `GitMenuBarTests/GitManagerAtomicCommitTests.swift:197-332` — hunk execution owns index-lock checks, staged-change rejection, snapshot revalidation, temporary `GIT_INDEX_FILE`, patch cleanup, rollback, and stale/unsafe-plan tests. Those safety guarantees are already covered and are out of this plan.
- `plans/064-hunk-aware-atomic-commits.md` and the README's Plan 064 constraints define hunk-aware menu-bar behavior; untracked/binary/deleted/renamed/unsupported changes remain whole-file selections, and Companion CLI remains file-level.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Drift/status | `git status -sb && git diff --stat b3c1bf2..HEAD -- GitMenuBar/App/MainMenuActionCoordinator.swift GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift GitMenuBarTests/MainMenuActionCoordinatorTests.swift` | clean starting tree and no unexpected in-scope drift |
| Reconfirm bypass | `rg -n -C 8 "performHunkCommitsAsync|performReviewedAtomicCommits|executeAtomicCommitsAndPush|onCommitCompleted" GitMenuBar/App/MainMenuActionCoordinator.swift GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift GitMenuBar/App/StatusBarController.swift` | direct reviewed-sheet execution is identified before editing |
| Focused coordinator tests | `./scripts/xcodebuild-safe.sh --project "$PWD/GitMenuBar.xcodeproj" --scheme GitMenuBar --configuration Debug --derived-data "$PWD/.xcode-build-tests" --destination "platform=macOS,arch=$(uname -m)" --action test-without-building -- -only-testing:GitMenuBarTests/MainMenuActionCoordinatorTests` | all coordinator tests pass after `make test` has built the test bundle |
| Agent check | `make agent-check` | changed Swift lint and Debug app build pass |
| Preview coverage | `./scripts/check-preview.sh GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift` | explicit changed UI candidate passes |
| Tests | `make test` | build-for-testing and full XCTest suite pass |
| Guidance | `make guidance-check` | guidance, plan structure, links, and execution profiles pass |
| Patch hygiene | `git diff --check` | no whitespace errors |
| Merge gate | `make lint && make test` | full lint and full test suite pass |

## Suggested executor toolkit

- Use `swift-concurrency` for MainActor/task ownership and avoiding detached work or duplicated async execution.
- Use `swift-conventions` for Swift naming and lint expectations.
- Use `test-strategy` for temporary-repository and exactly-once callback assertions.
- Use `delivery-workflow` for the mutation-risk validation lanes and final handoff.

## Scope

**In scope** (the only source/test files to modify):

- `GitMenuBar/App/MainMenuActionCoordinator.swift`
- `GitMenuBar/App/MainMenuActionCoordinator+AtomicCommits.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift`
- `GitMenuBarTests/MainMenuActionCoordinatorTests.swift`
- `GitMenuBarTests/MainMenuActionCoordinatorAtomicCommitTests.swift`

`plans/README.md` may be updated only to record the plan's execution status.

**Out of scope** (do not touch):

- `GitMenuBar/Services/Git/GitAtomicCommitService.swift`, `GitManager.swift`, `GitModels.swift`, or Plan 064's hunk/snapshot/index safety behavior.
- `GitMenuBar/Components/AI/AtomicCommitReviewSheet.swift` review controls, AI generation, hunk movement, or validation rules.
- Companion CLI models, JSON, prompt behavior, and file-level CLI execution.
- Push policy for the automatic path, authentication/keychain behavior, remote API behavior, or branch operations.
- A new atomic workflow service, event bus, background queue, or second completion/monitor-refresh callback.
- Unrelated UI copy/design changes; preserve the existing sheet dismissal, haptic, alert, success, and operation-status surfaces unless required to expose the currently hidden failure.

## Git workflow

- Branch: use the repository's current feature-branch convention; do not rewrite `main` or unrelated work.
- Commit after implementation and review with a Conventional Commit such as `refactor(atomic): route reviewed commits through action coordinator`.
- Do not push or open a PR unless the operator explicitly instructs it.
- Keep the commit scoped to the files above plus the plan ledger; do not stage unrelated changes.

## Steps

### Step 1: Reconfirm the two Atomic Commit entry points and safety boundary

Run the drift/status and bypass-audit commands above. Confirm that the reviewed sheet is the only direct UI caller of `performHunkCommitsAsync`, while the automatic path already enters `MainMenuActionCoordinator`. Read the Plan 064 constraints and the existing hunk-service tests before touching the coordinator.

**Verify**: the audit shows one reviewed direct execution closure in `MainMenuOverlays.swift`, one automatic coordinator entry point in `MainMenuActions.swift`, and no need to change the hunk service.

### Step 2: Add a local-only reviewed entry point to `MainMenuActionCoordinator`

Add a public `@MainActor` method such as `performReviewedAtomicCommits(plan:)` that accepts the complete `AtomicCommitExecutionPlan`, guards against an empty plan or a busy coordinator, enters `executeCommitOperation`, clears stale alerts/sync options, and delegates to the existing atomic execution helper.

Refactor only the private helper necessary to make push policy explicit, for example by passing `shouldPush: Bool`. The shared execution sequence must remain:

1. Publish `.committingGroup` progress.
2. Call `gitManager.performHunkCommitsAsync(groups:snapshot:)` for a hunk-backed plan (or preserve the existing file-level branch for the existing public method).
3. On failure, publish the existing split-commit alert and return `.failed` without setting `commitWasCreated`.
4. On success, set `commitWasCreated` so `executeCommitOperation` invokes `onCommitCompleted` once, then refresh remote status as the existing flow requires.
5. For reviewed execution, stop after the local commit and publish the existing local-commit success semantics; never push and never open push/sync options.
6. For automatic/file-level execution, preserve the current remote-ahead, push, refresh, and success behavior exactly.

Do not call `projectMonitor.refresh` here; the existing `onCommitCompleted` callback remains the single monitor-refresh notification at the app boundary.

**Verify**: the focused coordinator test target builds, existing automatic Atomic Commit tests retain their current result semantics, and `rg -n "projectMonitor\.refresh" GitMenuBar/App/MainMenuActionCoordinator.swift` returns no matches.

### Step 3: Replace the reviewed sheet's direct mutation with the coordinator call

In `MainMenuOverlays.atomicCommitSheet()`, keep the sheet's `makeSnapshot`, `generateGroups`, `onCancel`, and plan-validation contract. Replace the direct `gitManager.performHunkCommitsAsync` closure with a `Task` that calls `actionCoordinator.performReviewedAtomicCommits(plan: executionPlan)`. Preserve the current immediate dismissal and trigger success haptic only when the returned result reports `didCommit`. Let the coordinator's published alert/success/status state render through the existing main-window surfaces; do not add a second alert or monitor refresh in the overlay.

**Verify**: `rg -n "performHunkCommitsAsync|projectMonitor\.refresh" GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift` returns no reviewed-sheet execution matches, and the explicit preview command passes.

### Step 4: Add regression coverage for local-only reviewed execution

Extend `GitMenuBarTests/MainMenuActionCoordinatorTests.swift` with a temporary Git repository test that creates changed files, obtains an `AtomicCommitSnapshot`, builds a valid `AtomicCommitExecutionPlan`, and calls `performReviewedAtomicCommits`. Assert that it returns `.committed` without a remote, creates the expected local commit(s), publishes no failure alert, invokes `onCommitCompleted` exactly once, and does not set `showSyncOptions`. Keep the existing automatic test that expects a no-remote push failure; it proves the automatic path did not silently become local-only.

If a stale or invalid reviewed plan is used for an additional case, assert `.failed`, an alert, no completion callback, and no new commit; reuse the existing service safety tests rather than duplicating patch/index assertions.

**Verify**: the focused `MainMenuActionCoordinatorTests` command passes, including the new reviewed-local-only case and existing automatic push behavior.

### Step 5: Validate mutation, UI, and handoff behavior

Run `make agent-check`, the explicit preview command, `make test`, `make guidance-check`, `git diff --check`, and finally `make lint && make test`. Manually verify reviewed Atomic Commit with valid groups, an invalid/stale plan, and automatic Commit & Push with/without a usable remote. Confirm reviewed execution reports progress and failure/success state, refreshes the monitor once after success, never pushes, and leaves Plan 064's fail-closed safety behavior intact. Record the known clean-tree preview-script baseline rather than changing that script here.

**Verify**: all commands pass and the manual matrix shows reviewed-local-only versus automatic-push behavior as specified.

## Test plan

- Extend `GitMenuBarTests/MainMenuActionCoordinatorTests.swift`, following its existing `createTemporaryGitRepository`, `waitForWorkingTreeUpdate`, `makeActionCoordinator`, and `onCommitCompleted` patterns.
- Add a reviewed-plan success test with a local repository and no remote: local commits are created, result is `.committed`, success is published, `showSyncOptions` is false, and completion callback count is one.
- Preserve the existing multi-group automatic test: commits may be created but the final result remains `.failed` when push cannot run, proving automatic behavior is unchanged.
- Add a reviewed-plan failure assertion only if the implementation changes the helper enough to risk error-state regression; prefer a stale snapshot because Plan 064 already defines that failure mode.
- Preserve `GitMenuBarTests/GitManagerAtomicCommitTests.swift` as the authority for snapshot drift, staged-change rejection, rollback, temporary-index cleanup, and hunk safety.
- Verification: `make test` → full XCTest suite passes, including all existing coordinator and Atomic Commit safety tests.

## Done criteria

- [ ] The reviewed Atomic Commit sheet no longer executes Git mutation directly.
- [ ] Reviewed plans execute through `MainMenuActionCoordinator` and are local-only.
- [ ] Automatic Commit & Push retains its push, remote-ahead, alert, refresh, and result semantics.
- [ ] `onCommitCompleted` is the only completion-to-monitor refresh path, and successful reviewed execution triggers it exactly once.
- [ ] Failure state is visible through the existing coordinator alert/status surfaces and does not report a false success.
- [ ] Plan 064's hunk snapshot, temporary-index, stale-plan, rollback, and fail-closed behavior is unchanged.
- [ ] `make agent-check`, explicit preview check, `make test`, `make guidance-check`, `git diff --check`, and `make lint && make test` pass.
- [ ] No files outside the in-scope list and plan ledger are modified; no secrets or runtime state are added.
- [ ] `plans/README.md` status row is updated only after implementation and review.

## STOP conditions

Stop and report back without improvising if:

- Any Current state excerpt no longer matches the live code, especially the direct reviewed-sheet closure or Plan 064 safety boundary.
- Making the reviewed path coordinator-owned requires changing `GitAtomicCommitService`, `GitManager`, the hunk model, or Companion CLI contract.
- The reviewed path would push, open sync options, discard user changes, or bypass snapshot/staged/index validation.
- The implementation introduces a second monitor-refresh callback or causes more than one completion callback for one atomic execution.
- Existing automatic Commit & Push behavior changes without an explicit product decision.
- A validation command fails twice after a reasonable scoped fix, or requires touching an out-of-scope file/script.

## Maintenance notes

- All future Atomic Commit execution entry points should call the action coordinator; review sheets should return plans, not mutate repositories.
- `GitAtomicCommitService` remains the only owner of hunk/index safety, rollback, and runtime patch cleanup. The coordinator owns UI action state, push policy, refresh status, and completion notification.
- Reviewed commits are intentionally local-only because they represent an explicit review step; automatic Commit & Push retains its existing push contract.
- Deferred: extending the Companion CLI to hunk-aware proposals/apply. It needs a separate versioned non-interactive contract and stale-plan semantics, so it must not be smuggled into this UI orchestration fix.
