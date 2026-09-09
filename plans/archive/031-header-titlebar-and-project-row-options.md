# Plan 031: Align header chrome and move Repository Options into Projects rows

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 7ade5a9..HEAD -- GitMenuBar/Components/Common/MainMenuHeaderView.swift GitMenuBar/Components/Projects/ProjectSelectorPopover.swift GitMenuBar/Pages/MainMenu/MainMenuContent.swift GitMenuBar/Pages/MainMenu/MainMenuRepositoryOptions.swift GitMenuBar/App/StatusBarController.swift .interface-design/system.md plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/030-command-palette-full-window-scrim.md (recommended sequencing; not a hard code dependency)
- **Category**: direction
- **Planned at**: commit `7ade5a9`, 2026-07-25

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: `no`
- **Reviewer required**: `yes` — AppKit titlebar/toolbar embedding + popover presentation lifecycle
- **Rationale**: Touches window chrome alignment and repository-options presentation anchors; not a deterministic Low/Fast edit.
- **Escalate when**: titlebar approach requires rewriting window lifecycle, or options must support non-current repos.

## Why this matters

The header currently stacks below traffic lights, groups project + ellipsis + gear on a material plate, and keeps Repository Options in the header. Product direction: one titlebar line (traffic lights · project · Settings), no header plate, and ellipsis only on the **current** Projects row. This frees chrome and matches `.interface-design/system.md` Header chrome.

## Current state

Header `HStack` wraps project + optional ellipsis + gear, then applies `.workbenchPanelSurface`:

```39:100:GitMenuBar/Components/Common/MainMenuHeaderView.swift
    var body: some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            Button(action: { showProjectSelector.toggle() }, label: { ... })
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsRepositoryOptionsButton {
                MainMenuHeaderIconButton(systemImage: "ellipsis.circle", ...)
                    .popover(isPresented: $showRepositoryOptionsPopover, arrowEdge: .top) {
                        repositoryOptionsContent()
                    }
            }
            MainMenuHeaderIconButton(systemImage: "gearshape", ...)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .workbenchPanelSurface(cornerRadius: WorkbenchMetrics.cornerRadius, material: .thin)
    }
```

Projects popover lists rows with checkmark + path; Repository Options is a **footer** button, not per-row:

```12:45:GitMenuBar/Components/Projects/ProjectSelectorPopover.swift
            Section("Projects") { ForEach(recentPaths) { ... } }
            Section {
                Button(action: onBrowse) { Label("Choose Repository…", ...) }
                if let onShowRepositoryOptions {
                    Button(action: onShowRepositoryOptions) {
                        Label("Repository Options…", systemImage: "ellipsis.circle")
                    }
                }
            }
```

Presentation today closes Projects then shows options from the **header** ellipsis popover (`MainMenuRepositoryOptions.requestRepositoryOptionsPopoverPresentation`). Window already uses `fullSizeContentView` + transparent titlebar (`StatusBarController.configureMainWindowAppearance`) but does **not** embed header controls into the titlebar.

Locked decisions (inline — executor has no chat context):

- Remove header `workbenchPanelSurface` entirely.
- AppKit titlebar/toolbar embedding **required** for true vertical alignment with traffic lights.
- Ellipsis on **current row only**; hide when `canPresentRepositoryOptions` is false; never show for non-current rows.
- Remove header ellipsis + popover footer duplicate; **keep** project context menu + status-item / command-center entry points.
- On row ellipsis: close Projects, then present Repository Options anchored to the **project selector** control (reuse pending-presentation flow).
- Project button **hugs** label; flexible space; gear trailing.

See `.interface-design/system.md` → Header chrome; ADR `docs/adr/0002-window-shell-material-and-titlebar-chrome.md`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift | `git diff --stat 7ade5a9..HEAD -- GitMenuBar/Components/Common/MainMenuHeaderView.swift GitMenuBar/Components/Projects/ProjectSelectorPopover.swift GitMenuBar/App/StatusBarController.swift` | understood |
| Incremental | `make agent-check` | exit 0 |
| Full gate | `make lint && make test` | exit 0 |
| Header plate gone | `rg -n 'workbenchPanelSurface' GitMenuBar/Components/Common/MainMenuHeaderView.swift` | no matches |
| Footer options gone | `rg -n 'Repository Options' GitMenuBar/Components/Projects/ProjectSelectorPopover.swift` | no footer Label; row ellipsis only |

## Suggested executor toolkit

- `macos-app-engineering`, `menubar`, `apple-design`, `accessibility-audit`
- Any new/changed UI `View` needs `#Preview` (AGENTS.md)

## Scope

**In scope**

- `MainMenuHeaderView.swift` — remove plate; remove header ellipsis button; hug project control; trailing Settings only; host Repository Options `.popover` on the project selector (or dedicated anchor view in the header row)
- `StatusBarController.swift` (and small helpers if needed) — embed header controls into titlebar/toolbar so traffic lights, project, and gear share one vertical centerline; preserve `isMovableByWindowBackground` / autosave / auto-hide behavior
- `ProjectSelectorPopover.swift` — per-row ellipsis for current path only when options available; remove footer Repository Options button; ensure row select vs ellipsis are separate hit targets (a11y)
- `MainMenuContent.swift` — wire callbacks; stop passing header `showsRepositoryOptionsButton` as a header trailing control
- `MainMenuRepositoryOptions.swift` — keep pending presentation; retarget anchor assumptions to project control
- Tests that assert header/options presentation tokens if any break
- Previews for header + project selector

**Out of scope**

- Window material/vibrancy shell (Plan 032) — do not set opaque window backgrounds that fight the shell
- Quota redesign (Plan 033)
- Switch-then-open options for non-current projects
- Removing status-item / command-center / context-menu Repository Options
- Settings window titlebar work beyond what’s required for compile (Settings shell is Plan 032)

## Git workflow

- Branch: `feat/031-header-titlebar-projects-options`
- Commit example: `feat(ui): align header with titlebar and move repo options into projects`
- Do NOT push unless asked

## Steps

### Step 1: Projects row ellipsis + remove footer duplicate

- Add trailing `MainMenuHeaderIconButton` (or shared Icon variant) on the row when `path == currentRepoPath` **and** options callback is non-nil.
- Button must not trigger `onSelectPath` (use nested `Button` / `onTapGesture` carefully; prefer explicit button with `buttonStyle`).
- Remove footer “Repository Options…” row.
- Accessibility: distinct label “Repository options” on the ellipsis; row keeps repository name labeling.

**Verify**: `make agent-check` → exit 0

### Step 2: Strip header plate and header ellipsis; hug layout

- Remove `.workbenchPanelSurface` from `MainMenuHeaderView`.
- Remove header ellipsis control; attach `showRepositoryOptionsPopover` to the project selector control.
- Project button: intrinsic width (hug); `Spacer`; Settings gear trailing.
- Keep context menu on project button.

**Verify**: `rg -n 'ellipsis\.circle' GitMenuBar/Components/Common/MainMenuHeaderView.swift` → no matches; `rg -n 'workbenchPanelSurface' GitMenuBar/Components/Common/MainMenuHeaderView.swift` → no matches

### Step 3: Titlebar / toolbar embedding for one-line alignment

Using AppKit (toolbar, titlebar accessory, or equivalent supported pattern for this `NSWindow`):

- Place project selector + Settings in the titlebar region so they vertically align with traffic lights.
- SwiftUI header may become the titlebar content host (NSHostingView) or the SwiftUI body may omit a duplicate header once embedded — pick one source of truth; do not draw two headers.
- Preserve window move, frame autosave, and auto-hide-on-blur behavior.

**Verify**: `make agent-check` → exit 0

### Step 4: Presentation flow regression

Confirm:

- Row ellipsis → closes Projects → opens Repository Options from project anchor (`pendingRepositoryOptionsPresentation` still works).
- Context menu / status menu / command center still open options.
- When `canPresentRepositoryOptions` is false, no ellipsis on the current row.

**Verify**: `make lint && make test` → exit 0

## Test plan

- Update / add focused tests only if presentation token / pending flow gains new branches; model after existing `MainMenuPresentationModelTests`.
- Manual: multi-repo list, current vs non-current ellipsis visibility, options open/close, VoiceOver labels on row vs ellipsis.

## Done criteria

- [ ] Header has no `workbenchPanelSurface` and no ellipsis button
- [ ] Traffic lights, project, Settings share one titlebar line (manual confirmation required in done notes)
- [ ] Ellipsis only on current Projects row when options available
- [ ] Footer Repository Options removed; context menu + command center kept
- [ ] `make lint && make test` exit 0
- [ ] `plans/README.md` status row for 031 updated

## STOP conditions

- Cannot align with traffic lights without breaking `fullSizeContentView` or auto-hide — stop and report with attempted approach.
- Nested popover from row while Projects stays open seems required by code — do **not** invent that; locked decision is close-then-anchor-to-project.
- Drift in Current state excerpts.
- Need to implement options for non-current repos.

## Maintenance notes

- Reviewers: hit targets ≥ 28×28 on ellipsis; no accidental repo switch when opening options.
- Plan 032 will add window vibrancy — avoid opaque header fills here.
- Update Icon variant copy in system.md only if this plan is the one editing docs (prefer leave docs to advisor unless a contradiction appears).
