---
name: menubar
description: NSStatusItem and menu bar interaction patterns.
---

# Menu Bar Patterns

## Standards
- Status item should be initialized once.
- Left-click and right-click behavior must be explicit and predictable.
- Menu labels and action affordances should stay concise.

## Manual checks
- Verify menu opens reliably.
- Verify action handlers run on intended threads/actors.
- Verify app stays menu-bar style (no unexpected dock/window behavior).
