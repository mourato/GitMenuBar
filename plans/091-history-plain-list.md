# Plan 091: Rebuild history rows as a plain, information-dense list

> **Executor instructions**: Read this brief, `AGENTS.md`,
> [project workflow facts](../docs/agents/project-workflow.md),
> [UI contract](../docs/ui.md) (especially "Visual hierarchy rules"), and
> [ADR 0020](../docs/adr/0020-toolbar-actions-and-history-list.md) before
> editing. Work in a dedicated worktree. Use Workbench tokens only; no raw
> sizes, colors, or opacities in views. On a STOP condition, stop and report;
> do not widen scope. Leave merge and push to the operator. The UI owner
> reviews the diff and screenshots before merge.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MEDIUM
- **Depends on**: none (touches only Components/History)
- **Category**: ui (premium main-window pass)
- **Planned at**: commit e48a916, 2026-10-28
- **Integration**: main; merge and push require explicit operator authorization

## Execution profile

- **Recommended profile**: Standard/full
- **Risk/lane**: MEDIUM (dense list performance, parsing)
- **Executor**: Codex GPT 5.6 Luna, reasoning xhigh
- **Parallelizable**: Yes
- **Reviewer required**: Yes
- **Rationale**: Dense list with a new parser; needs tests and scroll performance care.
- **Escalate when**: rows need data beyond the `Commit` model, or scroll performance drops on a 1,000-commit history.

## Problem

History rows show only the subject with a trailing chevron. A vertical line
looks like a commit graph but carries no data. Merge commits look like other
commits. The selected row competes with the sidebar selection.

## Scope

1. In `HistoryTimelineSectionView.swift` remove the connecting line
   (`Rectangle()` rail) and the trailing chevron.
2. Row layout: state dot, subject (one line, tail truncation), `shortHash`
   in monospaced caption, author, relative time from
   `HistoryTimelineDateFormatter`.
3. Dot: filled accent when selected, outline otherwise, smaller and dimmed
   row when `Commit.isMergeCommit`.
4. Add a pure parser for conventional-commit prefixes (`type(scope)!:`)
   returning type, scope, and the remaining subject. Render type as a small
   tinted chip and scope in secondary text. Unknown types render as plain
   text.
5. Selection uses `WorkbenchPalette.selectedFill()`; keep the existing
   keyboard navigation and context menus.

## Acceptance

- Parser tests cover: plain subject, `fix:`, `feat(scope):`, `feat!:`,
  `Merge branch ...`, and colons inside the subject.
- VoiceOver reads "subject, author, time"; merge rows say "merge commit".
- Matches the approved prototype and `docs/ui.md` hierarchy rules.

## Validation

- `make lint-changed`
- `make check-preview` (add or update previews for every changed view)
- `make build`
- Screenshots of the changed surface in Dark and Light, plus Increase
  Contrast, attached to the handoff.
- `make test-focused TEST_FILTER='GitMenuBarTests/ConventionalCommitSubjectTests'`

## STOP conditions

- An unexpected changed path outside this scope.
- A rule in `docs/ui.md` blocks the change: report it; the UI owner decides.
