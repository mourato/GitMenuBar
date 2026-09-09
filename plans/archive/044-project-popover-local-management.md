# Plan 044: Move project name management into the Projects popover

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 94f2814..HEAD -- .interface-design/system.md GitMenuBar/Components/Projects GitMenuBar/Pages/MainMenu GitMenuBar/Pages/Settings GitMenuBar/Services/Persistence/RecentProjectsStore.swift GitMenuBarTests`
>
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/043-named-project-references.md
- **Category**: direction
- **Planned at**: commit `94f2814`, 2026-07-29

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: `no`
- **Reviewer required**: `yes` — this changes a primary menu-bar popover, local persistence, destructive confirmation copy, and the locked interface contract.
- **Rationale**: The work is conceptually bounded, but the same user action surface now coordinates hover-only controls, native menus, rename input, removal confirmation, persistence updates, Settings cleanup, and current-project state.
- **Escalate when**: implementation requires a new window/controller, broad `GitManager` state changes, remote repository mutations, or changes outside the in-scope files.

## Why this matters

Project display names were added in Plan 043 but the editing surface landed in Settings. That makes a frequent project-list action feel like a preference instead of item management. The Projects popover is already where users choose and add projects, so it should also own local project actions: rename, reveal in Finder, and remove from GitMenuBar.

This plan keeps the operational invariant from Plan 043: the folder path remains the only identity used for Git operations. Custom names and removal from the list are local GitMenuBar metadata only; they must not rename folders, alter Git remotes, or delete repositories.

## Current state

- `GitMenuBar/Components/Projects/ProjectSelectorPopover.swift` — renders the Projects popover. It currently shows the ellipsis only for the current project and keeps "Choose Repository..." as a full-width row:

```swift
// GitMenuBar/Components/Projects/ProjectSelectorPopover.swift:17
var body: some View {
    List {
        Section("Projects") {
            ForEach(recentProjects) { project in
                let path = project.path
                let isCurrentProject = path == normalizedCurrentRepoPath
                HStack(spacing: WorkbenchMetrics.compactSpacing) {
                    Button(action: { onSelectPath(path) }, label: {
                        HStack(spacing: 6) {
                            Image(systemName: isCurrentProject ? "checkmark.circle.fill" : "circle")
                            ...
                        }
                    })
                    .buttonStyle(.plain)
                    .workbenchRow(isSelected: isCurrentProject)

                    if isCurrentProject, let onShowRepositoryOptions {
                        MainMenuHeaderIconButton(
                            systemImage: "ellipsis.circle",
                            accessibilityLabel: "Repository options",
                            accessibilityHint: "Shows repository visibility and deletion actions.",
                            action: onShowRepositoryOptions
                        )
                    }
                }
            }
        }

        Section {
            Button(action: onBrowse) {
                Label("Choose Repository…", systemImage: "folder")
            }
            .workbenchRow()
        }
    }
}
```

- `GitMenuBar/Pages/MainMenu/MainMenuContent.swift` — wires the popover from the main view. It currently passes `onSelectPath`, `onBrowse`, and current-repository `onShowRepositoryOptions` only:

```swift
// GitMenuBar/Pages/MainMenu/MainMenuContent.swift:271
ProjectSelectorPopoverView(
    recentProjects: recentProjects,
    currentRepoPath: currentRepoPath,
    onSelectPath: { path in
        showProjectSelector = false
        switchRepository(path: path)
    },
    onBrowse: {
        showProjectSelector = false
        selectDirectory()
    },
    onShowRepositoryOptions: canPresentRepositoryOptions ? {
        requestRepositoryOptionsPopoverPresentation()
    } : nil
)
```

- `GitMenuBar/Services/Persistence/RecentProjectsStore.swift` — persists `[ProjectReference]`, supports add/rename/display, and has no removal API:

```swift
// GitMenuBar/Services/Persistence/RecentProjectsStore.swift:54
func add(_ path: String) {
    upsert(path: path)
}

func upsert(path: String, name: String? = nil) {
    let normalizedPath = Self.normalize(path)
    var current = recentProjects()
    let existing = current.first { $0.path == normalizedPath }
    let project = ProjectReference(path: normalizedPath, name: name ?? existing?.name)
    current.removeAll { $0.path == normalizedPath }
    current.insert(project, at: 0)
    write(Array(current.prefix(maxCount)))
}

func rename(path: String, name: String) {
    upsert(path: path, name: name)
}
```

- `GitMenuBar/Pages/Settings/SettingsPage.swift` — Git settings currently own the project-name text field that must move to the popover:

```swift
// GitMenuBar/Pages/Settings/SettingsPage.swift:127
Section {
    TextField(
        "Project Name",
        text: Binding(
            get: { projectName },
            set: { updateProjectName($0) }
        )
    )
    .disabled(repositoryPath.isEmpty)
    .onSubmit { normalizeProjectNameField() }
} header: {
    SettingsFormSectionHeader(title: "Project", icon: "tag")
}
```

- `.interface-design/system.md` locks the previous behavior and must be updated as part of this plan:

```markdown
<!-- .interface-design/system.md:167 -->
- Repository Options (ellipsis) lives on the **current** project row inside the Projects popover only (hidden when options unavailable or row is not current). Keep project-button context menu + status-item / command-center entry points; remove header ellipsis and the popover footer “Repository Options…” duplicate.
- Opening row options: close Projects, then present Repository Options anchored to the project-selector control (existing pending-presentation flow).
```

## Product and design decisions

Intent checkpoint:

- **Who**: a developer mid-flow between editor and terminal, switching repositories without opening Settings.
- **Verb**: choose a project, add a project, or manage one row's local identity.
- **Feel**: dense macOS workbench; calm, native, and local-only for project metadata.
- **Hierarchy**: project selection remains the primary row action. Ellipsis is secondary and hover-revealed. Add Project moves to the section header as compact icon chrome.
- **Depth**: keep the Projects popover one elevation above the main panel using `workbenchPanelSurface`. Use a native `Menu` for ellipsis actions and a lightweight rename overlay inside the popover, not a new app window.
- **Typography/spacing**: reuse `WorkbenchTypography`, `WorkbenchMetrics`, `WorkbenchPalette`, and `WorkbenchMotion`.

Concrete UX decisions:

- Every project row gets an ellipsis icon button.
- The ellipsis button is visually visible only while its row is hovered or its menu/overlay is active. It must not leave an invisible clickable trap when idle.
- Keep a keyboard/context-menu equivalent for accessibility even when the visual ellipsis is hidden.
- Use a native SwiftUI `Menu` for item actions:
  - `Rename Project…`
  - `Reveal in Finder`
  - `Remove from GitMenuBar…`
  - Current project only, when available: separator + `Repository Options…`
- Use a separate rename overlay with a focused text field:
  - Title: `Rename Project`
  - Field label: `Project name`
  - Helper text: `Only the name shown in GitMenuBar changes.`
  - Buttons: `Cancel`, `Save`
- Use a system alert before removal:
  - Title: `Remove “<project name>” from GitMenuBar?`
  - Message: `This only removes the project from this list. The folder, local repository, and remote repository are not deleted.`
  - If removing the active project, append: `GitMenuBar will stop using it until you choose it again.`
  - Buttons: `Cancel`, destructive `Remove`
- Move `Choose Repository…` out of the bottom row. Add a top-right icon button in the Projects section header using `folder.badge.plus` if available by symbol name. Accessibility label: `Add project`. Help/hint: `Choose a repository folder to add to GitMenuBar.`
- Remove project-name editing from Settings. Settings may keep repository path and recent project selection, but it must not expose a second rename surface.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift check | `git diff --stat 94f2814..HEAD -- .interface-design/system.md GitMenuBar/Components/Projects GitMenuBar/Pages/MainMenu GitMenuBar/Pages/Settings GitMenuBar/Services/Persistence/RecentProjectsStore.swift GitMenuBarTests` | Empty, or only understood drift that still matches this plan |
| Changed-file lint/build | `make agent-check` | exit 0; known baseline warnings may appear |
| Tests | `make test` | exit 0; all tests pass |
| Full lint | `make lint` | exit 0; current baseline warnings may appear |
| Plan metadata | `make guidance-check` | exit 0 |
| Whitespace | `git diff --check` | exit 0 |

## Suggested executor toolkit

- Use `macos-app-engineering` for SwiftUI/AppKit state, popover ownership, and `NSWorkspace` reveal behavior.
- Use `menubar` for status-item popover dismissal and current-project selection invariants.
- Use `apple-design` and `.interface-design/system.md` for workbench density, hover, motion, and popover hierarchy.
- Use `accessibility-audit` for hover-only controls, menu/context-menu equivalents, alert focus, and VoiceOver labels.
- Use `ux-writing` for destructive confirmation and local-only helper copy.
- Use `swift-conventions` when editing Swift source.
- Use `swift-testing-expert` if adding or restructuring tests.

## Scope

**In scope**:

- `.interface-design/system.md`
- `GitMenuBar/Components/Projects/ProjectSelectorPopover.swift`
- `GitMenuBar/Components/Projects/RecentProjectsSection.swift` only if needed to remove Settings rename coupling or keep recents compile-compatible
- `GitMenuBar/Pages/MainMenu/MainMenuContent.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuView.swift` only for state refresh hooks if needed
- `GitMenuBar/Pages/Settings/SettingsPage.swift`
- `GitMenuBar/Services/Persistence/RecentProjectsStore.swift`
- `GitMenuBarTests/RecentProjectsStoreTests.swift`
- Existing resolver/render tests only if signatures change and they need compile updates

**Out of scope**:

- Renaming folders on disk.
- Changing Git remote names, GitHub repositories, branches, worktrees, or repository visibility.
- Reworking the status-item owner, titlebar layout, Settings shell, or command palette.
- Adding project grouping, pinning, drag sorting, search, or sync.
- Restyling all confirmation dialogs.
- Moving or redesigning `RepositoryOptionsPopoverView` beyond wiring a current-project-only menu item to the existing flow.

## Git workflow

- Branch: `advisor/044-project-popover-local-management`
- Commit message style: Conventional Commits, for example `feat(projects): manage projects from popover`
- Do not push or open a PR unless the operator explicitly instructs it.
- Preserve unrelated local changes. Do not stage `.`.

## Steps

### Step 1: Update the documented interface contract

Edit `.interface-design/system.md` under `Header chrome` to replace the old current-row-only ellipsis rule with the new policy:

- Projects popover rows expose local item options through a hover-revealed ellipsis on every project row.
- The ellipsis menu owns local actions: rename display name, reveal folder in Finder, remove from GitMenuBar.
- The current row may additionally expose `Repository Options…`, separated from local actions, only when `canPresentRepositoryOptions` is true.
- Add Project lives in the Projects section header as icon chrome, not as a full-width row.
- Removal from GitMenuBar is local metadata only and must use a system confirmation alert.

**Verify**: `make guidance-check` -> exits 0.

### Step 2: Add local removal to `RecentProjectsStore`

In `GitMenuBar/Services/Persistence/RecentProjectsStore.swift`, add a narrow API:

```swift
func remove(path: String) {
    let normalizedPath = Self.normalize(path)
    let remaining = recentProjects().filter { $0.path != normalizedPath }
    write(remaining)
}
```

Keep behavior local to the recents store. Do not remove files, clear credentials, touch GitHub, or run Git commands from this store.

Add tests in `GitMenuBarTests/RecentProjectsStoreTests.swift`:

- removing an existing project deletes only that project and preserves order of the remaining projects;
- removing an equivalent normalized path works;
- removing a missing project is a no-op;
- removing one project does not change custom names on remaining projects.

**Verify**: `make test` -> exits 0.

### Step 3: Rework `ProjectSelectorPopoverView` into row-local management

In `GitMenuBar/Components/Projects/ProjectSelectorPopover.swift`:

- Replace the bottom `Choose Repository…` row with a section header `HStack`:
  - leading `Text("Projects")` using existing section/header typography;
  - trailing icon `Button` with `folder.badge.plus`, `.workbenchIcon()`, accessibility label `Add project`, and help/hint `Choose a repository folder to add to GitMenuBar.`
- Introduce a row helper in the same file, for example `ProjectSelectorRowView`, to keep row hover/menu state contained.
- The row helper should render:
  - selection button as the primary row action;
  - checkmark/circle state exactly as today;
  - project `name` primary and abbreviated `path` muted;
  - trailing ellipsis `Menu` on every row.
- The ellipsis control:
  - uses `ellipsis.circle`;
  - is opacity 1 only when row hover is active or its actions are active;
  - disables hit testing when hidden so there is no invisible mouse target;
  - keeps a row `.contextMenu` with the same actions for keyboard/accessibility equivalence.
- Add popover-level state for:
  - project currently being renamed;
  - rename draft;
  - project pending removal confirmation.

Extend the `ProjectSelectorPopoverView` initializer inputs with local action closures:

```swift
let onRenameProject: (String, String) -> Void
let onRevealProject: (String) -> Void
let onRemoveProject: (String) -> Void
let onShowRepositoryOptions: (() -> Void)?
```

If `onShowRepositoryOptions` remains current-project-only, only pass it to the current row. All rows still get rename/reveal/remove.

**Verify**: `make agent-check` -> exits 0.

### Step 4: Add the rename overlay and removal alert

Still in `ProjectSelectorPopover.swift`, add a lightweight rename overlay inside the Projects popover rather than a new window:

- Use a compact `VStack`/popover overlay with title `Rename Project`, a visible `TextField("Project name", text: ...)`, helper text, and `Cancel`/`Save` buttons.
- Focus the text field on presentation where SwiftUI focus state is practical.
- Pre-fill with the current custom/default project name.
- Trim on save by relying on `RecentProjectsStore.rename`, then refresh local row state through `onRenameProject`.
- Treat an empty submitted name as reset-to-default, matching Plan 043's store behavior.
- Dismiss on `Cancel`, `Save`, outside click if supported by the chosen overlay structure, and Escape.

Add a system `.alert` for pending removal:

- Use `Button("Cancel", role: .cancel)`.
- Use `Button("Remove", role: .destructive)` to call `onRemoveProject(project.path)`.
- Copy must state that the folder, local repository, and remote repository are not deleted.
- If the project is current, copy must state GitMenuBar will stop using it until it is chosen again.

Respect `WorkbenchMotion.adaptive(WorkbenchMotion.micro, usesReducedMotion:)` for overlay opacity/visibility transitions, if any. Hover feedback must be supplemental; selection, labels, and the native menu must remain understandable without motion.

**Verify**: `make agent-check` -> exits 0.

### Step 5: Wire actions from `MainMenuView`

In `GitMenuBar/Pages/MainMenu/MainMenuContent.swift`, pass the new closures from `MainMenuView` into `ProjectSelectorPopoverView`:

- `onRenameProject`: call a new `renameProject(path:name:)`;
- `onRevealProject`: call a new `revealProjectInFinder(path:)`;
- `onRemoveProject`: call a new `removeProject(path:)`;
- keep `onShowRepositoryOptions` current-only and preserve `requestRepositoryOptionsPopoverPresentation()`.

In `GitMenuBar/Pages/MainMenu/MainMenuActions.swift`, add helpers:

- `renameProject(path:name:)`:
  - call `recentProjectsStore.rename(path:name:)`;
  - refresh `recentProjectReferences`;
  - refresh render snapshot so the titlebar project name updates if the renamed path is current.
- `revealProjectInFinder(path:)`:
  - call `NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])`;
  - do not switch repositories.
- `removeProject(path:)`:
  - call `recentProjectsStore.remove(path:)`;
  - refresh `recentProjectReferences`;
  - if `RecentProjectsStore.normalize(path) == RecentProjectsStore.normalize(currentRepositoryPath)`, clear the current repository selection with `setCurrentRepositoryPath("")`, close repository-specific popovers, and refresh render/app command state so the header falls back to `Select Project`;
  - do not delete files, call GitHub APIs, or run Git commands.

If clearing the active project exposes stale `GitManager` data in the UI, keep the fix narrow: update the view state enough to hide repository-dependent actions. STOP if this appears to require broad `GitManager` redesign.

**Verify**: `make agent-check` -> exits 0.

### Step 6: Remove rename UI from Settings

In `GitMenuBar/Pages/Settings/SettingsPage.swift`:

- Remove `@State private var projectName`.
- Remove the `Project` section containing `TextField("Project Name", ...)`.
- Remove `updateProjectName(_:)` and `normalizeProjectNameField()`.
- Remove project-name updates from `updateRepositoryPath(_:)` and `applyRepositorySelection(_:)`.
- Keep the repository path, recent projects section, GitHub section, and danger zone intact.

Do not add the new ellipsis management controls to Settings. The single rename surface is the Projects popover.

**Verify**: `make agent-check` -> exits 0.

### Step 7: Update previews and tests

Update `ProjectSelectorPopoverView` previews to exercise:

- current project row with hover/options-capable wiring;
- non-current row with the same ellipsis actions;
- rename overlay state if it is practical to preview through a small preview container.

Keep every new SwiftUI `View` covered by `#Preview` if it is placed in a new file. If all helper views stay in `ProjectSelectorPopover.swift`, update the existing previews there.

Add or update tests:

- `RecentProjectsStoreTests` for `remove(path:)` cases from Step 2.
- If action logic is factored into a small pure helper for current-removal behavior, add a unit test for clearing active selection when the removed path is current.
- Existing resolver/render tests should continue to pass. Do not broaden test fixtures unless signatures require it.

**Verify**: `make test` -> exits 0.

### Step 8: Final validation and review pass

Run the full gate:

```bash
make agent-check
make test
make lint
make guidance-check
git diff --check
```

Expected result:

- all commands exit 0;
- `make lint` may print the existing warning baseline, but must exit 0;
- `git status --short` shows only in-scope files modified.

Perform a source review before commit:

- Confirm no GitHub API or Git command is called for rename/remove.
- Confirm "Remove from GitMenuBar" cannot be confused with `Delete Repository…`.
- Confirm hover-only ellipsis has a keyboard/context-menu equivalent.
- Confirm removing current project clears active selection or otherwise prevents stale current-project UI.

## Test plan

- `GitMenuBarTests/RecentProjectsStoreTests.swift`:
  - `testRemoveDeletesOnlyMatchingProject`
  - `testRemoveNormalizesPathBeforeMatching`
  - `testRemoveMissingProjectIsNoOp`
  - `testRemovePreservesCustomNamesOnRemainingProjects`
- Existing tests to keep green:
  - `GitMenuBarTests/MainMenuRenderSnapshotTests.swift`
  - `GitMenuBarTests/AppCommandResolverTests.swift`
  - `GitMenuBarTests/MainMenuCommandPaletteResolverTests.swift`
  - `GitMenuBarTests/PathDisplayFormatterTests.swift`
- Manual UI checks after build:
  - Open Projects popover; Add Project icon is in the header, not a bottom row.
  - Hover each project row; ellipsis appears only on hover and remains available while menu is open.
  - Non-current row menu offers rename, reveal, and remove.
  - Current row menu offers the same local actions and, when authenticated/available, separated `Repository Options…`.
  - Rename saves display-only name and updates titlebar/popover without changing the folder path.
  - Remove asks for confirmation and does not delete the folder or remote repository.
  - Removing the current project clears or safely resets active project UI.
  - Escape/outside click behavior remains predictable for Projects, rename overlay, and alerts.

## Done criteria

All must hold:

- [ ] `.interface-design/system.md` documents the new Projects popover item-management policy.
- [ ] Settings no longer contains the `Project Name` rename field.
- [ ] Add Project is a top-right icon button in the Projects popover header.
- [ ] Every project row has hover-revealed ellipsis options.
- [ ] Rename is display-only and local to GitMenuBar.
- [ ] Reveal opens/selects the project folder in Finder and does not switch projects.
- [ ] Remove is local to GitMenuBar, confirmed by a system alert, and never deletes folders or remotes.
- [ ] Removing the current project does not leave stale active-project UI.
- [ ] `make agent-check`, `make test`, `make lint`, `make guidance-check`, and `git diff --check` exit 0.
- [ ] `plans/README.md` status row for Plan 044 is updated.

## STOP conditions

Stop and report back if:

- The live code has already moved project management out of Settings or replaced `ProjectSelectorPopoverView`.
- Supporting hover-only ellipsis requires an invisible clickable target with no keyboard/context-menu equivalent.
- Removing the current project requires broad `GitManager` state redesign or destructive Git operations.
- The implementation starts touching GitHub repository visibility/deletion, branch/worktree cleanup, or remote APIs.
- The chosen rename overlay cannot dismiss predictably with Escape/outside click under the current popover structure.
- A validation command fails twice after a reasonable fix attempt.

## Maintenance notes

- `ProjectReference.name` is local display metadata. Future project features such as pinning, grouping, search, or sync should continue to keep path as operational identity.
- Reviewers should scrutinize copy around "Remove" vs. "Delete Repository…" because this app already has remote destructive repository actions.
- If a future Settings IA reintroduces project management, it should link to/open the Projects popover instead of creating a second rename surface.
