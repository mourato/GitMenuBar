---
kind: project-overlay
extends: accessibility-audit
project: GitMenuBar
precedence: project
---

# GitMenuBar accessibility overlay

- Treat the status item, repository picker, branch lists, working-tree rows,
  history actions, command palette, and settings panes as primary surfaces.
- Verify branch, file, repository, and cleanup actions have specific labels;
  color is never the only state signal.
- Popovers and transient actions must have predictable outside-click, focus,
  and `Esc` dismissal while remaining usable with Full Keyboard Access and
  VoiceOver.
- Check Reduce Motion, Reduce Transparency, Increase Contrast, and keyboard
  focus behavior for menu-bar flows.
