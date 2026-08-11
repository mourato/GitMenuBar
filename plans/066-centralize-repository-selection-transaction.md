# Plan 066: Centralize the selected-repository transaction

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the **STOP conditions** section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat b3c1bf2..HEAD -- GitMenuBar/App/RepositorySelectionCoordinator.swift GitMenuBar/App/StatusBarController.swift GitMenuBar/App/GitMenuBarApp.swift GitMenuBar/Pages/MainMenu/MainMenuView.swift GitMenuBar/Pages/MainMenu/MainMenuActions.swift GitMenuBar/Pages/MainMenu/MainMenuProjectActions.swift GitMenuBar/Pages/MainMenu/MainMenuPreviewHarness.swift GitMenuBarTests/RepositorySelectionCoordinatorTests.swift`
> If any in-scope file changed since this plan was written, compare the
> **Current state** excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: HIGH
- **Depends on**: Plans 050–053 and 059–063 are DONE; reconcile Plan 057's Swift 6.2 baseline before execution
- **Category**: tech-debt
- **Planned at**: commit `b3c1bf2`, 2026-08-10

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `High/Full`
- **Parallelizable**: `no` — picker, recent-project, sidebar, external-URL, and create-repository entry points must agree on one selection transaction.
- **Reviewer required**: `yes` — review persistence ordering, non-Git create flow behavior, MainActor ownership, and stale selected-repository state.
- **Rationale**: The code change is bounded, but it crosses AppKit lifecycle code, SwiftUI state, UserDefaults, recent-project persistence, monitored-project enrollment, and the selected `GitManager` facade. The normal implementer profile is the narrowest safe lane that can validate all entry points and their existing refresh-generation guards.
- **Escalate when**: selection requires an event bus, a second `GitManager`, an asynchronous selection actor, a new persistence schema, or a change to `GitManager`'s selected-refresh cancellation contract.
- **Reuse → extend → create**: reuse `RecentProjectsStore`, `ProjectMonitorStore`, `GitManager.resetSelectedRepositoryState()`, `GitManager.refreshSelectedRepository()`, and `MainMenuPresentationModel`; extend them with one concrete selection coordinator; create no protocol with one implementation, cache, notification bus, or per-project manager.

## Why this matters

The same selected-repository side effects are currently repeated in the status-bar picker, the main-window project selector, and `application(_:open:)`: write `gitRepoPath`, add a recent project, enroll a Git repository in monitoring, and reset selected state. The repetitions already diverge: the main-window path defers a non-Git authenticated folder until repository creation, while the status-bar and external-URL paths persist it immediately. One small transaction will make the mutation order and non-Git policy explicit while leaving route, remote-existence, and window-presentation decisions at their existing owners.

## Current state

The executor must confirm these facts before editing:

- `GitMenuBar/App/StatusBarController.swift:969-988` — `selectRepository(_:)` writes `UserDefaults`, creates a fresh `RecentProjectsStore`, enrolls `projectMonitor`, resets `gitManager`, then opens or refreshes the window. It calls `gitManager.isGitRepository(at:)` twice and currently persists a non-Git path before showing the create-repository route.
- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift:194-224` — `switchRepository(path:)` guards `actionCoordinator.canSwitchRepository`; authenticated non-Git paths go directly to `presentationModel.showCreateRepo`; other paths reset `gitManager`, write the path through `setCurrentRepositoryPath`, call `addToRecents`, and start a selected refresh.
- `GitMenuBar/App/GitMenuBarApp.swift:90-132` — `application(_:open:)` validates the folder, optionally checks GitHub remote existence, then directly writes `gitRepoPath`, adds recents, and adds the monitor before opening the main or create route. `private let recentProjectsStore = RecentProjectsStore()` at `:29` duplicates the store ownership used by other callers.
- `GitMenuBar/Pages/MainMenu/MainMenuProjectActions.swift:8-49` — `addToRecents(_:)` mutates recents and monitor enrollment; `setCurrentRepositoryPath(_:)` writes the selected path. `addToRecents` is only used by the create-repository success path in `MainMenuView.swift:117-132` and can be removed after that path uses the shared transaction.
- `GitMenuBar/Pages/MainMenu/MainMenuView.swift:8-115,117-132` — the view owns `currentRepositoryPath` and `recentProjectReferences` as local state. A successful `CreateRepositoryPageView` currently writes the path and recents separately before refreshing `GitManager`.
- `GitMenuBar/Services/Persistence/RecentProjectsStore.swift:22-101` and `GitMenuBar/Services/Persistence/MonitoredProjectsStore.swift:3-83` intentionally remain separate stores with different limits (5 recent projects versus 20 monitored projects). Do not merge their concepts or persistence keys.
- `GitMenuBar/Services/Git/ProjectMonitorStore.swift:8-16,89-101` — monitor enrollment is path-scoped and `add(path:)` persists through `MonitoredProjectsStore` and starts a refresh. Avoid re-adding an already monitored path during every switch.
- `GitMenuBar/Services/Git/GitManager.swift:138-159,200-260` — selected state is reset independently from selected refresh; selected refresh owns cancellation and generation gating. The coordinator may reset state, but it must not replace or bypass the selected-refresh session.
- ADR 0004 and ADR 0005 establish one selected `GitManager` plus lightweight path-scoped monitoring/cleanup. This plan preserves that boundary; it does not create one manager per monitored project.
- Special-case contract to preserve: an authenticated non-Git folder is a create-repository candidate, not the selected repository, until creation succeeds. A local Git repository whose remote is missing is still a selected local repository; remote existence only chooses the presentation route.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Drift/status | `git status -sb && git diff --stat b3c1bf2..HEAD -- GitMenuBar/App/RepositorySelectionCoordinator.swift GitMenuBar/App/StatusBarController.swift GitMenuBar/App/GitMenuBarApp.swift GitMenuBar/Pages/MainMenu/MainMenuView.swift GitMenuBar/Pages/MainMenu/MainMenuActions.swift GitMenuBar/Pages/MainMenu/MainMenuProjectActions.swift GitMenuBar/Pages/MainMenu/MainMenuPreviewHarness.swift GitMenuBarTests/RepositorySelectionCoordinatorTests.swift` | clean starting tree and no unexpected in-scope drift |
| Reconfirm callers | `rg -n -C 3 "gitRepoPath|RecentProjectsStore\(\).*add|projectMonitor\.add|resetSelectedRepositoryState|switchRepository|application\(_:open" GitMenuBar/App GitMenuBar/Pages/MainMenu GitMenuBar/Services` | every selection mutation is accounted for before editing |
| Focused coordinator tests | `./scripts/xcodebuild-safe.sh --project "$PWD/GitMenuBar.xcodeproj" --scheme GitMenuBar --configuration Debug --derived-data "$PWD/.xcode-build-tests" --destination "platform=macOS,arch=$(uname -m)" --action test-without-building -- -only-testing:GitMenuBarTests/RepositorySelectionCoordinatorTests` | all new selection tests pass after `make test` has built the test bundle |
| Agent check | `make agent-check` | changed Swift lint and Debug app build pass |
| Preview coverage | `./scripts/check-preview.sh GitMenuBar/Pages/MainMenu/MainMenuView.swift GitMenuBar/Pages/MainMenu/MainMenuPreviewHarness.swift` | explicit UI candidates pass |
| Tests | `make test` | build-for-testing and full XCTest suite pass |
| Guidance | `make guidance-check` | guidance, plan structure, links, and execution profiles pass |
| Patch hygiene | `git diff --check` | no whitespace errors |
| Merge gate | `make lint && make test` | full lint and full test suite pass |

## Suggested executor toolkit

- Use `swift-conventions` for Swift naming, formatting, and lint expectations.
- Use `macos-app-engineering` for the AppKit lifecycle and root-view injection boundary.
- Use `test-strategy` for the UserDefaults/store isolation and MainActor test shape.
- Use `delivery-workflow` for the validation lanes and final Git handoff.

## Scope

**In scope** (the only source/test files to modify):

- `GitMenuBar/App/RepositorySelectionCoordinator.swift` (create)
- `GitMenuBar/App/StatusBarController.swift`
- `GitMenuBar/App/GitMenuBarApp.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuView.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuProjectActions.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuPreviewHarness.swift`
- `GitMenuBarTests/RepositorySelectionCoordinatorTests.swift` (create)

`plans/README.md` may be updated only to record the plan's execution status.

**Out of scope** (do not touch):

- `GitMenuBar/Services/Git/GitManager.swift` refresh implementation, refresh-session callbacks, or repository context semantics.
- `RecentProjectsStore`, `MonitoredProjectsStore`, `ProjectMonitorStore`, their keys, limits, seed behavior, or refresh scheduling.
- GitHub remote-existence checks, GitHub authentication, create-repository API behavior, route animation, window placement, and command-palette resolution.
- Project rename/removal semantics except deleting the now-unused selection helper from `MainMenuProjectActions.swift`.
- `CONTEXT.md` or a new ADR; the coordinator name is an implementation detail, while existing selected-repository/monitored-project vocabulary is sufficient.
- Event buses, notification-based selection propagation, protocols/factories with one implementation, caches, persistence migrations, and additional `GitManager` instances.

## Git workflow

- Branch: use the repository's current feature-branch convention; do not rewrite `main` or unrelated work.
- Commit after implementation and review with a Conventional Commit such as `refactor(repository): centralize selected repository transaction`.
- Do not push or open a PR unless the operator explicitly instructs it.
- Keep the commit scoped to the files above plus the plan ledger; do not stage unrelated changes.

## Steps

### Step 1: Reconfirm drift and selection invariants

Run the drift/status and caller-audit commands above. Read the current implementations at the listed locations and confirm the two create-flow rules: authenticated non-Git folders must not replace the current selection before creation, while local Git repositories remain selectable even when the remote is missing. Confirm that `ProjectMonitorStore.add` is the only enrollment operation needed and that `GitManager` remains the single selected-repository facade.

**Verify**: the drift command reports no unexpected change, and the `rg` audit has a written mapping from each direct mutation to the coordinator or an explicitly out-of-scope rename/removal operation.

### Step 2: Add the smallest concrete selection transaction and tests

Create `GitMenuBar/App/RepositorySelectionCoordinator.swift` as a `@MainActor` concrete type with injected `GitManager`, `ProjectMonitorStore`, `UserDefaults`, and `RecentProjectsStore` dependencies. Do not add an interface. Define an equatable result with two outcomes: selected normalized path plus `isGitRepository`, or `requiresRepositoryCreation` with the normalized path.

Implement one operation with this order:

1. Normalize the input with `RecentProjectsStore.normalize` and determine Git status once.
2. If the path is not Git and the caller disallows non-Git selection, return `requiresRepositoryCreation` without writing defaults, recents, monitor state, or selected Git state.
3. Otherwise write `AppPreferences.Keys.gitRepoPath`, add the path to `RecentProjectsStore`, add it to `ProjectMonitorStore` only when it is Git and not already monitored, reset `GitManager` selected state, and return the selected result.

Keep route/window presentation and remote checks out of this type. Add `GitMenuBarTests/RepositorySelectionCoordinatorTests.swift` using an isolated `UserDefaults(suiteName:)`, injected stores, and temporary repositories/directories. Cover existing Git selection, duplicate monitor enrollment avoidance, authenticated non-Git deferral, and allowed non-Git selection when the create flow is not active.

**Verify**: `make test` passes, and the focused `RepositorySelectionCoordinatorTests` command passes with all new cases.

### Step 3: Route every selection entry point through the transaction

Instantiate one coordinator from `StatusBarController` using its existing `gitManager` and `projectMonitor`, inject it into the root `MainMenuView`, and add the same object to `MainMenuPreviewHarness` so previews remain constructible. Remove `AppDelegate`'s private `RecentProjectsStore`.

Update callers as follows:

- `StatusBarController.selectRepository(_:)`: preserve the busy guard and visible-window behavior, call the coordinator once, handle `requiresRepositoryCreation` by opening the create route, and use the selected result for the existing route/refresh logic. Call selected refresh without re-writing the path when the coordinator already persisted it.
- `MainMenuView.switchRepository(path:)`: preserve the busy guard and local presentation cleanup, call the coordinator with non-Git selection allowed only when GitHub authentication is unavailable, update local `currentRepositoryPath`/`recentProjectReferences` from the selected result, then use the existing `MainMenuPresentationModel` refresh callbacks.
- `GitMenuBarApp.application(_:open:)`: keep folder validation and the remote-existence check, but replace every direct path/recent/monitor mutation with one coordinator call. Preserve the remote-exists versus create-route decision and hop to the main actor before invoking the coordinator if the callback requires it.
- `CreateRepositoryPageView` success in `MainMenuView`: call the coordinator after the folder is initialized, update local selection state from its result, then preserve the existing main-route, remote-url, and refresh behavior.

**Verify**: `rg -n "UserDefaults\.standard\.set\([^\n]*gitRepoPath|RecentProjectsStore\(\)\.add|projectMonitor\.add\(path:|gitManager\.resetSelectedRepositoryState" GitMenuBar/App/GitMenuBarApp.swift GitMenuBar/App/StatusBarController.swift GitMenuBar/Pages/MainMenu` shows the shared transaction as the only selection mutation path; `make agent-check` passes.

### Step 4: Remove obsolete duplicate helpers without changing project management

Delete `MainMenuView.addToRecents(_:)` because the create-success path now uses the coordinator. Keep the separate recent/monitor store reads and the rename/remove operations. Retain a narrowly named deselection helper for `removeProject` if needed; it may clear the current path but must not be used to select a repository. Do not change monitored-project cleanup, seed, or sidebar semantics.

**Verify**: `rg -n "addToRecents|setCurrentRepositoryPath" GitMenuBar/Pages/MainMenu` shows no obsolete selection helper and only the intentional current-selection clear path, then rerun the explicit preview command.

### Step 5: Validate behavior and hand off

Run `make agent-check`, the explicit preview command, `make test`, `make guidance-check`, `git diff --check`, and finally `make lint && make test`. Manually verify the picker, recent-project command, Projects sidebar, `open -a GitMenuBar <folder>`, authenticated non-Git create flow, and local Git-without-remote flow. Record any known clean-tree preview-script baseline rather than changing `scripts/check-preview.sh` in this plan.

**Verify**: all commands pass; manual checks show one selected path, one recent entry, at most one monitor enrollment, no stale selected-state flash after switching, and no premature selection for an authenticated non-Git create candidate.

## Test plan

- Add `RepositorySelectionCoordinatorTests` with an isolated defaults suite and injected stores, following the persistence-isolation style in `GitMenuBarTests/MonitoredProjectsStoreTests.swift`.
- Cover selecting an existing Git repository: normalized `gitRepoPath`, recent entry, monitor enrollment, and selected-state reset.
- Cover selecting the same Git repository twice: no duplicate recent/monitor entries and no second monitor enrollment side effect.
- Cover an authenticated non-Git candidate: `requiresRepositoryCreation` and no mutation of selected path, recents, monitor, or GitManager state.
- Cover an allowed non-Git selection: selected normalized path and recent persistence without monitor enrollment.
- Preserve and rerun existing `MainMenuPresentationModelTests`, `MonitoredProjectsStoreTests`, and `GitManagerRefreshStateTests`; the selected-refresh generation behavior is not to be rewritten here.
- Verification: `make test` → full XCTest suite passes, including the four coordinator cases (or the exact count implemented if the executor combines equivalent cases).

## Done criteria

- [ ] `RepositorySelectionCoordinator` is the only shared transaction that writes `gitRepoPath`, adds a recent project, enrolls a selected Git path, and resets selected Git state.
- [ ] Authenticated non-Git folders remain create candidates and do not replace the current selection until creation succeeds.
- [ ] Existing Git paths, including local repositories with missing remotes, preserve their current route and selected-refresh behavior.
- [ ] `RecentProjectsStore` and `ProjectMonitorStore` remain separate with their existing limits and keys.
- [ ] Coordinator tests cover Git, duplicate enrollment, deferred create, and allowed non-Git cases.
- [ ] `make agent-check`, explicit preview check, `make test`, `make guidance-check`, `git diff --check`, and `make lint && make test` pass.
- [ ] No files outside the in-scope list and plan ledger are modified; no secrets or runtime state are added.
- [ ] `plans/README.md` status row is updated only after implementation and review.

## STOP conditions

Stop and report back without improvising if:

- Any Current state excerpt no longer matches the live code, especially the non-Git create ordering or selected-refresh generation behavior.
- The coordinator cannot preserve the authenticated non-Git deferral without changing GitHub API, create-repository, or route ownership.
- A proposed fix needs an event bus, a `GitManager` per monitored project, a persistence migration, or changes to `ProjectMonitorStore`/`GitManager` outside this scope.
- A caller still needs to write the selected path and also call the coordinator to avoid a duplicate mutation.
- A test reveals monitor enrollment or refresh is performed twice for one new selection and the cause is not a simple call-site duplication.
- Any validation command fails twice after a reasonable scoped fix, or requires touching an out-of-scope file/script.

## Maintenance notes

- Future repository-selection entry points must call the coordinator and handle its two outcomes; they must not write `gitRepoPath` or enroll the monitor directly.
- Route and remote-existence decisions intentionally remain at AppKit/SwiftUI owners because the external-URL path has an asynchronous remote check and the main-window path owns local presentation state.
- If selected refresh ever becomes an async value-returning API, preserve the coordinator's mutation-before-refresh ordering and keep generation/cancellation in `GitManager`.
- Deferred: a larger extraction of window presentation/refresh orchestration. It is not justified until traces show route/refresh duplication causes a user-visible defect after this transaction is centralized.
