# Plan 040: Ship Changed Files Summary in Commit Details

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 42cde45..HEAD -- GitMenuBar/Components/History/CommitDetailPageView.swift GitMenuBar/Components/History/CommitDetailPageView+Preview.swift GitMenuBar/Components/History/HistoryActionSet.swift GitMenuBar/Utils/GitHub/GitHubRemoteURLParser.swift GitMenuBar/Utils/DiffTree/ GitMenuBar/Components/WorkingTree/WorkingTreeFileRow.swift GitMenuBarTests/GitHubRemoteURLParserTests.swift plans/039-changed-files-diff-tree-foundation.md plans/040-commit-details-changed-files-summary.md plans/README.md CONTEXT.md .interface-design/system.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/039-changed-files-diff-tree-foundation.md
- **Category**: direction
- **Planned at**: commit `42cde45`, 2026-07-26

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: `no`
- **Reviewer required**: `yes` — Commit Details UX, accessibility, and external URL behavior
- **Rationale**: SwiftUI surface + GitHub URL navigation; medium ambiguity around chrome/a11y.
- **Escalate when**: Scope expands into an in-app diff viewer, working-tree Staged/Unstaged rewrite, or colored icon asset pipeline.

## Why this matters

Commit Details still shows a flat “Changed Files” list with a generic
`doc.text` icon and a prose stats line. Users want a T3-inspired **Changed
Files Summary**: collapsible Diff Tree, Compact Preview, Path Compaction,
expand/collapse-all folders, SF Symbol File Type Icons, and **Open Diff** to
GitHub (file-at-commit when possible). Keep **Workbench section chrome**
(ADR 0001 / `.interface-design/system.md`) — do not wrap this in a chat-style
bordered card.

## Current state

- Flat section in `CommitDetailPageView.swift`:

```165:180:GitMenuBar/Components/History/CommitDetailPageView.swift
    private func changedFilesSection(commit: Commit) -> some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
            Text("Changed Files")
                .font(WorkbenchTypography.sectionLabel)

            if commit.changedFiles.isEmpty {
                Text("No file list available for this commit.")
                // ...
            } else {
                VStack(spacing: WorkbenchMetrics.compactSpacing) {
                    ForEach(commit.changedFiles) { file in
                        CommitChangedFileRowView(file: file)
                    }
                }
            }
        }
    }
```

- Prose aggregate lives in `statsSummary(for:)` and is shown in `statsSection`:
  `"N files changed, X insertions(+), Y deletions(-)"`.
- `HistoryActionSet` already builds commit URLs; there is **no** file-at-commit
  (blob) URL helper yet:

```12:17:GitMenuBar/Components/History/HistoryActionSet.swift
        if let reference = GitHubRemoteURLParser.parse(remoteUrl) {
            commitURL = URL(string: "https://github.com/\(reference.owner)/\(reference.repository)/commit/\(commit.id)")
        } else {
            commitURL = nil
        }
```

- Line diff chips already exist as `WorkingTreeLineDiffView` in
  `WorkingTreeFileRow.swift` — reuse for per-node stats.
- Plan 039 must already have shipped `DiffTreeBuilder` +
  `ChangedFilesPresentation` under `GitMenuBar/Utils/DiffTree/`.
- UI files that render interface need `#Preview` (AGENTS.md).
- Reference UI (read-only):  
  `~/Documents/Projects/References/T3Code/apps/web/src/components/chat/ChangedFilesTree.tsx`

## Locked product decisions (do not reopen)

1. Surfaces this plan: **Commit Details only** (working tree is Plan 041).
2. Open Diff: header → commit URL; file row/chip →
   `https://github.com/<owner>/<repo>/blob/<sha>/<path>` when remote parses;
   else open on-disk file via existing `GitManager.openFile` / `NSWorkspace`
   if the executor wires a callback; if neither works, disable or no-op with
   accessibility hint — do not invent an in-app diff panel.
3. Path Compaction: on (via Plan 039).
4. Compact Preview when collapsed: on.
5. Auto-expand: ≤5 files and ≤200 changed lines (`shouldAutoExpand…`).
6. Chrome: Workbench section — **no** T3 chat card shell.
7. Aggregate `+X/-Y`: move into the Changed Files Summary header; **remove or
   shorten** the duplicate prose stats line in `statsSection` (decision 3B).
8. Icons: SF Symbols by extension/name only (colored icons = Plan 042).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift check | `git diff --stat 42cde45..HEAD -- <in-scope paths>` | empty or understood drift |
| Debug build | `make build` | exit 0 |
| Tests | `make test` | `Tests passed` |
| Agent gate | `make agent-check` | pass |
| Guidance (if docs touched) | `make guidance-check` | exit 0 |

## Suggested executor toolkit

- `global:macos-app-engineering`, `global:apple-design`, `global:accessibility-audit`
  (+ overlays).
- `global:swift-conventions`.
- Benchmarking overlay entry **T3Code** for visual parity checks.

## Scope

**In scope**:
- `GitMenuBar/Utils/GitHub/GitHubRemoteURLParser.swift` — add commit + blob URL
  builders (or thin wrappers)
- `GitMenuBarTests/GitHubRemoteURLParserTests.swift` — cover new URL helpers
- `GitMenuBar/Components/History/ChangedFilesSummaryView.swift` (create) —
  summary header, Compact Preview, Diff Tree, expand-all, Open Diff
- `GitMenuBar/Components/History/ChangedFilesSummaryView+Preview.swift`
  (create) **or** `#Preview` in the same file
- `GitMenuBar/Components/History/FileTypeSymbol.swift` (create) — path → SF Symbol
- `GitMenuBar/Components/History/CommitDetailPageView.swift` — replace flat
  section; adjust stats prose duplication
- `GitMenuBar/Components/History/CommitDetailPageView+Preview.swift` — update
  previews if needed
- `GitMenuBar/Components/History/HistoryActionSet.swift` — only if needed to
  expose blob URL helper inputs (prefer keeping URL construction in
  `GitHubRemoteURLParser`)
- `plans/README.md` status row

**Out of scope**:
- Working-tree Staged/Unstaged rewrite (041)
- Colored / Pierre-style icons (042)
- In-app diff viewer / DiffPanel
- Changing Commit Details toolbar/titlebar work from plan 037
- Copying assets or TSX from T3Code into the app bundle

## Git workflow

- Same feature branch / worktree as Plan 039.
- Prefer one commit for URL helpers + tests, one for the SwiftUI summary.
- Do not push/PR unless asked.

## Steps

### Step 1: Confirm Plan 039 landed

Ensure `DiffTreeBuilder`, `ChangedFilesPresentation`, and their tests exist and
pass. If missing, STOP and report — do not reimplement tree logic in views.

**Verify**: `make test` → `Tests passed` (includes DiffTree* tests)

### Step 2: Add GitHub blob/commit URL helpers

Extend `GitHubRemoteURLParser` (or a sibling enum in the same folder) with
pure functions, e.g.:

- `commitURL(owner:repository:sha:) -> URL?`
- `blobURL(owner:repository:sha:path:) -> URL?` →
  `https://github.com/{owner}/{repo}/blob/{sha}/{path}` with path segments
  percent-encoded appropriately (spaces, etc.)

Add XCTest cases for HTTPS/SSH-derived references and odd paths.

**Verify**: `make test` → `Tests passed`  
**Verify**: `rg -n "blob/" GitMenuBar/Utils/GitHub GitMenuBarTests` shows the helper + tests

### Step 3: SF Symbol File Type Icon map

Create `FileTypeSymbol.swift` mapping common extensions/names to SF Symbols
(examples — adjust to what exists on the deployment macOS version):

- `.swift` → `swift` if available, else `doc.text`
- `.md` → `doc.richtext` / `text.document`
- `.json` / `.yml` / `.yaml` → `curlybraces` / `doc.badge.gearshape`
- images → `photo`
- default → `doc`

Folders in the tree use `folder` / `folder.fill` when expanded if easy;
otherwise `folder`.

No custom PDF/SVG assets in this plan.

**Verify**: `make build` → exit 0

### Step 4: Build `ChangedFilesSummaryView`

Implement a reusable view that takes:

- `[CommitFileChange]` (or generic path + `LineDiffStats`)
- `commitSHA: String`
- `remoteURL: String`
- optional `onOpenLocalFile: (String) -> Void`

Behavior:

- Header: disclosure chevron, `"N changed file(s)"`, aggregate
  `WorkingTreeLineDiffView` (or equivalent), Hide/Show label, expand/collapse
  all folders (when expanded), Open Diff button (commit URL).
- Initial `expanded` from Plan 039 auto-expand helper.
- Collapsed + has files → Compact Preview (scopes + up to 3 chips + “Show all”).
- Expanded → Diff Tree from `DiffTreeBuilder`; directory rows toggle;
  file rows open blob URL (else local open callback).
- Accessibility: combined labels including additions/deletions; buttons have
  names (“Open diff”, “Expand all folders”, etc.).
- Respect `accessibilityReduceMotion` for expand transitions (opacity-only when
  reduced), matching `WorkingTreeSectionView`.
- Use `WorkbenchTypography` / `WorkbenchMetrics` / existing ghost/icon button
  styles — **no** new card shadow plate.

Include at least one `#Preview`.

**Verify**: `make build` → exit 0

### Step 5: Wire Commit Details + dedupe stats

- Replace `changedFilesSection` body with `ChangedFilesSummaryView`.
- Remove private `CommitChangedFileRowView` if unused.
- In `statsSection`, remove the prose `statsSummary` line **or** reduce it to
  non-duplicative metadata (decision 3B: aggregate live on the summary header).
  Keep Open on GitHub / copy / AI actions unchanged.
- Pass `remoteUrl` already available on the page.

**Verify**: `make agent-check` → pass  
**Verify**: `make test` → `Tests passed`

### Step 6: Manual UI checklist (record in PR / handoff notes)

Cannot be fully automated — executor must note results:

- [ ] Commit with 1–3 files auto-expands
- [ ] Commit with many files starts collapsed and shows Compact Preview
- [ ] Expand-all toggles nested folders
- [ ] Open Diff opens commit page when GitHub remote exists
- [ ] File row opens blob URL
- [ ] Non-GitHub remote: local open fallback or graceful disable
- [ ] VoiceOver reads file name + diff stats

## Test plan

- URL helper unit tests (required).
- Keep Diff Tree unit tests green.
- UI: `#Preview` coverage for summary expanded, collapsed preview, and empty
  list. No UI snapshot tests required unless the repo already has a pattern for
  Commit Details (it does not — do not invent).

## Done criteria

- [ ] Commit Details uses Changed Files Summary (tree + preview + Open Diff)
- [ ] Aggregate `+X/-Y` is not duplicated as the old full prose stats line
- [ ] Blob/commit URL helpers tested
- [ ] SF Symbol icons for common types; default fallback exists
- [ ] `#Preview` present for new UI file(s)
- [ ] `make build`, `make test`, `make agent-check` pass
- [ ] No working-tree section rewrite
- [ ] `plans/README.md` 040 → DONE

## STOP conditions

- Plan 039 artifacts missing.
- Implementing an in-app diff viewer seems “necessary.”
- Touches to `WorkingTreeSectionView` / staging actions creep in.
- Drift in Commit Details toolbar/header files unrelated to changed files.
- Verification fails twice.

## Maintenance notes

- Plan 041 should reuse `ChangedFilesSummaryView` patterns or extract shared
  row chrome — avoid forking tree rendering.
- Plan 042 replaces `FileTypeSymbol` visuals without changing navigation.
- Reviewer focus: URL encoding, a11y labels, Workbench chrome compliance
  (no nested card shadow), stats dedupe.
