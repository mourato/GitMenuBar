---
kind: project-overlay
extends: apple-design
project: GitMenuBar
precedence: project
---

# GitMenuBar Apple Design overlay

- GitMenuBar is a menu-bar Git workflow app; favor calm, direct feedback in
  compact popovers, panels, repository pickers, and branch/worktree surfaces.
- Use the project motion defaults and review checklist in
  [the GitMenuBar motion reference](references/gitmenubar-motion.md).
- Preserve status, selection, focus, and completion feedback when Reduce
  Motion is enabled; motion must remain supplemental to keyboard and
  VoiceOver cues.
- Keep popover and panel transitions anchored to their status-item or action
  origin and avoid layout churn in dense Git lists.
