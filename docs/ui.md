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
- Related decisions: [`docs/adr/0001-workbench-depth-and-token-naming.md`](adr/0001-workbench-depth-and-token-naming.md), [`docs/adr/0002-window-shell-material-and-titlebar-chrome.md`](adr/0002-window-shell-material-and-titlebar-chrome.md), and [`docs/adr/0006-workbench-scroll-edge-dissolve-and-thin-scrollbar.md`](adr/0006-workbench-scroll-edge-dissolve-and-thin-scrollbar.md)

The former `.interface-design/system.md` is a legacy pointer. Do not create a
second canonical design-system document. Reconcile code and this file when
they drift, and use an ADR for a durable decision rather than a task log.

## Depth, density, and tokens

- Use one depth strategy: window-level material/vibrancy for the shell, quiet
  borders/tints for structure, and shadows only for floating overlays.
- The header uses native toolbar chrome; the main window title stays hidden and
  the underlying titled `NSWindow` is retained only for AppKit traffic lights
  and toolbar ownership. Do not add a material plate above the content.
  Inputs are slightly inset from their surrounding surface.
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
  32-point hit areas; never ship a tiny visible icon with an undersized hit
  target.

## Composition and interaction

The main route remains native toolbar → commit composer → scroll content →
branch footer, with optional quota cards secondary to Git work. `NavigationSplitView`
owns the Projects sidebar's width, selection, and collapse behavior. Stage/
Unstage section actions stay visible; per-file actions remain hover-revealed
where the product policy permits. Preserve keyboard actions, context menus, and
confirmation for destructive work.

Each scroll surface has exactly one native vertical `ScrollView` or `List`
owner. Keep the composer and footer outside the main owner. Do not hide and
redraw native indicators, add edge masks, or add a parallel custom scrollbar.

Settings uses the native grouped Form hierarchy, one scroll owner per pane,
and no nested workbench panel plates. The multi-project window keeps a
collapsible Projects sidebar beside the selected-project detail column; the
system owns its divider and width.

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
