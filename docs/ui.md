# UI

Current UI contract for GitMenuBar. Read this before changing the main
workbench, Settings, project sidebar, commit composer, scroll surfaces,
command palette, or attached overlays. Durable rationale belongs in
[`docs/adr/`](adr/).

## Product intent

GitMenuBar is a native macOS workbench for a developer moving between editor
and terminal: stage → commit → sync or switch branch with low ceremony. It is
dense, calm, and semantic—not a SaaS dashboard or marketing surface.

## Sources of truth

- Token owners: `WorkbenchMetrics`, `WorkbenchTypography`,
  `WorkbenchPalette`, `WorkbenchMotion`, and `WorkbenchMaterialWeight` in
  `GitMenuBar/`
- Main composition: `GitMenuBar/Pages/MainMenu/`
- Settings: `GitMenuBar/Pages/Settings/`
- Layout persistence: the stable `NSWindow.FrameAutosaveName` in
  `MainWindowController`. `AppPreferences.Keys.inspectorColumnWidth` is a
  legacy unused key retained for compatibility after the side-panel change.
- Related decisions: [`docs/adr/0001-workbench-depth-and-token-naming.md`](adr/0001-workbench-depth-and-token-naming.md), [`docs/adr/0002-window-shell-material-and-titlebar-chrome.md`](adr/0002-window-shell-material-and-titlebar-chrome.md), [`docs/adr/0006-workbench-scroll-edge-dissolve-and-thin-scrollbar.md`](adr/0006-workbench-scroll-edge-dissolve-and-thin-scrollbar.md), [`docs/adr/0017-narrow-contextual-side-panel.md`](adr/0017-narrow-contextual-side-panel.md) (supersedes ADRs 0010–0015), [`docs/adr/0021-side-panel-split-column.md`](adr/0021-side-panel-split-column.md) (split column; supersedes the overlay parts of 0017), and [`docs/adr/0022-unified-branch-list-and-cleanup-review.md`](adr/0022-unified-branch-list-and-cleanup-review.md) (unified branch list and cleanup review; supersedes the work-unit list part of Branch Health cleanup)

The former `.interface-design/system.md` is a legacy pointer. Do not create a
second canonical design-system document. Reconcile code and this file when
they drift, and use an ADR for a durable decision rather than a task log.

## Depth, density, and tokens

- Use one depth strategy: window-level material/vibrancy for the shell, quiet
  borders/tints for structure, and shadows only for floating overlays. The
  side panel is inline structure: border and tint, no shadow.
- The header uses the native macOS titlebar and unified toolbar pattern used by
  GUGU Settings: the titlebar is opaque and the titlebar hairline is hidden.
  The system title is hidden; a plain, unbordered toolbar title item shows the
  repository or route so branch context can sit beside it (ADR 0020). The
  `NSWindow` title stays set for the Window menu and accessibility. The titled
  `NSWindow` remains the owner of traffic lights and toolbar chrome; do not add
  a hand-drawn titlebar or material plate above the content. Inputs are slightly
  inset from their surrounding surface.
- Spacing is based on 8 points: compact 8, section 12, group 20, panel inset
  16, and window inset 12. Micro values 4 and 6 must be named metrics.
- Radius scale is 6, 8, 10, 14, and 16 for chips, rows, inline panels, main
  surfaces, and the command palette respectively.
- Use one interactive accent (`Color.accentColor`) plus semantic diff,
  warning, error, success, and quota colors. Hover and selection use the
  shared palette rather than local opacity guesses.
- Prefer native SwiftUI/AppKit button styles. Keep shared wrappers only for
  semantic variants (Primary, Secondary, Ghost, Icon, Destructive, Row), not
  for custom hover, press scaling, pointer, or scrollbar behavior. Prefer
  32-point hit areas (`WorkbenchMetrics.minimumHitTarget`); never ship a tiny
  visible icon with an undersized hit target.

## Composition and interaction

The main route remains native toolbar → scroll content (repository
overview, then history), with optional quota cards secondary to Git work.
[ADR 0020](adr/0020-toolbar-actions-and-history-list.md) moves the branch
picker and repository actions into the toolbar and removes the branch footer.
Contextual details open in a trailing **side panel** column beside the
detail content (ADR 0021). It does not cover the detail column. The panel is
absent until a central selection exists; there is no permanent empty third
column and no compact sheet fallback. The commit workspace lives in the side
panel under the Working Tree selection as commit composer → working tree,
with the composer fixed above the workspace's single scroll owner. Commit
history lives in the central project view below the repository overview.
`NavigationSplitView` owns the Projects sidebar's width, selection, and
collapse behavior. While visible, the sidebar is always present and
user-resizable between `WorkbenchMetrics.projectsMinimumWidth` and
`WorkbenchMetrics.projectsMaximumWidth`; its footer contains the visibility
control beside Settings. When the sidebar is collapsed, the native toolbar item
`.toggleSidebar` remains available as the re-entry control. The center pane keeps a
minimum of `WorkbenchMetrics.centralMinimumWidth` and grows with the window;
it shrinks to make room for the side panel when one is open. The sidebar footer concentrates the
quota summary, sidebar visibility, and Settings access in one bottom surface;
the toolbar title item identifies the current repository or route. The
toolbar holds the sidebar toggle, Back, and the repository actions from ADR
0020. The repository title is a toolbar item, followed by the secondary
ahead/behind status and a branch chip that opens the branch selector. History
date headers show the day's commit count. A flexible space
pushes the actions to the trailing edge: Fetch, Sync (only when ahead or
behind), and Commit (opens the Working Tree side panel). Commit is the
primary action and uses the prominent, accent-tinted toolbar style.

The status item remains the single app-shell owner. Left click opens the main
GitMenuBar window. Right click and Control-click show only `AI Usage Quotas`,
`Settings`, and `Quit GitMenuBar`; when usage quotas are disabled, the menu
contains only Settings and Quit. [ADR 0019](adr/0019-focused-status-item-context-menu.md)
records this menu scope. Git and project actions remain available in their
existing app surfaces. The quota submenu retains the provider cards and refresh
action. The user can choose whether the status item always renders up
to two selected quota figures per provider or keeps them only inside that
submenu; the submenu remains available in both modes. The status-item strip
uses template/semantic AppKit label color so it follows the menu bar's
appearance. Unavailable provider data does not create an empty meter; cached
stale readings stay visible and marked Outdated in the quota submenu.

The side panel uses fixed `WorkbenchMetrics.sidePanelWidth`. Dismiss with the
explicit close control and Escape (clears selection first). Outside tap does
not dismiss: the detail column stays interactive. Draft commit text on
`MainMenuView` survives dismiss. The window minimum is the three-column floor
(`mainWindowMinimumWidth`: Projects + center + side panel), so the open
panel never truncates history row metadata. SwiftUI layout must not write measured geometry
back to state or defaults. The window frame uses its existing stable autosave
name for session/version continuity.
Stage/Unstage section actions stay visible; per-file actions remain hover-revealed
where the product policy permits. Preserve keyboard actions, context menus, and
confirmation for destructive work.

Each scroll surface has exactly one vertical `ScrollView` or `List`
owner. Keep the composer and footer outside their scroll owner, including in
the side-panel workspace. Do not hide and
redraw native indicators, add edge masks, or add a parallel custom scrollbar.

Settings uses the native grouped Form hierarchy, one scroll owner per pane,
and no nested workbench panel plates. The multi-project window keeps a
collapsible Projects sidebar beside the selected-project detail column; the
system owns its divider and width.

## Contextual side panel workbench

The main workbench has two inline surfaces plus one contextual column:

- Projects remains the compact navigation and attention surface on the left.
- The selected repository overview remains in the center.
- A trailing side panel column sits beside the detail content only while a
  `MainMenuSidePanelSelection` exists.

One optional selection drives the panel. Nil selection means no panel. Escape
clears contextual selection before other transient presentations or the
window. Changing repositories or leaving the main route clears selection. The
shell does not add an automatic fetch, duplicate repository query, custom
AppKit panel, or status-item lifecycle change. Durable rationale is recorded
in [`ADR 0015`](adr/0015-contextual-side-panel.md) and [`ADR 0021`](adr/0021-side-panel-split-column.md).

## Branch Health cleanup

Side Panel Branches is the primary local cleanup surface ([ADR 0022](adr/0022-unified-branch-list-and-cleanup-review.md)).
It shows one unified local branch list. Each branch appears once; its linked
worktree shows as the row's status badge. Detached worktrees appear only in the
Worktrees section (footer toggle).

- Filter chips (All, Mergeable, Dirty, Stale) select one filter and carry the
  counts. The search field applies alongside the chip. Stale means the last
  commit is more than 10 days old on a non-current local branch. A dirty
  worktree badge wins over the merged badge.
- The cleanup review banner shows `N ready to clean` and `M blocked`. Review
  opens the shared cleanup sheet with Ready and Blocked sections and a checked
  subset of ready units. With no ready units, hide Review and state
  `M blocked` with help text.
- Row actions: `Clean <branch>` removes the linked worktree before its branch.
  `Remove Worktree for <branch>` removes only the worktree. `Delete Branch`
  removes only the branch and runs through the cleanup sheet with
  `deletingBranchOnly()`, so the risk gate applies. Hide `Delete Branch` while
  the branch is checked out in a worktree, because Git requires that worktree
  removed first. A branch without a management unit keeps the plain legacy
  confirmation.
- The Worktrees section offers Remove Worktree when the worktree-only unit is
  allowed (eligible, branch not merged, or detached), plus Reveal in Finder,
  Copy Path, and Force Remove Worktree for dirty linked worktrees.

Merged status includes both default-branch reachability and Git's
cherry-equivalent result. Clean worktrees may be removed even when their branch
is not merged, and clean detached worktrees may be removed. Deleting an
unmerged branch, alone or with its worktree, requires the shared confirmation to
show a clear data-loss warning and an explicit risk-review step. Force Remove
Worktree requires a dedicated warning that its directory and uncommitted changes
are permanently deleted while its branch is kept. Remote branch management lists
all remote-tracking refs, including `upstream`, and labels the remote being
removed.

Project Cleanup remains the multi-repo shortcut and keeps its existing safe
eligibility contract.

### Reusable patterns

- Filter chips: single selection; the selected chip is accent-tinted and its
  accessibility label names the count (for example, "Dirty, 2 branches").
  Chips use a 32-point hit area and carry the only count for their filter.
- Cleanup review banner: one summary line and one action. Hide the action when
  nothing is ready; the blocked count and its help text explain the state.

## Visual hierarchy rules

- One selection highlight per window. The sidebar selection uses the neutral
  selected fill; only the focused content selection uses the accent.
- Color carries meaning, never decoration. Sidebar status dots use severity:
  red for diverged or behind, orange for uncommitted changes, secondary for
  unmerged branches only. Untracked files alone are not a warning.
- Do not repeat information. Hide the branch name in sidebar rows when it is
  the default branch. Do not show a count twice for the same object.
- Do not show a disabled control when there is nothing to do; hide it or state
  the result ("Up to date").
- History rows show subject, short hash in the monospaced caption, and time.
  Author lives in commit details. The open commit's row keeps its title;
  never share a `matchedGeometryEffect` id between two visible views. Conventional-commit prefixes render as a small tinted chip.
  Merge commits are dimmed. No trailing chevron; the row is the target.
- Commit details: subject is the headline; short hash is a monospaced chip
  that copies the full hash; never show the 40-character hash as text. One
  secondary action row plus an overflow menu; destructive actions live in the
  overflow menu behind the shared confirmation. Changed files are a vertical
  list with per-file line counts.
- Quota meters follow `UsageQuotaPresentationPreferences` (value style, meter
  style, warning thresholds). Color appears only past a configured threshold.
  No hard-coded percentages in views.

## States, accessibility, and motion

Affected surfaces must cover idle, hover, pressed, focused, selected, disabled,
loading, empty, and error states as applicable. Expose labels, values,
selection, keyboard behavior, and VoiceOver semantics. Verify Light/Dark,
increased contrast, Reduce Transparency, and Reduce Motion. Native controls
own hover, press, focus, and pointer feedback. Reduced motion removes
nonessential custom motion without removing scrolling or state feedback. The
main workbench window appears and disappears immediately; do not animate its
alpha, so status-item toggles feel responsive. Secondary panels may use the
shared motion defaults.

## Review checklist and lifecycle

- [ ] Reuse Workbench tokens and shared controls; no raw competing scale.
- [ ] Preserve depth, header, composition, button, hit-target, and scroll
      ownership contracts.
- [ ] Verify relevant states, keyboard/VoiceOver, appearance, contrast, and
      reduced-motion/transparency behavior.
- [ ] Update this file for reusable rules or invariants.
- [ ] Add/update an ADR for a meaningful alternative, risk, ownership
      decision, or external reference; do not record one-off polish.

Create or update this file when a rule constrains future UI or applies across
surfaces. Retire rules when their implementation and references disappear;
retain historical rationale in ADRs when useful.
