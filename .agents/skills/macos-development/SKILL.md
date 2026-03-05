---
name: macos-development
description: macOS-specific implementation guidance for SwiftUI/AppKit.
---

# macOS Development

## Baseline
- Keep UI state on main actor.
- Use AppKit bridges only when SwiftUI is insufficient.
- Keep status-item lifecycle deterministic (single registration, clean teardown).

## Validation
- Build with `make build`.
- For lifecycle-sensitive changes, run app and validate launch -> open menu -> close -> relaunch.
