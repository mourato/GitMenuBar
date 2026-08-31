# Plan 039: Add shared Diff Tree foundation for Changed Files Summaries

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 42cde45..HEAD -- GitMenuBar/Models/GitModels.swift GitMenuBar/Utils/ GitMenuBarTests/ plans/039-changed-files-diff-tree-foundation.md plans/README.md CONTEXT.md .agents/overlays/reference-apps.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: direction
- **Planned at**: commit `42cde45`, 2026-07-26

## Execution profile

- **Recommended profile**: `implementer-fast`
- **Risk/lane**: `Low/Fast`
- **Parallelizable**: `no` — this establishes the shared contract for 040–041
- **Reviewer required**: `no`
- **Rationale**: Pure Foundation value types + XCTest; no SwiftUI, Git mutation, or persistence.
- **Escalate when**: The builder must call Git, touch the filesystem, or change `WorkingTreeFile` / `CommitFileChange` public shapes in a breaking way.

## Why this matters

Commit Details and the main working-tree sections still render **flat** file
rows. T3 Code’s Changed Files Summary (benchmark reference under
`~/Documents/Projects/References/T3Code`, Nightly tag
`v0.0.29-nightly.20260725.899`) uses a hierarchical Diff Tree with path
compaction, aggregated `+N/-M` stats, auto-expand thresholds, and a compact
collapsed preview. GitMenuBar needs the same pure logic in Swift before any UI
port so Commit Details (040) and working-tree migration (041) share one tested
contract.

## Current state

- `CommitFileChange` and `WorkingTreeFile` already expose `path` + `LineDiffStats`
  (`added` / `removed`) in `GitMenuBar/Models/GitModels.swift`:

```47:73:GitMenuBar/Models/GitModels.swift
struct CommitFileChange: Identifiable, Equatable, Hashable {
    let path: String
    let lineDiff: LineDiffStats
    // ...
}

struct LineDiffStats: Hashable {
    let added: Int
    let removed: Int
    static let zero = LineDiffStats(added: 0, removed: 0)
}
```

- Commit Details lists files flat in `changedFilesSection` /
  `CommitChangedFileRowView` (`CommitDetailPageView.swift`).
- Working tree uses flat `WorkingTreeFileRowView` inside Staged/Unstaged
  sections (`WorkingTreeSectionView.swift`).
- Path helpers live under `GitMenuBar/Utils/Paths/` (e.g.
  `PathDisplayFormatter.swift`) — Foundation-only enums, XCTest in
  `GitMenuBarTests/`.
- Xcode uses `PBXFileSystemSynchronizedRootGroup`: new files under
  `GitMenuBar/` and `GitMenuBarTests/` do **not** require `project.pbxproj`
  edits.
- Vocabulary (use these names in types/comments): see root `CONTEXT.md` —
  **Diff Tree**, **Path Compaction**, **Compact Preview**, **Changed Files Summary**.
- Reference algorithm (read-only inspiration, MIT):  
  `~/Documents/Projects/References/T3Code/apps/web/src/lib/turnDiffTree.ts`  
  `~/Documents/Projects/References/T3Code/apps/web/src/components/chat/changedFilesPresentation.ts`

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift check | `git diff --stat 42cde45..HEAD -- <in-scope paths>` | empty or understood drift only |
| Debug build | `make build` | exit 0 |
| Full tests | `make test` | `Tests passed` |
| Agent gate | `make agent-check` | lint-changed + Debug build pass |

## Suggested executor toolkit

- `global:swift-conventions` (+ overlay) for naming/layout.
- `global:reference-apps` (+ `.agents/overlays/reference-apps.md`) if you need to
  re-open the T3Code Diff Tree reference.
- Local `swift-testing-expert` only if converting style; prefer XCTest to match
  existing `GitHubRemoteURLParserTests.swift` / `WorkingTreeParserTests.swift`.

## Scope

**In scope**:
- `GitMenuBar/Utils/DiffTree/DiffTreeModels.swift` (create)
- `GitMenuBar/Utils/DiffTree/DiffTreeBuilder.swift` (create)
- `GitMenuBar/Utils/DiffTree/ChangedFilesPresentation.swift` (create)
- `GitMenuBarTests/DiffTreeBuilderTests.swift` (create)
- `GitMenuBarTests/ChangedFilesPresentationTests.swift` (create)
- `plans/README.md` (status row only)

**Out of scope**:
- Any SwiftUI views (Plan 040 / 041)
- SF Symbol or colored file icons (040 / 042)
- GitHub URL helpers (040)
- Edits to `WorkingTreeSectionView`, `CommitDetailPageView`, or Git services
- Copying TypeScript/React source into the repo
- `project.pbxproj` edits

## Git workflow

- Work on branch `feat/t3code-changed-files-summary` (this worktree) or a
  child branch off it.
- Commit style (from recent history): `feat(…):` / `fix(…):` / `docs(…):`
  imperative summary.
- Do **not** push or open a PR unless the operator asks.

## Steps

### Step 1: Add Diff Tree value types

Create `DiffTreeModels.swift` with immutable Foundation types (no SwiftUI):

- `DiffTreeStat` — `additions: Int`, `deletions: Int` (map from
  `LineDiffStats.added` / `.removed` at the call site).
- `DiffTreeNode` — enum or equivalent with:
  - directory: `name`, `path`, `stat`, `children: [DiffTreeNode]`
  - file: `name`, `path`, `stat: DiffTreeStat?`
- Keep types `Equatable` / `Hashable` where natural.
- Do **not** embed staging status here; Plan 041 will pass status beside the
  node at the UI layer.

**Verify**: `make build` → exit 0

### Step 2: Implement builder + Path Compaction + aggregate stats

Create `DiffTreeBuilder.swift`:

- Input: sequence of `(path: String, stat: DiffTreeStat?)` (or a small
  `DiffTreeFileInput` struct).
- Normalize `\` → `/`, drop empty segments.
- Build a directory tree; directories first, then files; sort with
  numeric-aware, case-insensitive name compare (mirror T3’s
  `localeCompare(..., { numeric: true, sensitivity: "base" })` via
  `String.CompareOptions` / `localizedStandardCompare` as appropriate).
- Aggregate stats upward to every ancestor directory.
- **Path Compaction**: while a directory has exactly one child and that child
  is a directory, merge names to `parent/child` and keep the child’s path +
  children (see T3 `compactDirectoryNode`).
- `summarizeDiffTreeStats(_:)` → total additions/deletions across inputs.

**Verify**: `make build` → exit 0

### Step 3: Implement Compact Preview + auto-expand helpers

Create `ChangedFilesPresentation.swift` with constants matching T3 v1:

- `autoExpandFileLimit = 5`
- `autoExpandLineLimit = 200` (additions + deletions)
- `previewFileLimit = 3`
- `previewScopeLimit = 4`

Functions:

- `shouldAutoExpandChangedFiles(fileCount:totalChangedLines:isPrimaryContext:)` —
  auto-expand only when `isPrimaryContext` is true, `fileCount <= 5`, and
  `totalChangedLines <= 200`. For Commit Details, `isPrimaryContext` means
  “this is the commit being viewed” (always true on that page). Do not invent
  a “latest turn” concept in GitMenuBar.
- `summarizeChangedFileScopes(paths:limit:)` — group by first path segment
  (or `"root"`), order by file count desc then first-seen index, cap at limit.
- `selectChangedFilePreview(paths:limit:)` — prefer one file per distinct
  first-segment scope, then fill remaining slots.
- `changedFileName(path:)` — last path component.

**Verify**: `make build` → exit 0

### Step 4: Unit tests

Add XCTest coverage modeled on `GitHubRemoteURLParserTests.swift`:

`DiffTreeBuilderTests.swift`:
- Flat files at repo root
- Nested folders with aggregated directory stats
- Path compaction of single-child chains
- Mixed separators / empty segments ignored
- Stable sort order

`ChangedFilesPresentationTests.swift`:
- Auto-expand true/false for file count and line budget
- Scope summary ordering and limit
- Preview selection prefers distinct scopes then fills

**Verify**: `make test` → `Tests passed`  
**Verify**: `make agent-check` → pass

## Test plan

- Pure unit tests only; no temporary Git repos required.
- Pattern: `@testable import GitMenuBar` + `XCTestCase` like
  `GitMenuBarTests/GitHubRemoteURLParserTests.swift`.

## Done criteria

- [ ] Diff Tree types + builder + presentation helpers exist under
      `GitMenuBar/Utils/DiffTree/`
- [ ] Path compaction and aggregate stats covered by tests
- [ ] Auto-expand thresholds are 5 files / 200 lines
- [ ] `make build` exits 0
- [ ] `make test` exits 0
- [ ] `make agent-check` exits 0
- [ ] No files outside the in-scope list are modified
- [ ] `plans/README.md` status row for 039 updated to DONE

## STOP conditions

- Building the tree appears to require changing Git parsing or network code.
- An in-scope file’s current state no longer matches the excerpts above.
- A verification command fails twice after a reasonable fix.
- You believe SwiftUI must be introduced in this plan.

## Maintenance notes

- Plans 040–041 must consume these helpers rather than re-implementing tree
  logic in views.
- If thresholds change product-wise, edit constants in
  `ChangedFilesPresentation.swift` and update tests in the same PR.
- Reviewer focus: compaction correctness on deep Swift package paths; no
  locale-sensitive sort regressions.
