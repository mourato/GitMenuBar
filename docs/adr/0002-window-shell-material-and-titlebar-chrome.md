# Window shell material and titlebar chrome

The main panel and Settings window use a **window-level material/vibrancy shell** (Reduce Transparency → solid control/window backgrounds), not an opaque content fill with materials only on nested plates. Large nested `workbenchPanelSurface` plates on the main column are avoided so they do not double-frost the shell; popovers and sheets keep elevated materials. Header chrome is **AppKit titlebar/toolbar-aligned**: traffic lights, project selector, and Settings gear share one horizontal line — SwiftUI-only approximation is insufficient for true alignment with `fullSizeContentView`.

**Liquid Glass:** earlier builds opted out of the SDK's newer system chrome through `UIDesignRequiresCompatibility`. That key was removed on 2026-09-02. The main window now adopts the current native `NSToolbar` while retaining the transparent full-size content setup and traffic lights. A borderless `NSPanel` remains an alternative only if the product later chooses to remove window chrome altogether.

**Status:** accepted (2026-07-25); native toolbar adoption and compatibility-key removal recorded 2026-09-02

## Considered options

- SwiftUI-only padding to fake traffic-light alignment — rejected; vertical mismatch remains on transparent titlebars.
- Main-panel-only material shell (defer Settings) — rejected for this wave; Settings must match.
- Nested materials on every section plus a glass shell — rejected; muddy stacking.
- Targeted `.sharedBackgroundVisibility(.hidden)` only — not needed for the main window after adopting the current native toolbar; revisit if Settings needs an independent treatment.

## Consequences

- Plans 031–032 own titlebar embedding and shell wiring in `StatusBarController` / Settings window setup.
- Command-palette scrim must cover the full window (including under the titlebar), outside content `windowPadding`.
- `.interface-design/system.md` depth strategy includes the window shell; quota strip may grow into Mimir-style cards (Plan 033) without status-item glyphs.
- The main window continues to use a titled `NSWindow` only as the system owner of traffic lights and toolbar chrome; the content remains full-size and transparent beneath it.
