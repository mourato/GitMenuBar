---
name: accessibility-audit
description: Accessibility review checklist for GitMenuBar covering VoiceOver, keyboard navigation, focus order, contrast, and reduced-motion behavior.
---

# Accessibility Audit

Use this skill when changing menu UI, popovers, settings, keyboard shortcuts, or any interactive SwiftUI/AppKit surface.

## Minimum Bar

- Every interactive control needs a useful accessibility label.
- Keyboard-only users must be able to reach, trigger, and dismiss every primary action.
- Focus order must follow the visible reading and action order.
- Color cannot be the only signal for state.
- Transient UI must dismiss predictably with `Esc`.

## Review Checklist

- Can the full flow be completed without a pointer?
- Do popovers, alerts, and sheets place focus where the user expects?
- Are VoiceOver labels specific enough for branch, file, and repository actions?
- Does the UI still work with increased contrast, reduced motion, and reduced transparency?
- Are shortcut-only affordances still discoverable through labels, help text, or menus?

## GitMenuBar Focus

- Verify the status item remains reachable and understandable with assistive tech.
- Check branch lists, working tree rows, and history actions for row-level accessibility labels.
- Review command palette, settings panes, and repository pickers for tab order and escape behavior.
