---
name: macos-development
description: macOS-specific implementation guidance for SwiftUI/AppKit lifecycle, bridge boundaries, and platform services in GitMenuBar.
---

# macOS Development

Use this skill when implementing platform behavior, not just visual polish.

## Focus Areas

- App lifecycle and activation policy
- Window, popover, and controller ownership
- SwiftUI to AppKit bridges
- Persistence of desktop-specific state
- Main-actor coordination for UI state

## Core Rules

- Keep platform state ownership explicit; one controller should own each window, popover, or status item lifecycle.
- Use AppKit only where SwiftUI is insufficient or less reliable.
- Cross the SwiftUI/AppKit boundary in a small adapter layer instead of leaking AppKit concerns across feature code.
- Persist desktop state only when it improves continuity and stays predictable across relaunches.

## Validation

- `make build`
- For lifecycle-sensitive changes: launch, open the menu or window, dismiss it, and relaunch.
- Confirm activation behavior stays intentional: no stray Dock presence, rogue windows, or orphaned popovers.
