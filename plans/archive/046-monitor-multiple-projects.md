# Plan 046: Monitor multiple projects from a sidebar

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report - do not improvise. When done, update the status row for this plan
> in `plans/README.md` - unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 9ff2669..HEAD -- CONTEXT.md .interface-design/system.md docs/adr/0004-multi-project-monitoring-snapshots.md GitMenuBar/App GitMenuBar/Components/Projects GitMenuBar/Pages/MainMenu GitMenuBar/Services/Git GitMenuBar/Services/Persistence GitMenuBarTests plans/046-monitor-multiple-projects.md plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P0
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: plans/043-named-project-references.md, plans/044-project-popover-local-management.md, plans/045-polish-transient-overlay-experience.md
- **Category**: direction
- **Planned at**: commit `9ff2669`, 2026-07-29

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `High/Full`
- **Parallelizable**: `no` - persistence, refresh scheduling, status-item badge, command routing, and main-menu layout all share project identity and selection state.
- **Reviewer required**: `yes` - this changes app lifecycle state, periodic Git command execution, persisted project metadata, and the primary menu-bar window layout.
- **Rationale**: The feature is conceptually clear but broad. It must preserve the selected-repository workflow while adding a new monitoring subsystem that scans multiple paths without racing the existing single-repository `GitManager`.
- **Escalate when**: implementation appears to require changing commit/push/pull behavior for non-selected repositories, adding a database, running network fetches automatically, changing the Companion CLI repository path scope, or rewriting the main window as a separate multi-window app.

## Why this matters

GitMenuBar currently answers "what is happening in this one repository?" Developers often work across many local repositories and need to know whether every project is committed and synchronized without switching one by one. This plan adds a Projects sidebar and a lightweight monitoring service so users can scan all monitored projects, while keeping full Git actions scoped to the selected project.

## Current state

- `CONTEXT.md` defines the product terms:
  - **Monitored Project** is local app metadata for a project GitMenuBar keeps in its Projects surface.
  - **Attention State** summarizes whether a Monitored Project needs action, is clean, is unavailable, or is refreshing.
- `docs/adr/0004-multi-project-monitoring-snapshots.md` locks the architecture: multi-project monitoring uses lightweight per-path snapshots; `GitManager` stays selected-repository only.
- `.interface-design/system.md` now defines a split workbench with a Projects sidebar, not a project-management popover.

Relevant code facts:

- The active repository is a single `UserDefaults` string behind `GitRepositoryContext`:

```swift
// GitMenuBar/Services/Git/GitRepositoryContext.swift
var repositoryPath: String {
    get {
        if let overridePath {
            return overridePath
        }
        return defaults.string(forKey: AppPreferences.Keys.gitRepoPath) ?? ""
    }
    set {
        guard overridePath == nil else {
            return
        }
        defaults.set(newValue, forKey: AppPreferences.Keys.gitRepoPath)
    }
}
```

- `GitManager` publishes the selected repository's full state and refreshes many expensive surfaces:

```swift
// GitMenuBar/Services/Git/GitManager.swift
@Published var uncommittedFiles: [String] = []
@Published var stagedFiles: [WorkingTreeFile] = []
@Published var changedFiles: [WorkingTreeFile] = []
@Published var currentBranch: String = "main"
@Published var isAheadOfRemote: Bool = false
@Published var isRemoteAhead: Bool = false
@Published var behindCount: Int = 0
```

- The current menu-bar badge observes only active-repository uncommitted files and a 30-second timer updates that one repository:

```swift
// GitMenuBar/App/StatusBarController.swift
gitManager.$uncommittedFiles
    .receive(on: RunLoop.main)
    .sink { [weak self] files in
        self?.updateStatusItemBadge(count: files.count)
    }

badgeRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
    self?.gitManager.updateUncommittedFiles()
}
```

- `RecentProjectsStore` stores named `ProjectReference` records, deduped by normalized path, but caps at five by default and represents navigation history rather than monitoring intent:

```swift
// GitMenuBar/Services/Persistence/RecentProjectsStore.swift
struct ProjectReference: Codable, Equatable, Identifiable {
    let path: String
    var name: String
}

final class RecentProjectsStore {
    init(
        defaults: UserDefaults = .standard,
        key: String = AppPreferences.Keys.recentRepoPaths,
        maxCount: Int = 5
    )
}
```

- Project selection currently writes `gitRepoPath`, adds to recents, and refreshes the single `GitManager`:

```swift
// GitMenuBar/Pages/MainMenu/MainMenuActions.swift
func switchRepository(path: String) {
    if !gitManager.isGitRepository(at: path), githubAuthManager.isAuthenticated {
        presentationModel.showCreateRepo(path: path)
        return
    }

    setCurrentRepositoryPath(path)
    addToRecents(path)
    gitManager.refresh(includeReflogHistory: false)
}
```

- Existing working-tree parsing computes per-file line stats. Do not reuse that heavy path for background monitoring across many repositories:

```swift
// GitMenuBar/Services/Git/GitManager.swift
let statusResult = self.executeGitCommand(in: repositoryPath, args: ["status", "--porcelain", "-uall"])
let stagedDiffs = self.workingTreeParser.parseNumstat(
    self.executeGitCommand(in: repositoryPath, args: ["diff", "--cached", "--numstat", "--no-renames"]).output
)
let untrackedDiffs = self.workingTreeParser.lineDiffForUntrackedFiles(
    paths: status.untrackedPaths,
    repositoryPath: repositoryPath
)
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift check | `git diff --stat 9ff2669..HEAD -- <in-scope paths>` | Empty output, or only understood drift reconciled against this plan |
| Changed Swift lint + Debug build | `make agent-check` | exit 0 |
| Full lint | `make lint` | exit 0 |
| Tests | `make test` | exit 0; XCTest suite passes |
| Guidance/docs validation | `make guidance-check` | exit 0 |
| Whitespace | `git diff --check` | exit 0 |

## Suggested executor toolkit

- Use `swift-conventions` when adding models, stores, and tests.
- Use `swift-concurrency` if introducing an actor or async queue for repository monitoring.
- Use `macos-app-engineering` for app lifecycle, status item integration, and SwiftUI/AppKit state ownership.
- Use `menubar` for status-item badge and context-menu behavior.
- Use `interface-design`, `apple-design`, `accessibility-audit`, and `ux-writing` when building the sidebar and changing visible copy.
- Use `test-strategy` or `swift-testing-expert` for focused regression tests.

## Scope

**In scope**:

- Add `MonitoredProjectsStore` and new `AppPreferences.Keys` values for monitored projects and sidebar collapsed state.
- Add lightweight multi-project Git status models and a monitoring service/store that publishes per-path Attention State snapshots.
- Seed monitored projects from current repository plus existing recent projects on first launch/use.
- Add/select/remove project flows that keep recents and monitored projects consistent:
  - selecting or adding a valid Git repository adds it to recents and monitored projects;
  - `Stop Monitoring` removes only from monitored projects;
  - `Remove Project` removes from recents and monitored projects.
- Add a Projects sidebar to the main window:
  - visible by default when monitoring is active;
  - collapsible to a rail with attention indicators;
  - groups rows by Needs Attention, Clean, Unavailable;
  - row ellipsis is hover-revealed, with native context-menu equivalent.
- Replace project-management popover usage in the main UI. The titlebar project control should show active context and toggle/focus the sidebar rather than opening a project-management list.
- Update status-item badge to count projects needing attention or unavailable.
- Add command-palette/app-command entries for Add Project, Refresh All Projects, Fetch All Projects, and Open Project.
- Update status-item context menu to prefer monitored projects needing attention.
- Add focused tests for persistence, snapshot classification, scheduling/queue limits where practical, command resolution, badge count, and render/sidebar model behavior.

**Out of scope**:

- Commit, push, pull, branch switching, staging, or discard actions on any non-selected repository.
- Automatic background `git fetch` across all projects.
- Worktree auto-discovery. A worktree can be monitored only if the user adds that path explicitly.
- Search, pinning, drag sorting, project groups/tags, iCloud sync, database storage, or unlimited monitor count.
- GitHub repository visibility checks in the sidebar.
- Companion CLI behavior or repository path scope.
- Rewriting confirmation dialogs beyond the new/remove project confirmations.

## Git workflow

- Branch: `advisor/046-monitor-multiple-projects`
- Commit in logical slices if the operator permits, otherwise one scoped commit.
- Commit message style: Conventional Commits, for example `feat(projects): monitor multiple repositories`.
- Do not push or open a PR unless the operator explicitly instructs it.
- Preserve unrelated local changes. Do not stage `.`.

## Steps

### Step 1: Add monitored-project persistence

Add `MonitoredProjectsStore` near `GitMenuBar/Services/Persistence/RecentProjectsStore.swift`. Reuse `ProjectReference` as the path/name identity and normalize with `RecentProjectsStore.normalize`.

Required behavior:

- New preference key, for example `AppPreferences.Keys.monitoredProjects`.
- Default max count: 20.
- APIs similar to:
  - `monitoredProjects() -> [ProjectReference]`
  - `add(_ path: String, name: String? = nil)`
  - `upsert(path:name:)`
  - `remove(path:)`
  - `contains(path:)`
  - `seedIfNeeded(currentPath:recentProjects:)`
- Add a migration/seed sentinel key so existing users get current repo + recents only once.
- Keep store internals independent from `RecentProjectsStore`; coordinate cross-store removal in app actions, not by making the stores call each other.

Update app/project actions so selecting or adding a valid Git repository writes both stores. Do not add non-Git paths to monitored projects.

**Verify**: `make agent-check` -> exit 0.

### Step 2: Add lightweight project status snapshots

Create models for lightweight monitoring, preferably under `GitMenuBar/Models/` or `GitMenuBar/Services/Git/`:

- `ProjectAttentionClassification`: `clean`, `needsAttention`, `unavailable`, `refreshing`.
- `ProjectAttentionReason`: dirty, ahead, behind, diverged, noUpstream, detached, missing, invalidRepository, error.
- `ProjectStatusSnapshot` with:
  - `project: ProjectReference`
  - `branchName: String`
  - `isDetachedHead: Bool`
  - `stagedCount: Int`
  - `unstagedCount: Int`
  - `untrackedCount: Int`
  - `aheadCount: Int`
  - `behindCount: Int`
  - `hasUpstream: Bool`
  - `lastRefreshedAt: Date?`
  - `lastErrorDescription: String?`
  - computed classification/reasons

Add a lightweight Git reader that runs only cheap commands:

- validate repository with `git rev-parse --show-toplevel`, not just `.git` folder existence;
- local status with `git status --porcelain -uall`, parse counts only;
- branch/detached with `git rev-parse --abbrev-ref HEAD`;
- upstream with `git rev-parse --abbrev-ref --symbolic-full-name @{u}`;
- ahead/behind from local refs with `git rev-list --left-right --count @{u}...HEAD`;
- no line-diff stats, no commit history, no GitHub visibility, no automatic fetch.

Use existing `GitCommandRunner` where practical, but do not route scans through the selected-repository `GitManager`.

**Verify**: `make agent-check` -> exit 0.

### Step 3: Add monitoring service with conservative scheduling

Add a main-actor observable owner such as `ProjectMonitorStore` or `ProjectMonitoringService`.

Required behavior:

- Publishes snapshots keyed by normalized path.
- Refreshes local status:
  - on app launch / first construction;
  - when the main window appears;
  - when selecting a project;
  - every 60 seconds while the app runs.
- Limits local refresh concurrency to 2 repositories.
- Adds explicit `refreshAll()` for local-only status.
- Adds explicit `fetchAll()` that runs `git fetch` one repository at a time, then refreshes that repository's local snapshot.
- Fails per project and keeps successful project snapshots.
- Keeps last known attention classification during a refresh so the menu-bar badge does not drop to zero just because scans are running.

Wire the monitor into `AppDelegate` / `StatusBarController` as an environment object for `MainMenuView`. Avoid singletons unless existing app ownership makes dependency injection impractical.

**Verify**: `make agent-check` -> exit 0.

### Step 4: Build the Projects sidebar shell

Add sidebar UI under `GitMenuBar/Components/Projects/` and integrate it into `MainMenuView`.

Design requirements:

- Use the existing Workbench tokens: `WorkbenchMetrics`, `WorkbenchTypography`, `WorkbenchPalette`, `WorkbenchMotion`.
- No nested cards inside cards.
- Sidebar width when expanded: about 220-260 px.
- When expanded:
  - header contains title `Projects`, Add Project icon, Refresh All, Fetch All, and collapse toggle;
  - rows grouped as Needs Attention, Clean, Unavailable;
  - each row shows project name, branch, and compact badges such as file count, `ahead`, `behind`, `detached`, `no upstream`, or error;
  - active project has selected treatment but does not override attention grouping;
  - ellipsis appears on hover/focus and opens a native `Menu`.
- When collapsed:
  - show a rail, not a fully hidden sidebar;
  - each project remains selectable through an icon/dot row with accessibility label and tooltip;
  - keep a visible aggregate attention indicator;
  - context menu remains available even without visible ellipsis.
- Empty state:
  - if there is no active repository, show an inline Add Project path in the detail area;
  - do not keep the old Projects popover solely for empty/one-project cases.

Add previews for any new SwiftUI view files.

**Verify**: `make agent-check` -> exit 0.

### Step 5: Replace project popover management and wire actions

Change the titlebar project control and old project selector wiring:

- `ProjectSelectorPopoverView` should no longer be the main project-management surface.
- The header project control should show/focus/toggle the sidebar instead of opening a floating project list.
- Add Project should use `DirectoryPickerService`, add the valid Git repository to recents and monitored projects, select it, and refresh both `GitManager` and the monitor snapshot.
- Selecting a sidebar row should:
  - write `AppPreferences.Keys.gitRepoPath`;
  - add/update recent project recency;
  - refresh the selected `GitManager`;
  - refresh that row's monitor snapshot.
- Sidebar row menu actions:
  - Rename project: update display name in both recent and monitored stores when present.
  - Reveal in Finder: use existing Finder reveal behavior.
  - Stop Monitoring: remove only from monitored projects; if it is active, keep the active repository selected until user chooses another.
  - Remove Project: after confirmation, remove from recents and monitored projects; if it is active, clear active repository or route to the empty state consistently with existing `removeProject(path:)` behavior.

If keeping `ProjectSelectorPopoverView` temporarily for compile compatibility, mark it as unused/deprecated in code structure and remove it in this plan before final done criteria unless a STOP condition applies.

**Verify**: `make agent-check` -> exit 0.

### Step 6: Update status item, command palette, and context menu

Status item:

- Badge count becomes number of monitored projects classified as `needsAttention` or `unavailable`.
- `refreshing` uses last known classification for the count.
- Keep existing `StatusItemBadgeRenderer` image behavior; change only the count source unless tests require a small helper.

Commands:

- Extend `AppCommandID`/resolver/palette with:
  - `addProject`
  - `refreshAllProjects`
  - `fetchAllProjects`
  - open monitored project commands, preferably using the existing recent-project command shape or a renamed project command shape.
- Keep command invocations path-based, never name-based.
- Context menu should prefer monitored projects needing attention, then clean monitored/recent projects if there is space. Do not replicate full sidebar management in the status-item menu.

**Verify**: `make agent-check` -> exit 0.

### Step 7: Add regression tests and final cleanup

Add or extend XCTest coverage:

- `MonitoredProjectsStoreTests`:
  - add/upsert/dedupe/max count;
  - one-time seed from active + recents;
  - remove normalizes path;
  - Stop Monitoring vs Remove Project semantics through an action coordinator if added.
- Project snapshot parser/classification tests:
  - clean;
  - dirty staged/unstaged/untracked;
  - ahead;
  - behind;
  - diverged;
  - no upstream;
  - detached;
  - missing/invalid repository.
- Command resolver tests for Add/Refresh/Fetch/Open Project.
- Status item badge count tests for needs attention + unavailable.
- Render/sidebar model tests for grouping and active selection.

Remove unused project popover code, stale state, and dead tests if the sidebar fully replaces them. Provide objective evidence with `rg` before deleting large UI files.

**Verify**:

- `make lint` -> exit 0
- `make test` -> exit 0
- `make guidance-check` -> exit 0
- `git diff --check` -> exit 0

## Test plan

- Unit-test persistence and classification before UI wiring.
- Prefer pure model tests for grouping/ordering so sidebar behavior is verified without fragile UI snapshots.
- Use existing tests as patterns:
  - `GitMenuBarTests/RecentProjectsStoreTests.swift`
  - `GitMenuBarTests/MainMenuRenderSnapshotTests.swift`
  - `GitMenuBarTests/MainMenuCommandPaletteResolverTests.swift`
  - `GitMenuBarTests/StatusItemBadgeRendererTests.swift`
- Add previews for every new SwiftUI-rendering file.

## Done criteria

- [ ] `CONTEXT.md` terms remain accurate and no implementation detail is added there.
- [ ] ADR 0004 remains consistent with the implementation.
- [ ] Monitored projects are persisted separately from recents but coordinated by actions.
- [ ] Selecting/adding a valid Git repository adds it to recents and monitored projects.
- [ ] Removing from recents also removes from monitored projects.
- [ ] Stop Monitoring removes only from monitored projects.
- [ ] Background local refresh uses lightweight snapshots and does not call commit history, per-file diff stats, GitHub visibility, or automatic fetch.
- [ ] Fetch All is explicit and processes one repository at a time.
- [ ] Sidebar is visible by default when monitoring is active and can collapse to a rail.
- [ ] Header no longer opens a project-management popover.
- [ ] Status item badge counts monitored projects needing attention or unavailable.
- [ ] New tests exist and pass.
- [ ] `make lint && make test` exits 0.
- [ ] `make guidance-check` exits 0.
- [ ] `plans/README.md` status row updated.

## STOP conditions

Stop and report back if:

- The live code no longer uses `GitManager` as a single selected-repository facade.
- A lightweight snapshot cannot determine required status without running heavy per-file diff stats or commit history.
- The feature appears to require automatic background fetch to be useful.
- The sidebar cannot be added without rewriting unrelated Settings, branch-management, commit-history, or Companion CLI surfaces.
- A verification command fails twice after a reasonable fix attempt.
- You discover unrelated local changes in in-scope files that conflict with this work.

## Maintenance notes

- Keep `GitManager` focused on the selected repository. Future non-selected project actions should start with a separate product decision and safety review.
- Treat remote state as "based on last fetched refs" unless the user explicitly runs Fetch All or fetches the selected project.
- Reviewers should scrutinize process concurrency, auth prompts, stale snapshot behavior, and whether any Git mutation can accidentally run against a non-selected repository.
- Search, pinning, grouping, and worktree auto-discovery are intentionally deferred until the sidebar proves useful for the 10-project case.
