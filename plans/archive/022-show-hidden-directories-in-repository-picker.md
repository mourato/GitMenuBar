# Plan 022: Show hidden directories in the repository picker

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `ae25cad`, 2026-07-23

## Execution profile

- **Recommended profile**: `implementer-fast`
- **Risk/lane**: `Low/Fast`
- **Parallelizable**: no — the production configuration and its regression test are one small, ordered change
- **Reviewer required**: no — the change is isolated to the shared directory-picker configuration and has deterministic tests
- **Rationale**: the affected behavior is centralized in one AppKit service, the desired state is explicit, and the test does not require launching the panel or changing persistence/Git state
- **Escalate when**: the hidden-item behavior is configured outside `DirectoryPickerService`, a caller depends on overriding `showsHiddenFiles`, the test requires UI automation, or validation requires touching an out-of-scope file

## Why this matters

The repository picker uses `NSOpenPanel`, whose default presentation hides directories whose names begin with a period. This prevents users from selecting valid project repositories such as `.project` or `.config` through the Browse/Choose Repository flows, even though the rest of GitMenuBar can operate on paths containing hidden directory names. The fix should make hidden items visible in every repository-selection flow by changing the shared panel configuration once.

## Current state

- `GitMenuBar/Services/Platform/DirectoryPickerService.swift` owns the shared AppKit directory picker used by the app.
- `GitMenuBar/Pages/Settings/SettingsPage.swift:120-128` calls `selectDirectory` for Settings → Browse.
- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift:202-210` calls it for the main menu's repository selection action.
- `GitMenuBar/App/StatusBarController.swift:896-904` calls it for the status-bar context menu.
- The shared service currently configures the panel as follows:

  ```swift
  let panel = NSOpenPanel()
  panel.allowsMultipleSelection = false
  panel.canChooseDirectories = true
  panel.canChooseFiles = false
  panel.canCreateDirectories = true
  panel.title = title
  panel.prompt = prompt
  panel.worksWhenModal = false
  preparePanel?(panel)
  ```

  (`GitMenuBar/Services/Platform/DirectoryPickerService.swift:15-23`.) It does not set `showsHiddenFiles`, so the panel inherits the system default.
- `preparePanel` is an internal customization hook. No current app caller passes it, but the implementation must preserve its other customization behavior.
- The Xcode project uses `PBXFileSystemSynchronizedRootGroup` for both `GitMenuBar` and `GitMenuBarTests`, so a new Swift test file under `GitMenuBarTests/` is automatically included in the corresponding target; do not edit the Xcode project file for this plan.
- Existing tests use `@testable import GitMenuBar` and XCTest assertions; `GitMenuBarTests/RecentProjectsStoreTests.swift` is a compact example of the repository's test style.
- No `CONTEXT.md`, `DESIGN.md`, `PRODUCT.md`, or ADR currently defines a different hidden-directory policy. This is a reversible UI-default decision, so no ADR is required.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Scope check | `git diff --check` | exits 0 with no whitespace errors |
| Changed-file validation | `make agent-check` | changed Swift lint passes and Debug build exits 0 |
| Full lint | `make lint` | exits 0 |
| Full tests | `make test` | prints `Tests passed` and exits 0 |
| Merge gate | `make lint && make test` | both commands exit 0 |

## Scope

**In scope** (the only implementation files to modify):

- `GitMenuBar/Services/Platform/DirectoryPickerService.swift`
- `GitMenuBarTests/DirectoryPickerServiceTests.swift` (create)
- `plans/README.md` (update Plan 022 status only, after execution)

**Out of scope**:

- `GitMenuBar/Pages/Settings/SettingsPage.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift`
- `GitMenuBar/App/StatusBarController.swift`
- `GitMenuBar/Services/Persistence/RecentProjectsStore.swift`
- Finder preferences, global macOS hidden-file settings, path normalization, recent-project persistence, Git repository detection, and UI redesign
- `GitMenuBar.xcodeproj/project.pbxproj`; the synchronized test group discovers the new test file automatically

## Steps

### Step 1: Isolate the panel configuration and enforce hidden-item visibility

In `GitMenuBar/Services/Platform/DirectoryPickerService.swift`, keep `selectDirectory` responsible for activation, presentation, and completion, but move the panel property setup into a small internal helper that can be exercised without presenting an `NSOpenPanel` in a test. The helper must retain the current defaults: single selection, directories allowed, files disallowed, directory creation allowed, title, prompt, and `worksWhenModal == false`.

Set `panel.showsHiddenFiles = true` as the final hidden-item invariant after `preparePanel?(panel)` has run. This preserves the hook's ability to customize unrelated panel properties while ensuring no current or future repository-picker caller can accidentally turn hidden directories off. Do not add a user preference or a second picker implementation.

Keep `preparePanel` in the same relative lifecycle position: it runs before the panel is made key/front and before `begin` is called. Do not change completion handling, app activation, or the three callers.

**Verify**: `git diff --check` → exit 0; inspect the diff to confirm only the shared service's configuration path changed.

### Step 2: Add a configuration regression test

Create `GitMenuBarTests/DirectoryPickerServiceTests.swift` using the existing XCTest style. Instantiate an `NSOpenPanel` without presenting it and invoke the new configuration helper. Assert at minimum that:

- `showsHiddenFiles` is `true`;
- `canChooseDirectories` is `true`;
- `canChooseFiles` is `false`; and
- a `preparePanel` closure that attempts to set `showsHiddenFiles` to `false` cannot violate the final hidden-item invariant.

Use stable test strings for title and prompt and assert them if the helper exposes those inputs. Do not invoke `selectDirectory`, `begin`, `makeKeyAndOrderFront`, or `orderFrontRegardless` from the unit test; the regression concerns configuration, not AppKit window presentation.

**Verify**: `make test` → the new test passes along with the existing XCTest suite.

### Step 3: Perform focused and full validation

Run `make agent-check` after the Swift changes, then run `make lint && make test`. Confirm the new test file is part of the test target without modifying `GitMenuBar.xcodeproj/project.pbxproj`.

For manual acceptance, launch the app and exercise the repository chooser from Settings, the main menu, and the status-bar context menu. In each panel, navigate to a visible parent containing a directory named `.hidden-project`; confirm it is listed and can be selected. Confirm ordinary visible directories, cancellation, and the existing create-directory behavior still work.

**Verify**: `make agent-check` and `make lint && make test` → all commands exit 0; manual acceptance confirms `.hidden-project` can be selected through all three entry points.

## Test plan

- Add `GitMenuBarTests/DirectoryPickerServiceTests.swift` with an AppKit configuration test that runs without showing a panel.
- Cover the regression (`showsHiddenFiles == true`) and the invariant that the existing customization hook cannot disable it.
- Preserve the current panel-selection contract by asserting directories are selectable and files are not.
- Use `GitMenuBarTests/RecentProjectsStoreTests.swift` as the structural XCTest pattern.
- Run `make test` for the full suite and `make lint` for formatting/lint coverage.

## Done criteria

- [ ] The shared directory picker sets `showsHiddenFiles` to `true` after its customization hook.
- [ ] A new deterministic XCTest proves hidden items remain visible and the final configuration cannot be overridden to `false` by `preparePanel`.
- [ ] Settings, main-menu, and status-bar repository selection continue to use the shared service without caller changes.
- [ ] `make agent-check` exits 0.
- [ ] `make lint && make test` exits 0.
- [ ] Manual checks confirm a directory named `.hidden-project` is selectable through all three entry points.
- [ ] `git status --short` contains no modified files outside the Scope list.
- [ ] The Plan 022 row in `plans/README.md` is updated from TODO to DONE only after all criteria pass.

## STOP conditions

Stop and report back instead of improvising if:

- `DirectoryPickerService.swift` no longer matches the current-state excerpt or no longer owns all three picker flows.
- `preparePanel` is used by an existing caller that intentionally requires `showsHiddenFiles == false`.
- The synchronized Xcode test group does not include the new test automatically and adding it requires an out-of-scope project-file change.
- AppKit cannot instantiate/configure `NSOpenPanel` in the test environment without presenting UI; do not replace the deterministic test with flaky UI automation without approval.
- `make agent-check`, `make lint`, or `make test` fails twice after a reasonable, in-scope correction.
- The change appears to require modifying path display, recent-project storage, Git detection, or Finder preferences.

## Maintenance notes

- Keep hidden-item visibility centralized in `DirectoryPickerService`; new repository-selection entry points should call this service instead of constructing their own `NSOpenPanel`.
- Review future changes to `preparePanel` carefully: it remains a customization hook, but hidden-directory visibility is an intentional service invariant.
- This plan does not change manually typed paths or already stored recent paths; those paths already accept hidden directory names and should remain covered by their existing flows.
