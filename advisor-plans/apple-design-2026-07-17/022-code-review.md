# Code review — Plan 022

## Scope

Reviewed the complete Plan 022 diff in `StatusBarController.swift` using the
GitMenuBar thermo review profile, the menu-bar lifecycle invariants, and the
Apple Design AppKit presentation guidance.

## Findings and resolution

No unresolved code findings.

The review specifically verified that:

- positioning still happens before activation and ordering the window front;
- the close path persists the frame before starting the fade;
- `orderOut` is called only from the current transition completion;
- a monotonically increasing transition ID invalidates stale completions when
  opening interrupts a close or closing interrupts an opening;
- Reduce Motion uses the supported `NSWorkspace` accessibility property and a
  short opacity transition without changing ordering semantics;
- attached sheets, status-item ownership, auto-hide guards, shortcut handling,
  and repository refresh calls remain untouched.

## Validation

- `make agent-check` — passed.
- `make lint && make test` — passed; 0 serious lint violations and all tests
  passed. Existing non-blocking lint warnings remain in unrelated baseline
  files.
- `git diff --check` — passed.
- SDK inspection confirmed `NSWorkspace.accessibilityDisplayShouldReduceMotion`
  and `NSAnimationContext.runAnimationGroup(...completionHandler:)` are
  available in the deployment SDK.

## Manual verification limitation

This CLI session has no desktop UI harness, so the status-item toggle, close
button, auto-hide-on-blur, attached-sheet, keyboard-shortcut, Reduce Motion,
and reopen-during-fade checklist could not be exercised interactively. The
implementation preserves those existing code paths; these scenarios remain a
manual macOS acceptance check.

## Verdict

Approved for merge with the manual macOS acceptance check recorded above.
