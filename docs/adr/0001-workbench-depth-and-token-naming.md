# Workbench depth strategy and token naming

GitMenuBar UI chrome is a dense macOS **workbench**, not a shadowed card dashboard. We commit to **materials + soft borders/tints** for panel surfaces, and allow **shadows only on floating overlays** (command palette, popovers, sheets). Mixing elevation strategies made hierarchy noisy; one depth model keeps craft quiet and predictable.

Design tokens are renamed from generic `MacChrome*` / `MacPanel*` to `Workbench*` (`WorkbenchMetrics`, `WorkbenchTypography`, `WorkbenchPalette`, `WorkbenchMotion`, `WorkbenchMaterialWeight`, `workbenchPanelSurface`) with **no long-lived typealiases**. The rename costs a wide diff once, then names match the locked feel in `.interface-design/system.md` and stop reading like reusable template chrome.

**Status:** accepted (2026-07-25)

## Considered options

- Keep `MacChrome*` and document semantic aliases only — rejected; names would keep drifting from the product metaphor.
- Layered shadows as the default elevation language — rejected; fights menu-bar material density.
- Borders-only / minimize materials — rejected; existing material work (Plan 010) already fits the platform.

## Consequences

- Plans 025+ must compile against `Workbench*` only.
- New UI must map buttons to variants in `.interface-design/system.md` rather than inventing styles.
- Overlay shadows remain allowed; section/list “card shadows” are not.
