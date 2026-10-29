# Plan 003: Commit detail header hierarchy

## Status

- **Priority**: P2
- **Effort**: S–M
- **Risk**: LOW–MED (touches the history parser)
- **Depends on**: 002
- **Planned at**: commit `fa92af4`, 2026-10-29

## Execution profile

- **Recommended profile**: `implementer`
- **Suggested executor**: Antigravity Gemini Flash 3.8, `high`
- **Risk/lane**: `Low/Fast` for views; parser change needs a test
- **Parallelizable**: with 005; not with 004 (same file)
- **Reviewer required**: yes, light; check the parser test
- **Escalate when**: other features read `Commit.body` expecting the subject

## Problems

- Panel header shows project name plus the full 40-character hash, wrapped
  across two lines (`SidePanelHeaderView`, title from the selection).
- A separate "Back to History" button repeats the close button.
- The commit body repeats the subject: the parser uses `%B` (subject + body)
  in `GitMenuBar/Services/Git/CommitHistoryParser.swift:18`.

## Target layout (top to bottom)

1. Commit subject: `WorkbenchTypography.windowTitle`, `lineLimit(3)`,
   `.accessibilityAddTraits(.isHeader)`. Close button on the same row,
   top-aligned: `xmark` 12pt semibold in a 28 × 28 pt hit area
   (`WorkbenchMetrics.iconHitTarget`), same as `SidePanelHeaderView`.
2. Avatar (circle, 24 pt), author name in
   `WorkbenchTypography.detail.weight(.semibold)`, short hash chip
   (`commit.shortHash`, `.caption.monospaced()`, `WorkbenchPalette.hoverFill()`,
   `WorkbenchMetrics.microCornerRadius`, horizontal padding `chipSpacing`). The chip copies the full hash on click and has
   `.help` with the full hash. Second line: relative and absolute time.
   Author email moves to `.help` on the name.
3. Body text in `WorkbenchTypography.detail`, `.primary` color,
   only if not empty. Section spacing `WorkbenchMetrics.sectionSpacing`.

## Change

1. For `.commit` selections, do not render `SidePanelHeaderView` with the hash;
   render the subject header inside `CommitDetailPageView` instead. Keep
   `SidePanelHeaderView` for other selections. Do not show the project name
   here; the toolbar already shows it.
2. Remove the "Back to History" button and the `onBack` parameter if it
   becomes unused. Close button and `Esc` stay.
3. Parser: change `%B` to `%b`. Add or update a parser test: a commit with
   subject and body yields a body without the subject; a subject-only commit
   yields an empty body. Check all `Commit.body` readers (for example the
   message editor and AI generation) still get what they need; if one needs
   the full message, build it from `subject` + `body` there.
4. Avatar shape: circle instead of rounded square.

## Acceptance

- Header reads: subject, then author with short hash, then time.
- No 40-character hash on screen; full hash is reachable by click and tooltip.
- Body never repeats the subject.
- VoiceOver reads subject as a header, and the hash chip as "Copy commit hash".

## Evidence for UI review

Follow "UI review rubric and evidence" in `README.md`. Hand off the list of
`#Preview` names and the screenshot paths.

## Validation

- `make test-focused TEST_FILTER='GitMenuBarTests/CommitHistoryParserTests'`
  (or the existing parser test class)
- `make check-preview`, `make lint-changed`
