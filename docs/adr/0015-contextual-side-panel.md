# ADR 0015: Contextual side panel overlay

Status: Superseded by ADR 0017
Date: 2026-09-07

## Context

ADRs 0010–0014 established a trailing workbench inspector that became an
always-open `HSplitView` column with a compact-width sheet fallback. That model
consumed width when no detail was selected, capped the center overview so
extra space fed the inspector, and treated the Working Tree commit workspace as
a permanent third surface.

VoiceInk’s trailing `sidePanel` overlay (studied at
`~/Documents/Projects/References/VoiceInk` @ `8f089cb`, GPL-3.0) shows detail
only while a contextual selection exists: fixed width, slide+opacity motion
with Reduce Motion, optional outside-tap dismiss, and an explicit close
control. GitMenuBar needs the same contextual/temporary posture for every
former inspector selection, including Working Tree, without copying GPL
sources.

## Decision

- Retire the always-open trailing inspector column and the compact inspector
  sheet.
- Present one selection-gated trailing **side panel** overlay hosted on the
  `NavigationSplitView` detail column (Projects sidebar stays outside the
  dismiss layer).
- Drive presentation with one optional `MainMenuSidePanelSelection`. Nil means
  no panel (no empty permanent column).
- Use a fixed `WorkbenchMetrics.sidePanelWidth` (560). Do not persist panel
  width; leave the legacy `inspectorColumnWidth` preference unused.
- Remove the center pane `centralMaximumWidth` cap so the overview grows with
  the window. Window minimums are the two-column floor (sidebar + center).
- Dismiss with Escape, an explicit close control, and outside tap — except
  Working Tree, which disables outside tap so commit composition is not
  dismissed accidentally. Draft commit text on `MainMenuView` survives dismiss.
- Independently reimplement the overlay with Workbench tokens/materials;
  VoiceInk remains inspiration-only under GPL-3.0.

## Consequences

- The main workbench is two inline surfaces until a contextual selection opens
  the side panel.
- Narrow and wide windows share one presentation owner.
- Durable UI contract lives in `docs/ui.md`; ADRs 0010–0014 are superseded.
- Product and code vocabulary use Side Panel rather than Inspector.

## Rejected or deferred

- Keeping an always-open column for Working Tree only was rejected: the agreed
  model is fully contextual and temporary.
- Compact sheet fallback was rejected to avoid dual presentation owners.
- Resizable/persisted panel width was deferred; the overlay uses a fixed token.
- Copying VoiceInk’s `SidePanel.swift` was rejected under GPL-3.0.

## Ownership and accessibility

`MainMenuView` owns selection. `MainMenuContent` owns detail-hosted
`sidePanel` attachment and dismiss policy. `SidePanelModifier` owns overlay
chrome and motion. Content views own their scroll surfaces and accept an
`onClose` for the header control. Escape clears selection before other
transient dismissals. Close is labeled for VoiceOver (“Close details”).

## References

- [`docs/ui.md`](../ui.md)
- Plan 081 (`plans/081-contextual-side-panel.md`)
- VoiceInk catalog entry in `.agents/overlays/reference-apps.md`

## Affected surfaces

- `GitMenuBar/Components/Common/SidePanel.swift`
- `GitMenuBar/Components/Common/WorkbenchMetrics.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuContent.swift`
- `GitMenuBar/Pages/MainMenu/*SidePanel*`
- `GitMenuBar/App/StatusBarController.swift`
- `GitMenuBar/App/MainMenuPresentationModel.swift`
- `docs/ui.md`
