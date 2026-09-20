# Window shell material and titlebar chrome

The main panel and Settings window use a **window-level material/vibrancy shell** (Reduce Transparency → solid control/window backgrounds), not an opaque content fill with materials only on nested plates. Large nested `workbenchPanelSurface` plates on the main column are avoided so they do not double-frost the shell; popovers and sheets keep elevated materials. Header chrome is **AppKit titlebar/toolbar-aligned**: the main window follows the GUGU Settings pattern of an opaque titlebar, native unified toolbar, visible native window title, and no separator hairline. SwiftUI-only approximation is insufficient for true alignment with native titlebar ownership.

**Liquid Glass:** earlier builds opted out of the SDK's newer system chrome through `UIDesignRequiresCompatibility`. That key was removed on 2026-09-02. The main window now adopts the current native `NSToolbar` while retaining the full-size content window style and traffic lights; the titlebar material is system-owned and opaque, matching the GUGU Settings chrome. A borderless `NSPanel` remains an alternative only if the product later chooses to remove window chrome altogether.

**Status:** accepted (2026-07-25); native toolbar adoption and compatibility-key removal recorded 2026-09-02

**Update (native sidebar toggle and sidebar footer):** following Cue's native split view and unified chrome pattern, the sidebar collapse toggle is integrated natively via AppKit's standard `NSToolbarItem.Identifier.toggleSidebar` in the unified toolbar, placing the toggle at the top leading chrome aligned directly above the sidebar column. The manual toolbar toggle button (`MainWindowToolbarItemIdentifier.sidebarToggle`) and the redundant collapse button in the sidebar footer have been removed. The sidebar footer now hosts only the quota strip and Settings gear.

**Update (sidebar-local toggle):** the visible sidebar now owns the collapse control
in its footer beside Settings. The native `.toggleSidebar` toolbar item remains
only while the sidebar is collapsed, providing the re-entry control without
duplicating the visible-state affordance.

## Considered options

- SwiftUI-only titlebar approximation — rejected; traffic lights, native title, and toolbar alignment belong to AppKit's window chrome.
- Main-panel-only material shell (defer Settings) — rejected for this wave; Settings must match.
- Nested materials on every section plus a glass shell — rejected; muddy stacking.
- Targeted `.sharedBackgroundVisibility(.hidden)` only — not needed for the main window after adopting the current native toolbar; revisit if Settings needs an independent treatment.

## Consequences

- Plans 031–032 own titlebar embedding and shell wiring in `StatusBarController` / Settings window setup.
- Command-palette scrim must cover the full window (including under the titlebar), outside content `windowPadding`.
- `.interface-design/system.md` depth strategy includes the window shell; quota strip may grow into Mimir-style cards (Plan 033) without status-item glyphs.
- The main window continues to use a titled `NSWindow` as the system owner of traffic lights, native title, and toolbar chrome. The workbench keeps its window-level material shell without adding a second hand-drawn titlebar surface.
