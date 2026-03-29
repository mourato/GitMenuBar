---
name: menubar
description: Menu bar specific invariants for GitMenuBar, including NSStatusItem ownership, click behavior, and popover/window dismissal.
---

# Menu Bar

Use this skill for `NSStatusItem`, status item interaction, menu/popup opening, and app-style behavior that is unique to a menu bar app.

## Invariants

- Register the status item once and keep its lifetime explicit.
- Left-click, right-click, and modifier-click behavior must be intentional and documented in code.
- Opening the menu should not create duplicate controllers, duplicate work, or stale state.
- Dismissal must be predictable with outside click, focus changes, and `Esc` where applicable.

## Review Checklist

- Does the app remain menu-bar style after the change?
- Can the status item recover cleanly after relaunch or settings changes?
- Is app activation/deactivation behavior consistent with the expected UX?
- Are branch, project, and command surfaces reachable without unexpected windows appearing?

## Manual Checks

- Open from the status item repeatedly.
- Close and reopen after performing an action.
- Verify there is no unexpected Dock or window behavior.
