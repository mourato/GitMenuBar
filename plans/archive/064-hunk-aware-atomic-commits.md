# Plan 064: Split atomic commits by diff hunk

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the **STOP conditions** section occurs, stop and
> report — do not improvise. When done, update the status row for this plan in
> `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat d362977..HEAD -- GitMenuBar GitMenuBarTests`
> If any in-scope file changed since this plan was written, compare the
> **Current state** excerpts against the live code before proceeding. A
> mismatch is a STOP condition.

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: none; reconcile Plan 057's status before execution if the repository governance requires it
- **Category**: bug
- **Planned at**: commit `d362977`, 2026-08-09

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `High/Full`
- **Parallelizable**: `no` — the model, AI prompt, review UI, Git index transaction, and callers must evolve together.
- **Reviewer required**: `yes` — this changes commit/index mutation and rollback behavior, in addition to user-visible SwiftUI.
- **Rationale**: The smallest safe implementation is still cross-layer and must prove that selected hunks become separate commits without losing working-tree content or silently accepting stale plans.
- **Escalate when**: The implementation needs to preserve arbitrary pre-existing staged hunks, support binary/rename hunk splitting, change Companion CLI JSON, add a new dependency, or touch Keychain, persistence, concurrency, push, or branch operations.

## Why this matters

The atomic-commit flow currently treats a file path as the smallest unit. When
the AI returns one path in two groups, `AtomicCommitPlan` rejects the plan as a
duplicate before any commit is made, so the entire command is cancelled. A
file can legitimately contain unrelated changes, so the correct unit is a
diff hunk: different hunks from one file may belong to different commits.

This plan adds hunk-aware grouping and staging for the menu-bar atomic-commit
flow. It keeps whole-file fallback for untracked, binary, deleted, renamed, or
otherwise non-splittable changes, and rejects stale or unsafe plans before
mutating the repository.

## Current state

The executor must confirm these facts before editing:

- `GitMenuBar/Models/GitModels.swift:273-354` — `AtomicCommitGroup` stores only
  `files: [String]`; `AtomicCommitPlan` rejects a path seen in more than one
  group with `duplicateFile`.
- `GitMenuBar/Services/AI/AICommitGrouperService.swift:26-106` — the AI parser
  accepts only `files` and `message`. It does not identify hunks or validate
  group ownership against a diff snapshot.
- `GitMenuBar/Services/AI/AICommitGrouperService+Prompt.swift:8-25` — the
  prompt requires every changed file to appear exactly once and returns only
  file paths.
- `GitMenuBar/Components/AI/AtomicCommitReviewSheet.swift:75-192` — the
  review surface renders file rows and moves/removes complete files. It has a
  preview at `:248-260`; retain preview coverage after the UI change.
- `GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift:393-421` — the reviewed
  flow generates groups from `changedFiles` plus per-file diffs, then executes
  groups after closing the sheet.
- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift:326-356` — the automatic
  split-commit path generates file groups and falls back to one group per
  file.
- `GitMenuBar/Services/Git/GitAtomicCommitService.swift:63-117` — one group is
  staged with `git restore --staged -- .` followed by `git add -- <files>` and
  `git commit`.
- `GitMenuBar/Services/Git/GitAtomicCommitService.swift:120-169` — execution
  validates the file-only plan, commits groups sequentially, and rolls back a
  partial sequence with `git reset --mixed`.
- `GitMenuBar/Services/Git/GitExecution.swift:35-47` and
  `GitMenuBar/Services/Git/GitCommandRunner.swift:10-23` — Git commands already
  support `additionalEnvironment`, but `GitAtomicCommitService`'s private
  command helper does not expose it. This is the existing seam for a temporary
  `GIT_INDEX_FILE` transaction.
- `GitMenuBar/Services/CLI/CompanionCLIService.swift:105-185` — the companion
  CLI also uses file-only groups. Keep its existing file-level contract in
  this plan; do not change `GitMenuBar/Services/CLI/*` or its JSON schema.
- `GitMenuBarTests/GitManagerAtomicCommitTests.swift:58-181` — integration
  tests already cover multiple commits, validation before mutation, and
  rollback after a later commit fails. Extend this file for hunk execution.
- `GitMenuBarTests/AICommitGrouperServiceTests.swift:23-238` — parser and
  fallback tests use a stub AI provider. Extend this pattern for hunk-shaped
  responses.

The repository's relevant conventions are:

- Swift code is formatted/linted with the repository scripts; use `make
  agent-check` during implementation and `make lint && make test` before
  handoff.
- Git mutations return `Result` or a localized error and run through the
  existing `GitExecution`/`GitCommandRunner` seam. Do not shell out through a
  second process abstraction.
- UI-rendering Swift files require a `#Preview`. Reuse the existing
  `AtomicCommitReviewSheet` preview and add previews only if a new UI file is
  created.
- Existing atomic commits intentionally use `--no-gpg-sign`; preserve that
  behavior. Do not add push, amend, reset, or force operations to this plan.

## Product and safety decisions

These decisions are part of the plan, not optional implementation details:

1. A group may contain complete files and/or hunk references. A path may occur
   in several groups only through distinct hunk references. The same hunk may
   occur at most once.
2. The AI response for the hunk-aware flow uses:

   ```json
   [
     {
       "files": ["Sources/NewFile.swift"],
       "hunks": ["Sources/Existing.swift#hunk-1"],
       "message": "feat: add new behavior"
     }
   ]
   ```

   `hunks` is optional for compatibility with providers that return only
   whole-file groups. A repeated file without hunk references is invalid for
   splitting and must fall back to one whole-file group, never be silently
   assigned to an arbitrary group.
3. The first version splits only ordinary text hunks from tracked modified
   files. Untracked, binary, deleted, renamed, or unparseable changes remain
   whole-file items. Do not invent a binary or rename patch format.
4. Hunk-aware execution requires a clean index at the start of the operation
   (`git diff --cached --quiet`). If staged content exists, fail before any
   mutation with an actionable error asking the user to unstage it. This keeps
   the first version from destroying or incorrectly reconstructing an
   arbitrary staged/unstaged split. Existing file-level CLI behavior is not
   changed.
5. The snapshot used for AI generation and review must be revalidated before
   the first mutation. If `HEAD`, file status, or diff content changed, abort
   without creating a commit and ask the user to regenerate the groups.
6. Use a temporary index (`GIT_INDEX_FILE`) while preparing and committing
   hunk groups. Patch files may be written only below the system temporary
   directory and must be removed with `defer`. Never persist source diffs,
   prompts, snapshots, or temporary paths in the repository.
7. If the AI response has unknown, duplicate, overlapping, or malformed hunk
   references, use the existing safe per-file fallback for that generation.
   Runtime validation must remain in `AtomicCommitPlan`; UI validation is not
   the only safety boundary.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Drift | `git diff --stat d362977..HEAD -- GitMenuBar GitMenuBarTests` | Empty output, or all listed changes are explicitly reconciled before editing |
| Focused tests | `make test` | XCTest suite passes, including hunk parser/grouping/atomic tests |
| Changed-source gate | `make agent-check` | Changed Swift lint and Debug build pass |
| UI preview gate | `make check-preview` | Changed UI candidates have preview coverage; record the known clean-tree empty-array baseline if it applies |
| Full pre-merge gate | `make lint && make test` | Both commands pass |
| Guidance | `make guidance-check` | Plan and repository guidance validation passes |
| Diff hygiene | `git diff --check` | No whitespace errors |

## Scope

**In scope — these are the only source/test files to modify:**

- `GitMenuBar/Models/GitModels.swift` — hunk/snapshot/group/plan domain types and validation.
- `GitMenuBar/Services/Git/GitDiffHunkParser.swift` — new pure parser for ordinary unified-diff hunks and patch fragments.
- `GitMenuBar/Services/Git/GitAtomicCommitService.swift` — snapshot construction and temporary-index hunk execution.
- `GitMenuBar/Services/Git/GitManager.swift` — narrow facade methods for snapshot generation and hunk-plan execution.
- `GitMenuBar/Services/AI/AICommitGrouperService.swift` — hunk-aware response decoding and safe fallback.
- `GitMenuBar/Services/AI/AICommitGrouperService+Prompt.swift` — hunk IDs and response contract.
- `GitMenuBar/Services/AI/AICommitCoordinator.swift` — expose the hunk-aware generation call while preserving existing file-level callers.
- `GitMenuBar/Services/AI/GitMenuBarCommitSession.swift` — only if needed to keep the existing coordinator/session boundary explicit; do not alter credential or message-policy behavior.
- `GitMenuBar/Components/AI/AtomicCommitReviewSheet.swift` — render, move, remove, and validate hunks; retain/update the preview.
- `GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift` — pass snapshot and hunk-aware plan through the reviewed flow.
- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift` — use the hunk-aware snapshot in automatic split commits.
- `GitMenuBar/App/MainMenuActionCoordinator.swift` — carry the validated hunk plan through automatic commit-and-push without changing push behavior.
- `GitMenuBarTests/GitDiffHunkParserTests.swift` — new parser unit tests.
- `GitMenuBarTests/AICommitGrouperServiceTests.swift` — hunk response and fallback tests.
- `GitMenuBarTests/GitManagerAtomicCommitTests.swift` — repository integration tests for hunk commits and safety failures.
- `GitMenuBarTests/GitModelsTests.swift` — create only if no existing model-test file can naturally contain the plan-validation cases.

**Out of scope — do not touch:**

- `GitMenuBar/Services/CLI/*` and the Companion CLI JSON schema; CLI remains
  file-level in this plan.
- Push, pull, amend, rebase, branch, reset-to-history, or force operations.
- Keychain, provider credentials, message policy, persistence, or AI quota
  behavior.
- Binary, rename, submodule, or arbitrary staged/unstaged hunk splitting.
- A custom diff viewer, drag-and-drop grouping, new external dependency, or a
  second Git command runner.
- Unrelated UI redesign, localization overhaul, or new command-palette
  commands.

## Suggested executor toolkit

Use the narrowest relevant skills if available:

- `swift-conventions` for Swift structure and lint/formatter expectations.
- `swiftui-expert-skill` and `swiftui-accessibility-audit` for the review sheet's hunk rows and state validation.
- `test-strategy` for parser, async, and repository-integration coverage.
- `delivery-workflow` for validation gates and final Git handoff.

## Steps

### Step 1: Add a pure hunk/snapshot domain and parser

Add the minimum model needed to distinguish a complete-file selection from a
hunk selection. Keep `AtomicCommitGroup.files` for existing file-level callers
and add an ordered collection of stable hunk IDs. Add metadata for display
(path, hunk ordinal/header, additions, removals) and an internal snapshot
mapping from hunk ID to the exact patch fragment needed by `git apply --cached`.

Implement `GitDiffHunkParser.swift` as a pure parser for ordinary unified
diffs. It must:

- preserve the file header required for `git apply --cached`;
- create deterministic IDs such as `<path>#hunk-1`, ordered as they appear;
- parse hunk headers and addition/removal counts;
- mark binary or unsupported records as whole-file-only instead of fabricating
  hunks;
- reject malformed hunk boundaries rather than returning a partial patch.

Build the snapshot from a canonical, sorted representation of the current
`HEAD`, status, and diff bytes. Use a stable digest (CryptoKit's SHA-256 is
acceptable if already available to the target; do not add a package) so a
reviewed plan can be checked again immediately before execution. Include
untracked/unsupported paths as whole-file entries, but do not generate hunk
patches for them.

Extend `AtomicCommitPlan` validation so it accepts repeated paths only when
their hunk IDs are distinct, rejects duplicate hunk IDs, rejects an entire
file selection mixed with one of that file's hunk selections, rejects unknown
hunks, and preserves existing empty-group/message/unknown-file errors.

**Verify**: `make test` → parser and plan-model tests pass; no source file
outside the in-scope list is modified.

### Step 2: Make AI grouping hunk-aware with a safe fallback

Update the hunk-aware prompt to enumerate each splittable hunk with its stable
ID and ask for `files`, optional `hunks`, and `message`. State that the same
hunk ID must appear in at most one group and that a file may be repeated only
when different hunk IDs explain the split.

Add hunk-shaped decoding with an empty default for missing `hunks`. Validate
the decoded response against the snapshot before returning it. If the JSON is
invalid, a hunk ID is unknown/duplicated, a complete file overlaps a hunk, or
the AI repeats a file without hunk IDs, return the safe one-group-per-file
fallback for the snapshot. Preserve the existing `AIError.messagePolicyRejected`
behavior; a rejected commit message must not be silently converted into a
fallback.

Keep the existing file-level generation entry point for Companion CLI and
other callers. Add a separate hunk-aware entry point or an explicit mode so
the executor cannot accidentally change the CLI's file-only schema.

**Verify**: `make test` → `AICommitGrouperServiceTests` covers valid hunk JSON,
same-file different-hunk groups, repeated hunk rejection, repeated-file
fallback, unknown-hunk fallback, and message-policy rejection.

### Step 3: Update the review surface to operate on hunks

Change the reviewed main-window flow to load one immutable snapshot and keep
the snapshot plus editable groups together. The sheet must show complete-file
rows and hunk rows. A hunk row needs at least the path, hunk ordinal/header,
addition/removal counts, and actions to move to the previous/next group or
exclude it. Do not build a source-code editor or a custom diff renderer in
this slice.

When the user edits groups, validate the draft before closing the sheet. Keep
the Create button disabled or show an inline error for empty groups/messages,
unknown selections, complete-file/hunk overlap, or duplicate hunk IDs. If a
working-tree refresh changes the snapshot while the sheet is open, the
executor must reject the plan at execution time and leave the sheet's source
changes untouched.

Add accessible labels/help text to hunk movement and exclusion buttons. Update
the existing preview to include at least one group with two hunks from the
same file and one complete-file row. Do not add a new UI file without a
`#Preview`.

**Verify**: `make check-preview` → the changed sheet has preview coverage; run
the focused UI/model tests if present and record any known clean-tree preview
script baseline separately.

### Step 4: Execute hunk plans through a temporary Git index

Add the narrowest `GitManager` facade needed to prepare a snapshot and execute
a validated hunk plan. Extend the atomic service command helper to pass
`additionalEnvironment` through `GitExecution`.

Before mutation, verify:

- repository path and `HEAD` are available;
- `.git/index.lock` is absent;
- no staged changes exist for hunk mode;
- the current snapshot fingerprint equals the reviewed plan fingerprint.

For each group, use an absolute temporary `GIT_INDEX_FILE` under the system
temporary directory. Initialize it from the current `HEAD`; stage complete
files with `git add -- <path>` and stage each selected hunk by writing its
exact patch fragment to a temporary file and running `git apply --cached
--check` followed by `git apply --cached`. Commit with the existing
`git commit --no-gpg-sign -m <message>` behavior and reuse the temporary index
for the next group. Clean all temporary files in `defer` blocks.

Do not mutate the real index until the transaction has succeeded. On any
stage/apply/commit failure, roll back created commits to the original `HEAD`
using the existing rollback seam and leave the working-tree content intact.
On success, reconcile the real index so committed changes are no longer
staged, while omitted changes remain as working-tree changes. If this cannot
be done without altering an unrelated staged state, the preflight staged-index
guard must stop the operation instead of guessing.

Preserve progress callbacks and existing push orchestration. The hunk executor
must return a localized error that names the failed group/hunk and whether the
plan was stale, unsupported, or rejected by Git.

**Verify**: `make test` → repository integration tests prove two non-overlapping
hunks from one file create two commits, omitted hunks remain uncommitted, a
stale snapshot creates no commit, staged input fails before mutation, and a
later hook failure rolls back created commits without losing worktree content.

### Step 5: Wire reviewed and automatic split-commit paths

Use the snapshot-aware hunk generation in `MainMenuOverlays.swift` and the
automatic path in `MainMenuActions.swift`. Carry the validated plan through
`MainMenuActionCoordinator` rather than passing bare groups that no longer
contain enough context to apply hunk IDs safely.

Keep the existing one-group-per-file fallback for AI failure and unsupported
file kinds. Keep the existing success, remote-ahead, push-failure, haptic, and
refresh behavior unchanged. The reviewed flow must close only after the plan
has passed local validation; execution errors should use the existing alert
surface and must not silently retry or push partial work.

**Verify**: `make agent-check` → changed Swift lint and Debug build pass; run
focused atomic/grouper tests and `git diff --check`.

### Step 6: Run the full handoff gates

Run the commands below from the repository root and record their results in
the handoff. Do not modify unrelated baseline failures to make this plan
green.

**Verify**:

- `make agent-check` → pass.
- `make test` → pass, including the new hunk integration tests.
- `make check-preview` → pass for changed UI candidates, or document the
  known clean-tree empty-array baseline if no candidates are discovered.
- `make lint && make test` → pass before merge.
- `make guidance-check` → pass with Plan 064 indexed.
- `git diff --check` → no whitespace errors.
- `git status --short` → only the intended source/test files and plan/index
  files are changed.

## Test plan

Add or extend tests using the existing XCTest and temporary-repository
patterns:

- `GitMenuBarTests/GitDiffHunkParserTests.swift`
  - two independent hunks in one tracked text file produce stable ordered IDs;
  - addition/deletion counts and hunk headers are correct;
  - paths containing spaces remain intact;
  - malformed, binary, and unsupported records become whole-file-only or fail
    closed without a partial hunk.
- `GitMenuBarTests/AICommitGrouperServiceTests.swift`
  - valid JSON assigns different hunk IDs from one path to different groups;
  - duplicate hunk IDs, unknown hunk IDs, and repeated whole-file paths use
    the per-file fallback;
  - missing `hunks` preserves file-only decoding;
  - message policy rejection remains a hard error.
- `GitMenuBarTests/GitManagerAtomicCommitTests.swift`
  - two non-overlapping hunks in the same file produce two commits with the
    expected messages and contents;
  - an omitted hunk remains in the working tree;
  - staged input is rejected before `HEAD` changes;
  - changing the file after review causes a fingerprint mismatch and no
    commit;
  - a second-commit hook failure rolls back the first commit and leaves the
    working tree content available;
  - existing whole-file atomic tests remain green.
- Model validation tests may live in `GitMenuBarTests/GitModelsTests.swift`
  only if that file already exists; otherwise keep them in the smallest
  existing atomic test file rather than creating a test target abstraction.

Use `GitManagerAtomicCommitTests.swift:58-181` as the integration-test pattern
and `AICommitGrouperServiceTests.swift:23-238` as the AI-stub pattern. Tests
must assert repository state (`HEAD`, commit messages, status, and file
content), not only returned Swift values.

## Done criteria

- [ ] A tracked text file with two independent hunks can be assigned to two
      atomic groups and produces two commits.
- [ ] A repeated file path without distinct hunk IDs cannot cancel the whole
      command; generation falls back to one whole-file group or presents a
      preflight error before Git mutation.
- [ ] Complete-file selections and hunk selections cannot overlap.
- [ ] Unknown, duplicate, stale, and unsupported selections fail closed before
      mutation.
- [ ] Existing staged changes are rejected by hunk mode before mutation with
      an actionable message.
- [ ] Failed later commits roll back created commits without discarding
      working-tree content.
- [ ] Companion CLI files and JSON schema are unchanged and its existing tests
      pass.
- [ ] `make agent-check` exits 0.
- [ ] `make test` exits 0.
- [ ] `make lint && make test` exits 0 before merge.
- [ ] `make check-preview` covers the changed review sheet.
- [ ] `make guidance-check` exits 0 and Plan 064 has a status row.
- [ ] `git diff --check` exits 0.
- [ ] No files outside the scope are modified, apart from
      `plans/README.md` and this plan file.

## STOP conditions

Stop and report instead of improvising if:

- The current `AtomicCommitGroup`, `AtomicCommitPlan`, review sheet, or Git
  service no longer matches the excerpts above.
- Supporting hunks requires changing the Companion CLI contract or any file
  under `GitMenuBar/Services/CLI/`; split that into a separate plan.
- Git cannot safely apply a selected patch against the temporary index without
  modifying the working tree.
- Preserving/reconciling the real index would alter unrelated staged content;
  keep the staged-input preflight failure rather than weakening it.
- A hunk parser would need to support binary, rename, submodule, or merge
  diffs to satisfy a test; report the case and keep it out of this MVP.
- A stale snapshot can still create a commit after the fingerprint check.
- Any failure path loses working-tree content or leaves a temporary index/patch
  file behind.
- The implementation needs a new dependency, persistence, credential access,
  push/force behavior, or a broad `GitManager` refactor.
- Any required verification command fails twice after a focused fix attempt.
- The change requires modifying files outside Scope.

## Maintenance notes

- The hunk ID format is an internal plan identity, not a permanent Git object
  ID. If diff generation changes its context or normalization, update the
  fingerprint and parser tests together.
- Any future support for pre-existing staged hunks should be a separate plan
  with explicit index-state tests; do not remove the current guard casually.
- If Companion CLI needs hunk splitting, create a separate plan for its versioned
  JSON schema, stale-plan behavior, and non-interactive review contract.
- Reviewers should scrutinize temporary-index cleanup, patch application
  ordering, rollback behavior, stale-plan rejection, and whether omitted
  hunks remain recoverable in the working tree.
- Keep the existing file-level API until all callers are migrated; it is the
  compatibility boundary for the Companion CLI and single-file commit paths.
