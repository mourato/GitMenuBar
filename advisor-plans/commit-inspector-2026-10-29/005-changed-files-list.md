# Plan 005: Changed files as a vertical list

## Status

- **Priority**: P2
- **Effort**: S–M
- **Risk**: LOW
- **Depends on**: 002
- **Planned at**: commit `fa92af4`, 2026-10-29

## Execution profile

- **Recommended profile**: `implementer-fast`
- **Suggested executor**: OpenCode free model
- **Risk/lane**: `Low/Fast`
- **Parallelizable**: yes, with 003 and 004
- **Reviewer required**: no; author diff review is enough
- **Escalate when**: the change needs new data in `CommitFileChange`

## Problem

`GitMenuBar/Components/History/ChangedFilesSummaryView.swift` shows files as
wrapping chips. Rows misalign, names truncate, and "Show all 4 files" hides
one file out of four.

## Target

- Summary row: "N changed files", then `+insertions` (green), `−deletions`
  (red), a small proportion bar (40 × 5 pt, radius 2.5, existing diff colors),
  and an "Open Diff" button (`.workbenchGhost()`).
- Keep existing group headers (for example "Shared", "Mac") as small
  uppercase section labels.
- Row height: at least 24 pt; spacing `WorkbenchMetrics.microSpacing`.
- One row per file: file-type icon, file name (middle truncation), directory
  in secondary color with `.help` showing the full path, then per-file
  `+added −removed` from `CommitFileChange.lineDiff`, right-aligned and
  monospaced digits.
- Show all files when there are 8 or fewer; otherwise show 8 and a
  "Show All N Files" button.
- Keep existing open-file actions (`onOpenLocalFile`, GitHub links).
- Do not add status letters; the model has no status field.

## Evidence for UI review

Follow "UI review rubric and evidence" in `README.md`. Hand off the list of
`#Preview` names and the screenshot paths.

## Validation

- `make check-preview`, `make lint-changed`
- Manual: commit with 1 file, 4 files, 30 files; long paths.
