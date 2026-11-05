# GitMenuBar coding standards

Read during review (Standards axis) and retro. Extends the global standards at
`${AGENT_CONFIG_HOME:-$HOME/.agents}/core/standards/CODING_STANDARDS.md` and the
`swift-conventions` skill; project rules only.

## Review focus

- Failure here: a Git action that changes the wrong repository, branch, or
  worktree, or reports success before Git confirms it.
- Failure here: a status item, popover, or window that stops responding or
  leaves an orphaned controller.
- Skip: `GitMenuBar/Assets.xcassets/` content changes.
- Needs a person: `GitMenuBar/Services/Git/` (commit, push, discard, and
  branch cleanup) and `GitMenuBar/Services/Credentials/`.
- The [thermo review profile](.agents/review-profiles/thermo-gitmenubar.md)
  still applies; this section does not repeat it.

## Ownership

- Git services, menu-bar controllers, SwiftUI views, and AppKit adapters stay
  separate; Git operations never live in views.
- Feature UI stays with its feature; shared UI only after reuse is established.
- One `NSStatusItem` owner. Preserve left/right/modifier-click, activation
  policy, settings, outside-click, focus-change, and `Esc` dismissal without
  orphaned windows or duplicate controllers.

## UI

- Calm, direct feedback in compact popovers and panels; transitions anchor to
  their status-item or action origin; no layout churn in dense Git lists.
- No ellipses in visible labels; placement, grouping, icon, or helper text
  signals that an action opens more UI.
- Main-window previews use `MainMenuPreviewHarness(showsTransparentTitlebar: true)`;
  component previews do not simulate window chrome.
- A pull request that adds a UI file without preview coverage is incomplete.

## Accessibility

- Primary surfaces: status item, repository picker, branch lists, working-tree
  rows, history actions, command palette, settings panes.
- Action labels name the affected repository, branch, file, or worktree.
- Status, selection, focus, and completion feedback survive Reduce Motion;
  motion stays supplemental to keyboard and VoiceOver cues.
