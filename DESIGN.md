---
name: GitMenuBar
description: Dense, calm, native macOS Git workbench opened from the menu bar.
---

# Design System: GitMenuBar

Read this before changing the main workbench, Settings, the Projects sidebar,
the commit composer, scroll surfaces, the command palette, or attached
overlays. Product facts live in [PRODUCT.md](PRODUCT.md); durable rationale
lives in [`docs/adr/`](docs/adr/).

## Overview

Native SwiftUI and AppKit first. The interface stays dense and semantic:
color and depth carry meaning, never decoration.

### Tokens and Sources

The Swift token types are the only token source. This file names their
symbols and never repeats their values.

- `WorkbenchMetrics`, `WorkbenchTypography`, `WorkbenchPalette`:
  `GitMenuBar/Components/Common/WorkbenchMetrics.swift`
- `WorkbenchMotion`: `GitMenuBar/Components/Common/WorkbenchMotion.swift`
  (usage rules in [`docs/agents/motion.md`](docs/agents/motion.md))
- `WorkbenchMaterialWeight` and `workbenchPanelSurface(cornerRadius:material:)`:
  `GitMenuBar/Components/Common/WorkbenchPanelSurface.swift`
- Button variants: `GitMenuBar/Components/Common/WorkbenchButtonStyles.swift`
- Main composition: `GitMenuBar/Pages/MainMenu/`; Settings:
  `GitMenuBar/Pages/Settings/`
- Layout persistence: the stable `NSWindow.FrameAutosaveName` in
  `MainWindowController`. `AppPreferences.Keys.inspectorColumnWidth` is a
  legacy unused key kept for compatibility after the side-panel change.

Related decisions: [ADR 0001](docs/adr/0001-workbench-depth-and-token-naming.md),
[ADR 0002](docs/adr/0002-window-shell-material-and-titlebar-chrome.md),
[ADR 0006](docs/adr/0006-workbench-scroll-edge-dissolve-and-thin-scrollbar.md),
[ADR 0017](docs/adr/0017-narrow-contextual-side-panel.md) (supersedes ADRs
0010–0015), [ADR 0021](docs/adr/0021-side-panel-split-column.md) (split column;
supersedes the overlay parts of 0017),
[ADR 0022](docs/adr/0022-unified-branch-list-and-cleanup-review.md) (unified
branch list and cleanup review),
[ADR 0023](docs/adr/0023-issue-label-mutations.md) (issue label edits), and
[ADR 0024](docs/adr/0024-issue-label-creation.md) (repository label creation).

## Colors

- One interactive accent: the native `Color.accentColor`. Text and labels use
  native `.primary` and `.secondary`.
- Semantic fills and borders come from `WorkbenchPalette`: `hoverFill`,
  `selectedFill`, `neutralBorder`, `warningFill`/`warningBorder`,
  `errorFill`/`errorBorder`, `successFill`, and `accentFill`. The
  status fills and borders and `accentFill` take `ColorSchemeContrast`;
  `hoverFill` and `selectedFill` do not adapt to contrast. Hover and selection use
  these functions, never local opacity values.
- Diff, warning, error, success, and quota colors are semantic. Color carries
  meaning, never decoration.
- Sidebar status dots use severity: red for diverged or behind, orange for
  uncommitted changes, `.secondary` for unmerged branches only. Untracked files
  alone are not a warning.
- The status-item strip uses template or semantic AppKit label color so it
  follows the menu bar's appearance.

## Typography

- Text roles come from `WorkbenchTypography` (`windowTitle`, `sectionLabel`,
  `body`, `detail`, `caption`, `captionStrong`, `field`), built on native
  text styles. `WorkbenchTypography.tracking(for:)` owns tracking per style.
- Short commit hashes use the monospaced caption.

## Layout

- Spacing uses the `WorkbenchMetrics` scale: `compactSpacing`,
  `sectionSpacing`, `groupSpacing`, `panelPadding`, and `windowPadding`. Micro
  values must be named metrics (`microSpacing`, `chipSpacing`).
- Main route: native toolbar, then scroll content (repository overview, then
  commit history), with optional quota cards secondary to Git work. The main
  scroll viewport reaches the detail column edges; `windowPadding` belongs to
  its scroll content, so native toolbar effects and scrolling reach the edges.
- The repository overview always presents five metrics: Changes, Branches,
  Stashes, Pull Requests, and Issues. `ViewThatFits` selects adaptive tiers
  from the card's own width.
- `NavigationSplitView` owns the Projects sidebar's width, selection, and
  collapse. While visible, the sidebar is user-resizable between
  `WorkbenchMetrics.projectsMinimumWidth` and
  `WorkbenchMetrics.projectsMaximumWidth`. Its footer holds the quota summary,
  the sidebar visibility control, and Settings.
- The center pane keeps at least `WorkbenchMetrics.centralMinimumWidth`, grows
  with the window, and shrinks when the side panel opens.
- The trailing side panel is a column beside the detail content with the fixed
  `WorkbenchMetrics.sidePanelWidth`. It never covers the detail column
  ([ADR 0021](docs/adr/0021-side-panel-split-column.md)).
- The window minimum is the three-column floor
  `WorkbenchMetrics.mainWindowMinimumWidth`, so an open panel never truncates
  history row metadata.
- Toolbar ([ADR 0020](docs/adr/0020-toolbar-actions-and-history-list.md)):
  sidebar toggle, Back, the repository title item, the secondary ahead/behind
  status, and a branch chip that opens the branch selector. A flexible space
  pushes Fetch and Sync (Sync only when ahead or behind) to the trailing edge.
  The toolbar keeps only route-specific controls and does not duplicate the
  Commit action.
- List alignment: section headers, the remote hidden-by-filter caption, and
  nested disclosure labels use `WorkbenchMetrics.rowContentInset`. List row
  content aligns to the same token. Button rows (`workbenchRow`,
  `workbenchDestructiveRow`) keep the padding defined in
  `WorkbenchButtonStyles`.
- Settings uses the native grouped `Form` hierarchy, one scroll owner per
  pane, and no nested workbench panel plates.

## Elevation & Depth

- One depth strategy: window-level material and vibrancy for the shell, quiet
  borders and tints for structure, shadows only for floating overlays.
- The side panel is inline structure: border and tint, no shadow.
- Panel surfaces use `workbenchPanelSurface` with a `WorkbenchMaterialWeight`
  over native materials (`.thinMaterial`, `.regularMaterial`,
  `.thickMaterial`). Under Reduce Transparency they fall back to the native
  `controlBackgroundColor`.
- Header ([ADR 0002](docs/adr/0002-window-shell-material-and-titlebar-chrome.md)):
  native titlebar with the unified toolbar pattern. The titlebar is opaque and
  its hairline is hidden. The system title is hidden, and a plain, unbordered
  toolbar title item shows the repository or route. The `NSWindow` title stays
  set for the Window menu and accessibility. The titled `NSWindow` owns traffic
  lights and toolbar chrome.
- Inputs are slightly inset from their surrounding surface.

## Shapes

Corner radii come from `WorkbenchMetrics`: `microCornerRadius` for chips,
`rowCornerRadius` for rows, `cornerRadius` for inline panels,
`largeCornerRadius` for main surfaces (the `workbenchPanelSurface` default),
and `overlayCornerRadius` for the command palette. Shapes use the continuous
corner style.

## Components

- Buttons: prefer native SwiftUI and AppKit button styles. Shared wrappers in
  `WorkbenchButtonStyles.swift` exist only for semantic variants:
  `workbenchPrimary`, `workbenchSecondary`, `workbenchGhost`, `workbenchIcon`,
  `workbenchRow`, and `workbenchDestructiveRow`. Never add custom hover, press
  scaling, pointer, or scrollbar behavior to them.
- Filter chips: single selection. The selected chip is accent-tinted and
  carries the only count for its filter.
- Projects sidebar rows: every GitHub project can show trailing count badges,
  open issues and open pull requests, whether or not it is selected. Counts
  come from the repository totals in the monitor snapshot, never from the
  20-item pull-request detail list, and never change a project's health
  classification or group. Known positive totals show a badge; a known zero
  hides that badge. Large totals use the locale's compact notation (`1.3K`).
  An unread or failed count, or the last totals of a row whose refresh failed,
  shows a neutral `—`; non-GitHub remotes show no badge. When the row is too
  narrow, visible badges hide before the project name is squeezed; VoiceOver
  still reads available totals. The row summary keeps only the current
  branch's own pull-request status, so no count appears twice.
- Cleanup review banner: one summary line (`N ready to clean`, `M blocked`)
  and one Review action. Review opens the shared cleanup sheet with Ready and
  Blocked sections and a checked subset of ready units.
- Issues side panel: rows open the issue on GitHub and show its label chips.
  A trailing tag menu lists every repository label with the applied ones
  checked. The menu appears only when the account can change labels; a lock
  caption explains read-only access. One change runs at a time, with progress
  on the affected row and a retry action after a failure. The menu ends with
  `New Label in Repository`, which opens a sheet with name, color, and optional
  description. The sheet names the repository and states that creating a label
  does not apply it to the issue; applying stays the existing toggle action.
- Side Panel Branches
  ([ADR 0022](docs/adr/0022-unified-branch-list-and-cleanup-review.md)): one
  unified local branch list; each branch appears once, and its linked worktree
  shows as the row's status badge. Detached worktrees appear only in the
  Worktrees section (footer toggle). Filter chips: All, Mergeable, Dirty,
  Stale. The search field applies together with the selected
  chip, never instead of it. Stale means the last commit is older than
  `BranchListResolver.staleThresholdSeconds` on a non-current local branch. The
  Mergeable chip counts merged local rows; the banner counts cleanup units,
  which also include unmerged clean branches and worktree-only units, so both
  counts stay.
- History rows: subject, short hash, and time. Author lives in commit details.
  Conventional-commit prefixes render as a small tinted chip. Merge commits
  are dimmed. No trailing chevron; the row is the target. Date headers show
  the day's commit count.
- Commit details: the subject is the headline. The short hash is a monospaced
  chip that copies the full hash; the 40-character hash never shows as text.
  One secondary action row plus an overflow menu. Changed files are a vertical
  list with per-file line counts.
- Commit workspace: in the side panel under the Working Tree selection, the
  commit composer sits fixed above the working tree, which is the workspace's
  single scroll owner. The composer owns the primary Commit action.
- Quota meters follow `UsageQuotaPresentationPreferences` (value style, meter
  style, warning thresholds). Color appears only past a configured threshold.
  Meter size comes from `WorkbenchMetrics.quotaMeterWidth` and
  `WorkbenchMetrics.quotaMeterHeight`.
- Status-item quota strip: the user chooses whether the status item always
  shows up to two selected quota figures per provider or keeps them only in
  the quota submenu. The submenu keeps the provider cards and the refresh
  action in both modes. Providers with an exhausted weekly reading are hidden
  from the strip until a refreshed reading has remaining weekly quota. Providers
  without a weekly reading keep their selected figures.

## Do's and Don'ts

- Do reuse Workbench tokens and shared controls. Don't add a competing raw
  scale in a view.
- Do hide a control when there is nothing to do, or state the result ("Up to
  date"). Don't show a disabled control instead.
- Don't repeat information: hide the branch name in sidebar rows when it is
  the default branch, and never show a count twice for the same object.
- Don't hand-draw a titlebar or add a material plate above the content.
- Don't hide and redraw native scroll indicators, add edge masks, or add a
  parallel custom scrollbar.
- Don't hard-code quota percentages in views.
- Don't show an empty meter for unavailable provider data. Keep cached stale
  readings visible and marked Outdated in the quota submenu.
- Don't use error styling for GitHub-unavailable overview metrics; they stay
  neutral.

## Interaction & States

- Affected surfaces cover idle, hover, pressed, focused, selected, disabled,
  loading, empty, and error states as applicable. Native controls own hover,
  press, focus, and pointer feedback.
- Hit areas: prefer `WorkbenchMetrics.minimumHitTarget` for chips, toggles,
  and buttons; icon buttons use `WorkbenchMetrics.iconHitTarget`. Never ship a
  tiny visible icon with an undersized hit target.
- One selection highlight per window. The sidebar selection uses the neutral
  selected fill; only the focused content selection uses the accent. A pinned
  current branch row gets a neutral border, not an accent fill; accent stays
  on its checkmark and the selected filter chip.
- Side panel: one optional `MainMenuSidePanelSelection` drives it; nil means
  no panel, with no permanent empty third column and no compact sheet
  fallback. Close with the explicit close control or Escape. Escape clears
  the contextual selection before other transient presentations or the
  window. Outside clicks do not dismiss; the detail column stays interactive.
  Changing repositories or leaving the main route clears the selection.
  Draft commit text on `MainMenuView` survives dismiss
  ([ADR 0015](docs/adr/0015-contextual-side-panel.md),
  [ADR 0021](docs/adr/0021-side-panel-split-column.md)).
- The Changes metric opens the Working Tree side panel.
- When the sidebar is collapsed, the native `.toggleSidebar` toolbar item
  stays available as the re-entry control.
- Stage and Unstage section actions stay visible; per-file actions are
  hover-revealed where product policy permits. Keyboard actions and context
  menus stay available.
- Destructive work always goes through confirmation. Commit-detail
  destructive actions live in the overflow menu behind the shared
  confirmation.
- Branch cleanup row actions: `Clean <branch>` removes the linked worktree
  before its branch; `Remove Worktree for <branch>` removes only the
  worktree; `Delete Branch` removes only the branch through the cleanup sheet
  with `deletingBranchOnly()`, so the risk gate applies. Hide `Delete Branch`
  while the branch is checked out in a worktree. A branch without a
  management unit keeps the plain legacy confirmation.
- The Worktrees section offers Remove Worktree when the worktree-only unit is
  allowed (eligible, branch not merged, or detached), plus Reveal in Finder,
  Copy Path, and Force Remove Worktree for dirty linked worktrees.
- With no ready cleanup units, hide Review and state `M blocked` with help
  text.
- Badge precedence: a dirty worktree badge wins over the merged badge.
- Status item context menu: right click and Control-click show only
  `AI Usage Quotas`, `Settings`, and `Quit GitMenuBar`; with usage quotas
  disabled, only Settings and Quit
  ([ADR 0019](docs/adr/0019-focused-status-item-context-menu.md)).

## Accessibility

- Expose labels, values, selection, keyboard behavior, and VoiceOver
  semantics on every affected surface.
- Filter chip accessibility labels name the count (for example, "Dirty, 2
  branches").
- Verify Light and Dark, Increased Contrast, Reduce Transparency, and Reduce
  Motion. `WorkbenchPalette` contrast-aware functions and
  `workbenchPanelSurface` adapt to Increased Contrast and Reduce
  Transparency.
- Reduce Motion removes nonessential custom motion without removing scrolling
  or state feedback (`WorkbenchMotion.adaptive(_:usesReducedMotion:)`,
  `adaptiveMotion()`).
- The main workbench window appears and disappears immediately; its alpha is
  never animated, so status-item toggles feel responsive. Secondary panels may
  use the shared `WorkbenchMotion` defaults.

## Invariants

- Each scroll surface has exactly one vertical `ScrollView` or `List` owner.
  The composer and footer stay outside their scroll owner, including in the
  side-panel workspace.
- SwiftUI layout never writes measured geometry back to state or defaults.
  The window frame keeps its stable autosave name in `MainWindowController`.
- The status item is the single app-shell owner.
- `NavigationSplitView` owns the Projects sidebar divider and width.
- The side panel is a split column, never an overlay, and opens only with a
  `MainMenuSidePanelSelection`.
- Never share a `matchedGeometryEffect` id between two visible views; the open
  commit's history row keeps its title.
- Cleanup follows the rules in [PRODUCT.md](PRODUCT.md). Their
  presentation: deleting an unmerged branch shows a clear data-loss warning
  and a risk-review step, unmerged branches start unchecked in cleanup
  confirmation, and Force Remove Worktree has its own permanent-deletion
  warning.
- Remote branch management lists all remote-tracking refs, including
  `upstream`, and labels the remote being removed.
- The side panel adds no automatic fetch, duplicate repository query, custom
  AppKit panel, or status-item lifecycle change.

## Review & Update Triggers

- Check every UI change against the SwiftUI previews (main-window previews
  use `MainMenuPreviewHarness(showsTransparentTitlebar: true)`), `make build`,
  and `make test`. Verify states, keyboard and VoiceOver, appearance,
  contrast, and reduced motion and transparency manually.
- Update this file in the same change when a reusable rule, token, component,
  or invariant changes. Add or update an ADR for a meaningful alternative,
  risk, ownership decision, or external reference; never record one-off
  polish.
- Retire a rule when its implementation and references disappear; keep the
  historical rationale in ADRs.
- When code and this file disagree, the code is the truth; fix this file in
  the same change.
