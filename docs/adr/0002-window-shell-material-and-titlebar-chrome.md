# Window shell material and titlebar chrome

The main panel and Settings window use a **window-level material/vibrancy shell** (Reduce Transparency → solid control/window backgrounds), not an opaque content fill with materials only on nested plates. Large nested `workbenchPanelSurface` plates on the main column are avoided so they do not double-frost the shell; popovers and sheets keep elevated materials. Header chrome is **AppKit titlebar/toolbar-aligned**: traffic lights, project selector, and Settings gear share one horizontal line — SwiftUI-only approximation is insufficient for true alignment with `fullSizeContentView`.

**Status:** accepted (2026-07-25)

## Considered options

- SwiftUI-only padding to fake traffic-light alignment — rejected; vertical mismatch remains on transparent titlebars.
- Main-panel-only material shell (defer Settings) — rejected for this wave; Settings must match.
- Nested materials on every section plus a glass shell — rejected; muddy stacking.

## Consequences

- Plans 031–032 own titlebar embedding and shell wiring in `StatusBarController` / Settings window setup.
- Command-palette scrim must cover the full window (including under the titlebar), outside content `windowPadding`.
- `.interface-design/system.md` depth strategy includes the window shell; quota strip may grow into Mimir-style cards (Plan 033) without status-item glyphs.
