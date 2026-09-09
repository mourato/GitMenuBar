# Plan 043: Store and display custom project names

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat a28fdd2..HEAD -- GitMenuBar/Services/Persistence/AppPreferences.swift GitMenuBar/Services/Persistence/RecentProjectsStore.swift GitMenuBar/Utils/Paths/PathDisplayFormatter.swift GitMenuBar/Pages/MainMenu/MainMenuComputed.swift GitMenuBar/Pages/MainMenu/MainMenuView.swift GitMenuBar/Pages/MainMenu/MainMenuActions.swift GitMenuBar/Pages/MainMenu/MainMenuContent.swift GitMenuBar/Pages/MainMenu/MainMenuCommandPaletteResolver.swift GitMenuBar/App/AppCommandCenter.swift GitMenuBar/App/StatusBarController.swift GitMenuBar/App/GitMenuBarApp.swift GitMenuBar/Pages/Settings/SettingsPage.swift GitMenuBar/Components/Projects/ProjectSelectorPopover.swift GitMenuBar/Components/Projects/RecentProjectsSection.swift GitMenuBar/Components/Projects/RecentPathRow.swift GitMenuBar/Components/Projects/RepositoryPathSection.swift GitMenuBarTests/RecentProjectsStoreTests.swift GitMenuBarTests/PathDisplayFormatterTests.swift GitMenuBarTests/AppCommandResolverTests.swift GitMenuBarTests/MainMenuCommandPaletteResolverTests.swift plans/043-named-project-references.md plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: direction
- **Planned at**: commit `a28fdd2`, 2026-07-28

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: `no` — persistence, command-center context, and UI call sites share the same project model.
- **Reviewer required**: `yes` — this changes UserDefaults migration and multiple visible app surfaces.
- **Rationale**: The implementation is conceptually small, but the storage migration from `[String]` to named records and the fan-out through menu bar, popover, Settings, command palette, and context menu make this broader than a deterministic Low/Fast edit.
- **Escalate when**: The change appears to require a database, iCloud sync, deleting old preference keys, multi-window state coordination, or support for duplicate records with the same path.

## Why this matters

GitMenuBar currently treats a project as only a folder path and derives its visible name from the folder's last path component. Users cannot distinguish repositories with generic folder names such as `app`, `frontend`, `website`, or multiple worktrees of the same repo. Store a project record that contains both `name` and `path`, default the name from the folder, and use the custom name anywhere the app presents a project identity while keeping Git operations path-based.

## Current state

- `GitMenuBar/Services/Persistence/RecentProjectsStore.swift` stores only paths as a JSON-encoded `[String]` in `AppPreferences.Keys.recentRepoPaths`:

```swift
// GitMenuBar/Services/Persistence/RecentProjectsStore.swift:18
func recentPaths() -> [String] {
    guard let data = defaults.data(forKey: key) else {
        return []
    }

    return (try? JSONDecoder().decode([String].self, from: data)) ?? []
}
```

- `GitMenuBar/Services/Persistence/AppPreferences.swift:5-7` only defines `gitRepoPath`, `recentRepoPaths`, and `showFullPathInRecents`; there is no preference key or model for a custom display name.
- `GitMenuBar/Utils/Paths/PathDisplayFormatter.swift:12-18` derives the visible project label from `URL(fileURLWithPath: path).lastPathComponent` and uses that for recents unless the user asks to show the full path.
- `GitMenuBar/Pages/MainMenu/MainMenuComputed.swift:72` sets the header name to `"Select Project"` or `PathDisplayFormatter.projectName(from: currentRepoPath)`.
- `GitMenuBar/Components/Projects/ProjectSelectorPopover.swift:20-23` shows each recent row as `lastPathComponent` plus the abbreviated path.
- `GitMenuBar/Pages/Settings/SettingsPage.swift:83-95` keeps `repositoryPath` and `recentPaths` as local `@State`, backed by `RecentProjectsStore().recentPaths()`.
- `GitMenuBar/Pages/Settings/SettingsPage.swift:112-129` has a Git Settings section for the repository path and a separate Recent Projects section, but no project name field.
- `GitMenuBar/App/AppCommandCenter.swift:177-185` and `GitMenuBar/Pages/MainMenu/MainMenuCommandPaletteResolver.swift:84-91` build recent-project commands from paths and derive titles from `PathDisplayFormatter.projectName(from:)`.
- `GitMenuBar/App/StatusBarController+ContextMenu.swift:59-67` uses command-center recent project titles for the status-item context menu and stores the path as `representedObject`.
- Existing tests to mirror:
  - `GitMenuBarTests/RecentProjectsStoreTests.swift:4-28` covers add, dedupe, and max-count behavior.
  - `GitMenuBarTests/PathDisplayFormatterTests.swift:4-22` covers folder-name and full-path labels.
  - `GitMenuBarTests/AppCommandResolverTests.swift:43-88` covers recent-project filtering and limits.
  - `GitMenuBarTests/MainMenuCommandPaletteResolverTests.swift:43-92` covers command-palette recent-project filtering and limits.

Repo and design conventions:

- SwiftUI UI files include previews. If you add a new UI-rendering Swift file, add a `#Preview`.
- Xcode uses file-system synchronized groups, so new Swift files under `GitMenuBar/` and `GitMenuBarTests/` should be picked up without manual `.pbxproj` edits. Do not edit the Xcode project unless the build proves a file is missing.
- The interface system says the app is a dense macOS workbench, not a dashboard. Use `WorkbenchMetrics`, `WorkbenchTypography`, `WorkbenchPalette`, and native Form rows. Do not add nested `workbenchPanelSurface` plates inside Settings panes.
- Keep project identity separate from Git behavior: path drives repository operations; name is display-only.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift check | `git diff --stat a28fdd2..HEAD -- <in-scope paths>` | Empty output, or only understood drift reconciled against this plan |
| Changed-file lint + Debug build | `make agent-check` | exit 0 |
| Full lint | `make lint` | exit 0 |
| Tests | `make test` | exit 0; XCTest suite passes |

## Suggested executor toolkit

- Use `global:swift-conventions` when touching model/store APIs and tests.
- Use `global:macos-app-engineering` for the SwiftUI/AppKit state flow.
- Use `global:apple-design` and `global:accessibility-audit` if the Settings or project popover UI grows beyond the fields described here.

## Scope

**In scope**:
- Add a `Codable`, `Equatable`, `Identifiable` project record that stores `path` and `name` together.
- Migrate legacy `recentRepoPaths` data encoded as `[String]` into named project records with `name = folder lastPathComponent`.
- Preserve existing current-repository path storage under `AppPreferences.Keys.gitRepoPath`.
- Add a Git Settings `Project Name` field for the selected repository. Empty or whitespace-only input must reset to the default folder name, not persist an empty display name.
- Display custom names in the main header, Projects popover, Settings recents, command palette recents, and status-item `Open Recent` submenu.
- Keep full/abbreviated paths visible where they exist today, especially as subtitles/tooltips.
- Update unit tests for storage migration, name editing semantics, render snapshot/current name, command-center recents, and command-palette recents.
- Update `plans/README.md` status row for Plan 043.

**Out of scope**:
- Do not change Git operation paths, repository discovery, remote URLs, branch/worktree cleanup, or the Companion CLI's repository path scope.
- Do not add Settings search, a Settings sidebar, project folders/groups/tags, drag sorting, iCloud sync, or delete/reorder controls.
- Do not allow multiple saved project records for the same normalized path.
- Do not change Repository Options availability. Options remain on the current project row only.
- Do not delete the old preference key; decode it for migration compatibility.

## Git workflow

- Branch: `advisor/043-named-project-references`.
- Commit as one logical unit unless the operator asks otherwise.
- Conventional Commit example: `feat(projects): support custom project display names`.
- Do not push or open a PR unless the operator instructed it.

## Steps

### Step 1: Introduce the named project persistence model

Add a small model, preferably near persistence ownership:

- Either `GitMenuBar/Models/ProjectModels.swift` or `GitMenuBar/Services/Persistence/ProjectReference.swift`.
- Suggested shape:

```swift
struct ProjectReference: Codable, Equatable, Identifiable {
    let path: String
    var name: String

    var id: String { path }
}
```

Add or update formatter helpers so there is exactly one default-name policy:

- `PathDisplayFormatter.defaultProjectName(for path: String) -> String`
- It should return `URL(fileURLWithPath: path).lastPathComponent` when available.
- For empty paths, callers should still show `"Select Project"` rather than asking this helper.
- For paths with no useful last component, fall back to the expanded path's last component or the original path string; do not return an empty name.

Update `RecentProjectsStore` while preserving a compatibility API during the migration:

- Add `recentProjects() -> [ProjectReference]`.
- Keep `recentPaths() -> [String]` temporarily as `recentProjects().map(\.path)` so callers can be migrated incrementally in this plan.
- Add `add(_ path: String, name: String? = nil)` or `upsert(path:name:)`.
- Add `rename(path: String, to rawName: String)`.
- Add `displayName(for path: String) -> String`.
- Decode order for `recentProjects()`:
  1. Try `[ProjectReference]` from the existing key.
  2. If that fails, try legacy `[String]` and map each path to `ProjectReference(path: expandedPath, name: defaultProjectName(for: path))`.
  3. If both fail, return `[]`.
- On every write, encode `[ProjectReference]` back to the same key.
- Normalize incoming paths with `PathDisplayFormatter.expandedPath`.
- Deduplicate by normalized path.
- Preserve an existing custom name when re-adding an existing path without an explicit new name.
- Trim names. If the trimmed name is empty, store the default folder name.

**Verify**: `make agent-check` → exit 0.

### Step 2: Migrate app state from paths to project references

Change state and context APIs so display surfaces receive named records, not raw paths:

- `MainMenuRenderSnapshot` should hold `recentProjects: [ProjectReference]` and `currentProjectName: String`.
- `MainMenuRenderSnapshot.build(...)` should accept `recentProjects: [ProjectReference]`, look up the current path by normalized path, and use its `name`; fallback to `PathDisplayFormatter.defaultProjectName(for:)`.
- `MainMenuView` should replace `recentProjectPaths` with `recentProjects`, loaded from `RecentProjectsStore().recentProjects()`.
- `reloadRepositorySelectionSnapshot()` should refresh both `currentRepositoryPath` and `recentProjects`.
- `addToRecents(_:)` should call the store and then reload `recentProjects`.
- `setCurrentRepositoryPath(_:)` must continue writing only the path to `AppPreferences.Keys.gitRepoPath`.
- `AppCommandContext` should use `recentProjects: [ProjectReference]` instead of `recentPaths: [String]`.
- `AppCommandResolver.resolveSnapshot` should filter by `project.path`, title from `project.name`, subtitle from `PathDisplayFormatter.abbreviatedPath(project.path)`, and keep invocation payloads as paths.
- `MainMenuCommandPaletteResolver.resolveItems` should do the same.
- `StatusBarController.refreshAppCommands()` should pass `RecentProjectsStore().recentProjects()`.

Do not change `AppCommandInvocation.recentProject(path:)` or `MainMenuCommandPaletteKind.recentProject(path:)`; commands still select by path.

**Verify**: `make agent-check` → exit 0.

### Step 3: Add the Settings editing surface

Update the Git Settings pane to edit the selected project's display name:

- Add `@State private var projectName = ""`.
- On initialization/appear, load `projectName` with `RecentProjectsStore().displayName(for: repositoryPath)` when `repositoryPath` is non-empty; otherwise use an empty string.
- Add a `TextField("Project Name", text: ...)` in the Git pane, near the Repository Path section. Prefer a native Form row in the existing section or a small adjacent `Section` headed `Project Identity`; do not create a nested panel/card.
- Disable or hide the name field when no repository path is selected.
- On commit/change of the field, call `recentProjectsStore.rename(path: repositoryPath, to: newValue)`, then refresh local `recentProjects` and `projectName`.
- When `applyRepositorySelection(_:)` selects a new path, call `recentProjectsStore.add(normalizedPath)` before reading display name so the default folder name exists beside the path.
- When `updateRepositoryPath(_:)` changes the current path via text input, ensure a non-empty normalized path is represented in the store before updating `projectName`.

Accessibility and UX requirements:

- The field label must be visible as `Project Name`.
- The full path remains visible in `Repository Path` and recents as today.
- Empty/whitespace input resets to the default folder name.
- Custom names should truncate safely in compact project rows; do not widen the main window.

**Verify**: `make agent-check` → exit 0.

### Step 4: Update project display call sites

Wire named records through the visible surfaces:

- `ProjectSelectorPopoverView` should accept `recentProjects: [ProjectReference]` and render `project.name` as primary text and `PathDisplayFormatter.abbreviatedPath(project.path)` as secondary text.
- `RecentProjectsSection` should accept `[ProjectReference]`, filter by `project.path != currentRepoPath`, preserve the existing `showFullPathInRecents` behavior, and use:
  - custom `project.name` when `showFullPathInRecents == false`
  - abbreviated `project.path` when `showFullPathInRecents == true`
- `RecentPathRowView` can keep `displayText` and `fullPath`; only its callers need to pass the named project title.
- `MainMenuHeaderToolbarContent` should continue receiving the already-resolved `currentProjectName`.
- `AppRecentProjectCommand.title` should receive the custom name; `subtitle` should remain the path.
- Update previews to include at least one custom name that differs from the folder name.

Do not remove path subtitles/tooltips; the user explicitly needs the name to exist with the folder path.

**Verify**: `make agent-check` → exit 0.

### Step 5: Add regression tests

Extend existing XCTest files; do not add a UI snapshot harness.

Update `GitMenuBarTests/RecentProjectsStoreTests.swift`:

- Decode legacy `[String]` data into `[ProjectReference]` with folder default names.
- Adding an existing path without a name moves it to the top and preserves the custom name.
- Adding an existing path with a name updates the custom name.
- Renaming trims whitespace and rejects empty names by restoring the default folder name.
- `recentPaths()` remains path-only compatibility output until all callers are migrated or the helper is intentionally removed.

Update `GitMenuBarTests/PathDisplayFormatterTests.swift`:

- Rename expectations from `projectName(from:)` to the new default-name helper if you rename the API.
- Cover empty or trailing-slash path behavior if the helper contains fallback logic.

Update `GitMenuBarTests/AppCommandResolverTests.swift`:

- Pass `recentProjects` with a custom name and assert `snapshot.recentProjects.first?.title == <custom name>`.
- Keep assertions that current repo is excluded and only five recents show.

Update `GitMenuBarTests/MainMenuCommandPaletteResolverTests.swift`:

- Pass named recent projects and assert palette titles use custom names while `.kind` still carries `.recentProject(path:)`.

Add a focused test for `MainMenuRenderSnapshot.build` if no existing file covers it:

- Current path `/tmp/worktrees/client-a`.
- Recent project record `ProjectReference(path: "/tmp/worktrees/client-a", name: "Client A")`.
- Assert `snapshot.currentProjectName == "Client A"`.
- Assert fallback remains the folder name when the record is absent.

**Verify**: `make test` → exit 0 and the XCTest suite passes.

### Step 6: Full validation and index update

Run the repo gates:

**Verify**: `make lint` → exit 0.  
**Verify**: `make test` → exit 0.  
**Verify**: `make agent-check` → exit 0.

Update `plans/README.md` Plan 043 status from TODO to DONE only after the code and validation are complete.

## Test plan

- Unit tests in `RecentProjectsStoreTests` cover persistence, migration, dedupe, default names, and rename semantics.
- Unit tests in command resolver files cover display names in command palette and status-item context-menu source data.
- A render-snapshot test covers the main header name resolution.
- Existing previews for the project selector and Settings project rows compile with named project data.
- Manual check after `make build`: select a repo, set a custom project name in Settings, confirm the titlebar project selector and Projects popover show the custom name while the folder path remains visible.

## Done criteria

- [ ] A persisted project record stores `name` and `path` together.
- [ ] Legacy `[String]` recent-project data migrates without losing paths.
- [ ] Default display name is the folder name for every project without a custom name.
- [ ] Empty custom name resets to the folder default instead of showing blank UI.
- [ ] Main titlebar project selector shows the custom current project name.
- [ ] Projects popover, Settings recents, command palette, and status-item `Open Recent` use custom names with paths preserved as subtitles/tooltips.
- [ ] Git operations and command invocations continue to use paths, not display names.
- [ ] `make lint`, `make test`, and `make agent-check` pass.
- [ ] No files outside the in-scope list are modified, except if Xcode proves a project-file update is required.
- [ ] `plans/README.md` status row for 043 is updated.

## STOP conditions

Stop and report back if:

- The code at the locations in "Current state" no longer matches the described storage or call-site shape.
- Existing persisted data cannot be decoded safely without deleting `recentRepoPaths`.
- Supporting custom names appears to require changing `gitRepoPath` semantics or passing names into Git commands.
- The implementation requires project grouping, drag sorting, sync, or duplicate same-path records to satisfy the request.
- A validation command fails twice after a reasonable fix attempt.

## Maintenance notes

- Treat `ProjectReference.name` as display-only. Reviewers should reject any use of the custom name for filesystem, Git, or GitHub operations.
- If future project management adds delete/reorder/pin/grouping, keep it in `RecentProjectsStore` or a successor store with explicit migration tests.
- When removing the temporary `recentPaths()` compatibility helper later, first run `rg -n "recentPaths\\(" GitMenuBar GitMenuBarTests` and update all callers intentionally.
