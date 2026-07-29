# Plan 045: Polish transient overlay experience after removing SwiftUI popovers

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report. Do not reintroduce SwiftUI `.popover`, `NSPopover`, or AppKit
> `showRelativeToRect` presentation for these surfaces.
>
> **Drift check (run first)**:
> `git diff --stat 5419723..HEAD -- GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift GitMenuBar/Pages/MainMenu/MainMenuActions.swift GitMenuBar/Components/Projects/ProjectSelectorPopover.swift GitMenuBar/Components/Branches/BranchSelectorPopover.swift GitMenuBar/Components/Common/RepositoryOptionsPopoverView.swift GitMenuBar/Components/Common/WorkbenchMotion.swift GitMenuBar/Components/Common/WorkbenchPanelSurface.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/044-project-popover-local-management.md (DONE)
- **Category**: tech-debt
- **Planned at**: commit `5419723`, 2026-07-29

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: `no` - the same overlay state and visual helper code is shared by all three transient panels.
- **Reviewer required**: `yes` - this is a compact macOS UI/accessibility change affecting dismissal, focus, depth, and motion.
- **Rationale**: The source diff is small, but it changes user-facing overlay behavior in a menubar app and needs judgment across SwiftUI layout, keyboard handling, Reduce Motion, and Reduce Transparency.
- **Escalate when**: the implementation appears to require AppKit popovers, status-item/window lifecycle changes, persistence changes, or edits outside the in-scope UI files.

## Why this matters

Commit `5419723` correctly removed SwiftUI/AppKit popover presentation from the
main GitMenuBar surface after a macOS ViewBridge/AppKit crash involving
`_NSPopoverWindow` and SafariPlatformSupport remote completion UI. The custom
overlay system avoids that crash-prone platform path, but the first pass left a
few experience mismatches: an invisible click-catcher, inconsistent panel
depth, unanchored placement, raw transition values, and Escape behavior that can
cancel inline rename without closing the overlay. This plan keeps the safer
custom-overlay architecture and brings the interaction back in line with the
GitMenuBar interface system and Apple-style compact overlay behavior.

## Current state

Relevant files and roles:

- `GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift` - owns transient Projects,
  Repository Options, Branch selector, and command palette overlay rendering.
- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift` - owns transient presentation
  dismissal and toggle helpers.
- `GitMenuBar/Components/Projects/ProjectSelectorPopover.swift` - Projects panel
  content, inline rename, local project actions, and remove alert.
- `GitMenuBar/Components/Branches/BranchSelectorPopover.swift` - Branch panel
  content.
- `GitMenuBar/Components/Common/RepositoryOptionsPopoverView.swift` - Repository
  Options panel content.
- `GitMenuBar/Components/Common/WorkbenchMotion.swift` - shared animation tokens.
- `GitMenuBar/Components/Common/WorkbenchPanelSurface.swift` - shared material
  panel surface and Reduce Transparency fallback.

Current transient overlay scrim is invisible but blocks clicks:

```swift
// GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift:24-38
private var transientPresentationOverlayContent: some View {
    if presentationModel.route == .main && hasTransientPresentation {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .accessibilityHidden(true)
                .onTapGesture {
                    dismissTransientPresentations()
                }

            transientPanelContent
        }
        .transition(.opacity)
    }
}
```

Current panel placement is a mix of fixed top-leading, top-center, and
bottom-leading padding:

```swift
// GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift:42-77
if showProjectSelector {
    VStack {
        HStack {
            projectSelectorOverlay
            Spacer(minLength: 0)
        }
        Spacer(minLength: 0)
    }
    .padding(.top, WorkbenchMetrics.sectionSpacing)
    .padding(.leading, WorkbenchMetrics.windowPadding * 2)
    .padding(.trailing, WorkbenchMetrics.windowPadding)
} else if showRepositoryOptionsPopover {
    VStack {
        HStack {
            Spacer(minLength: 0)
            repositoryOptionsOverlay
            Spacer(minLength: 0)
        }
        Spacer(minLength: 0)
    }
    .padding(.top, WorkbenchMetrics.sectionSpacing)
    .padding(.horizontal, WorkbenchMetrics.windowPadding)
} else if showBranchSelector {
    VStack {
        Spacer(minLength: 0)
        HStack {
            branchSelectorOverlay
            Spacer(minLength: 0)
        }
    }
    .padding(.leading, WorkbenchMetrics.windowPadding)
    .padding(.trailing, WorkbenchMetrics.windowPadding)
    .padding(.bottom, WorkbenchMetrics.windowPadding * 2)
}
```

Current Repository Options receives surface and shadow at the call site, while
Projects and Branches already apply their surface internally:

```swift
// GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift:103-113
RepositoryOptionsPopoverView(...)
    .workbenchPanelSurface(material: .thin)
    .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 8)
    .accessibilityAddTraits(.isModal)
    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
```

```swift
// GitMenuBar/Components/Projects/ProjectSelectorPopover.swift:64-84
}
.workbenchPanelSurface(material: .thin)
.frame(width: 300, height: 260)
.alert(item: $removalProject) { project in
    ...
}
.onExitCommand {
    if renamingProjectPath != nil {
        cancelRename()
    }
}
```

The command palette already uses a visible full-window scrim and Reduce
Transparency branch:

```swift
// GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift:233-242
@ViewBuilder
private var commandPaletteScrim: some View {
    if reduceTransparency {
        Color(nsColor: .windowBackgroundColor)
    } else {
        ZStack {
            Color.black.opacity(0.08)
            Rectangle()
                .fill(.ultraThinMaterial)
        }
    }
}
```

Design constraints to honor:

- `.interface-design/system.md:45` says floating overlays are one elevation
  above parent, shadows are allowed there, and popovers/sheets keep
  `workbenchPanelSurface`.
- `.interface-design/system.md:46` says command palette scrim is full-window
  material plus subtle dim. For these smaller transient overlays, use the same
  principle but lighter than command palette.
- `.interface-design/system.md:149-158` says project-row repository options
  close Projects first, then present Repository Options anchored to the project
  selector control.
- `.agents/overlays/apple-design.md:10-18` says compact popovers, panels,
  repository pickers, and branch/worktree surfaces should preserve feedback
  under Reduce Motion and keep transitions anchored to their origin.
- `.agents/overlays/references/gitmenubar-motion.md` says use `WorkbenchMotion`
  tokens, keep Reduce Motion as an opacity/static equivalent, and reject
  unanchored panel transitions.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift check | `git diff --stat 5419723..HEAD -- GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift GitMenuBar/Pages/MainMenu/MainMenuActions.swift GitMenuBar/Components/Projects/ProjectSelectorPopover.swift GitMenuBar/Components/Branches/BranchSelectorPopover.swift GitMenuBar/Components/Common/RepositoryOptionsPopoverView.swift GitMenuBar/Components/Common/WorkbenchMotion.swift GitMenuBar/Components/Common/WorkbenchPanelSurface.swift` | no output, unless expected drift is reviewed |
| Popover guard | `rg '\\.popover|NSPopover|showRelativeToRect|_NSPopoverWindow' GitMenuBar` | exit 1, no matches |
| Whitespace | `git diff --check` | exit 0 |
| Changed Swift gate | `make agent-check` | exit 0 |
| Pre-merge gate | `make lint && make test` | exit 0 |

## Suggested executor toolkit

- Use `interface-design` if available when adjusting depth, curtain strength,
  panel chrome, and placement.
- Use `apple-design` if available when adjusting materials, motion, Reduce
  Motion, Reduce Transparency, Escape behavior, and platform consistency.
- Use `accessibility-audit` if available before review because the work changes
  modal traits, Escape behavior, visual dimming, and keyboard dismissal.

## Scope

**In scope**:

- `GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift`
- `GitMenuBar/Components/Projects/ProjectSelectorPopover.swift`
- `GitMenuBar/Components/Branches/BranchSelectorPopover.swift`
- `GitMenuBar/Components/Common/RepositoryOptionsPopoverView.swift`
- `GitMenuBar/Components/Common/WorkbenchMotion.swift`
- `GitMenuBar/Components/Common/WorkbenchPanelSurface.swift`
- Focused tests or previews only if the implementation introduces a testable
  helper or new UI-rendering type that requires preview coverage.
- `plans/README.md`, only to update this plan's status after execution.

**Out of scope**:

- Reintroducing SwiftUI `.popover`, `NSPopover`, or AppKit `showRelativeToRect`.
- Renaming `ProjectSelectorPopoverView`, `BranchSelectorPopoverView`, or
  `RepositoryOptionsPopoverView`; the naming cleanup is P3 and not required for
  this behavior fix.
- New persistence, repository model, Git/GitHub behavior, command center
  command IDs, or status item lifecycle changes.
- Full anchored geometry from toolbar item bounds if SwiftUI cannot expose those
  bounds cleanly without AppKit popovers. Use stable titlebar-relative placement
  instead and report the limitation in the final notes.

## Git workflow

- Branch: `advisor/045-polish-transient-overlay-experience`
- Commit style: Conventional Commits, matching recent history such as
  `refactor(ui): migrate popovers to custom overlay system`.
- Do not push or open a PR unless the operator explicitly instructs it.
- Preserve unrelated local changes. If the worktree is dirty before starting,
  inspect the diff and stop unless every change is part of this plan.

## Steps

### Step 1: Replace the invisible click-catcher with a light transient curtain

In `MainMenuOverlays.swift`, add a private `transientPresentationScrim` or
similarly named helper near `commandPaletteScrim`. Replace the `Color.clear`
click-catcher in `transientPresentationOverlayContent` with this visible
curtain, keeping the same outside-tap dismissal and `accessibilityHidden(true)`.

Target behavior:

- The curtain covers the full window, including titlebar area, like the command
  palette scrim.
- It is visibly lighter than `commandPaletteScrim` because Projects, Repository
  Options, and Branches are compact transient panels, not a command-search mode.
- With Reduce Transparency enabled, it uses a solid system color fallback rather
  than material/vibrancy.
- It still dismisses on outside click and does not expose a VoiceOver element.

Do not make the curtain a large dark modal backdrop. The user should perceive
"temporary overlay is active", not "the whole app entered a blocking dialog".

**Verify**: `rg 'transientPresentationScrim|Color.clear' GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift` -> the file contains the new scrim helper, and the transient outside-tap layer no longer uses `Color.clear`.

### Step 2: Normalize transient panel chrome and depth

In `MainMenuOverlays.swift`, introduce a small private helper or view modifier
for transient overlay elevation, for example a helper that applies:

- consistent shadow for all three transient panels,
- `.accessibilityAddTraits(.isModal)` when the curtain is active,
- the panel transition chosen in Step 4.

Avoid double material:

- `ProjectSelectorPopoverView` and `BranchSelectorPopoverView` already apply
  `.workbenchPanelSurface(material: .thin)` internally.
- Move the Repository Options surface into
  `RepositoryOptionsPopoverView.swift` so live usage and previews share the same
  base surface.
- Apply the shared elevation helper around all three overlays from
  `MainMenuOverlays.swift`.

Keep the shadow in the floating-overlay range from the design system. One
elevation above the parent is correct; shadow-on-every-section is not.

**Verify**:
`rg -n 'shadow\\(|workbenchPanelSurface' GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift GitMenuBar/Components/Projects/ProjectSelectorPopover.swift GitMenuBar/Components/Branches/BranchSelectorPopover.swift GitMenuBar/Components/Common/RepositoryOptionsPopoverView.swift`
-> Project, Branch, and Repository Options each have one material surface; the
shared shadow/elevation is applied once per transient panel.

### Step 3: Make placement and origin relationship coherent

Update `transientPanelContent` in `MainMenuOverlays.swift` so each panel appears
from a stable, explainable origin:

- Projects: top-center under the titlebar principal project control.
- Repository Options: top-center under the same project-selector control,
  because the interface system says row repository options close Projects and
  reopen anchored to the project selector control.
- Branches: bottom-leading above the footer branch chip.

Use named layout helpers or small private computed views instead of scattering
new raw padding values. Prefer existing `WorkbenchMetrics` values. If true
toolbar-bound anchors are not available without AppKit popovers, do not add an
AppKit bridge; keep the titlebar-relative SwiftUI placement and mention that
constraint in the final notes.

**Verify**:
`git diff -- GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift` -> no
`.popover`, no AppKit bridge, no broad layout refactor outside
`transientPanelContent` and small local helpers.

### Step 4: Replace raw transitions with WorkbenchMotion-backed transitions

In `MainMenuOverlays.swift`, replace repeated raw
`.transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))`
with a helper that accepts an anchor or semantic position:

- top-origin panels use a top or top-center scale anchor;
- branch selector uses a bottom-leading scale anchor;
- Reduce Motion uses opacity only;
- animation is attached to specific values such as `showProjectSelector`,
  `showRepositoryOptionsPopover`, and `showBranchSelector`, using
  `WorkbenchMotion.adaptive(WorkbenchMotion.swap, usesReducedMotion: reduceMotion)`.

Do not add broad `.animation` modifiers without a concrete `value:`.

**Verify**:
`rg 'scale\\(scale: 0\\.98\\)|\\.animation\\(' GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift`
-> no repeated raw transition snippets remain, and any animation has an explicit
state value.

### Step 5: Fix Escape semantics for inline project rename and overlay dismissal

In `ProjectSelectorPopover.swift`, add an `onDismiss: () -> Void` closure to
`ProjectSelectorPopoverView`. Update previews and call sites accordingly.

Change `.onExitCommand` so Escape behaves as:

1. If inline rename is active, cancel the rename and keep the Projects panel open.
2. Otherwise, call `onDismiss()` so Escape closes the Projects panel.

Pass `dismissTransientPresentations` from `MainMenuOverlays.swift` when creating
`ProjectSelectorPopoverView`.

Do not remove the row-level cancel button or change the remove-project alert.

**Verify**:
`rg -n 'onDismiss|onExitCommand' GitMenuBar/Components/Projects/ProjectSelectorPopover.swift GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift`
-> Projects has an explicit dismiss closure and Escape has the two-stage
cancel-then-dismiss behavior.

### Step 6: Run the full verification and manual smoke pass

Run the machine checks:

1. `rg '\\.popover|NSPopover|showRelativeToRect|_NSPopoverWindow' GitMenuBar`
2. `git diff --check`
3. `make agent-check`
4. `make lint && make test`

Expected results:

- Command 1 exits 1 with no matches.
- Commands 2-4 exit 0.

Manual smoke in the running app:

- Open Projects from the titlebar project control. Confirm a light curtain is
  visible, outside click closes it, Escape closes it, and inline rename uses
  Escape to cancel rename first.
- From the current project row, open Repository Options. Confirm Projects closes
  first, Repository Options appears under the project selector area, and outside
  click/Escape dismisses it.
- Open Branch selector from the footer branch chip. Confirm it appears above the
  footer at bottom-leading, uses the same elevation family, and outside
  click/Escape dismisses it.
- Repeat the visual checks with Reduce Motion enabled. Motion should become
  opacity/static feedback, not disappear entirely.
- Repeat with Reduce Transparency enabled. The curtain and panels should remain
  legible without material/vibrancy.

## Test plan

- No new XCTest is required if the change remains visual/layout-only and keeps
  the existing boolean presentation model.
- If the implementation introduces a new enum/helper with logic beyond view
  composition, add focused tests beside `GitMenuBarTests/MainMenuPresentationModelTests.swift`.
- Any new Swift UI-rendering file must include at least one `#Preview` per the
  repository preview policy.
- Always run `make agent-check` and the pre-merge `make lint && make test` gate.

## Done criteria

All must hold:

- [ ] The transient overlay curtain is visible, lighter than the command palette
  scrim, dismisses on outside click, and has a Reduce Transparency fallback.
- [ ] Projects, Repository Options, and Branch selector share one elevation
  treatment without double material surfaces.
- [ ] Projects and Repository Options appear top-center under the titlebar
  project-control area; Branch selector appears bottom-leading above the footer.
- [ ] Escape cancels project rename first; Escape closes Projects when no inline
  rename is active.
- [ ] Transitions use `WorkbenchMotion.adaptive(...)` with explicit animation
  values, and Reduce Motion uses opacity/static feedback.
- [ ] `rg '\\.popover|NSPopover|showRelativeToRect|_NSPopoverWindow' GitMenuBar`
  has no matches.
- [ ] `git diff --check`, `make agent-check`, and `make lint && make test` exit 0.
- [ ] `plans/README.md` status row for Plan 045 is updated.

## STOP conditions

Stop and report back if:

- Any in-scope file has drifted in a way that invalidates the excerpts above.
- The fix appears to require reintroducing SwiftUI `.popover`, `NSPopover`, or
  `showRelativeToRect`.
- True trigger anchoring requires a new AppKit bridge or status-item/window
  lifecycle changes.
- Escape handling conflicts with active system alerts, command palette handling,
  or sheet presentation.
- Verification fails twice after a reasonable fix attempt.
- The implementation needs files outside the in-scope list, except for focused
  tests/previews directly required by this plan.

## Maintenance notes

- This work preserves the anti-crash decision from commit `5419723`: custom
  SwiftUI overlays stay in the main window instead of using platform popover
  windows.
- Review should focus on interaction coherence: outside click, Escape,
  Reduce Motion, Reduce Transparency, VoiceOver/modal traits, and whether
  panel placement reads as connected to the trigger.
- The `*PopoverView` type names are intentionally left alone. Rename them only
  in a later cleanup plan because this plan is about behavior and experience,
  not API naming churn.
