# Plan 005: AI-powered atomic commit grouping

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `High/Full`
- **Parallelizable**: no; this plan is serial unless a named independent workstream is added during reclassification.
- **Reviewer required**: yes; the plan has high-risk architectural, operational, or integration impact.
- **Rationale**: Integra IA, commits atômicos e UI de aprovação; requer revisão estrutural e de segurança.
- **Escalate when**: Se tocar tokens, Keychain, persistência, concorrência ou publicação.

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 1a9e012..HEAD -- GitMenuBar/`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MED
- **Depends on**: none
- **Category**: direction
- **Planned at**: commit `1a9e012`, 2026-07-08

## Why this matters

The app already generates AI commit messages for the entire working tree at once.
But real-world commits should be atomic — one logical change per commit. When a
developer has changes across multiple files that touch different concerns
(e.g., a refactor + a bugfix + a style change), they should be grouped into
separate commits with their own messages. AI analysis of file-level diffs can
detect these logical groupings and propose atomic commits automatically.

## Current state

- `AICommitMessageService.swift` — generates a single commit message from the
  entire diff (via `AICommitCoordinator`)
- `AICommitCoordinator.swift` (referenced) — orchestrates message generation
  with scope override (`DiffScope.staged` or `.unstaged`)
- `AICommitMessageService+DiffParsing.swift` — parses diff output for AI context
- `AICommitMessageService+Prompt.swift` — prompt templates
- `AICommitMessageService+Sanitizing.swift` — output sanitization
- `GitManager.swift:844-875` — `diffStaged()`, `diffUnstaged()`, `diffAll()`
  return raw diff strings
- `GitManager.swift:569-638` — `stageFile()`, `stageAllChanges()`,
  `unstageAllChanges()`, `unstageFile()` — file-level staging operations
- `GitManager.swift:120-162` — `commitLocallyAsync()` commits currently staged
  content
- `MainMenuActionCoordinator.swift` — orchestrates commit flow
- `WorkingTreeParser.swift` — parses git status into per-file `WorkingTreeFile`
  entries with `LineDiffStats`

**Key insight**: The existing `GitManager.changedFiles` and `stagedFiles` arrays
already track per-file changes and their diff stats. The AI service can receive
per-file diffs to analyze groupings.

## What we're building

### Core flow

1. **Analyze phase**: Read the full diff of all modified files
2. **Group phase**: Send per-file diffs to AI with a prompt asking it to group
   files into logical atomic commits (the `Agrupamento inteligente (IA)` approach).
   The AI returns JSON with groups like:
   ```json
   [
     {"files": ["src/feature/api.swift", "src/feature/model.swift"], "message": "feat: add new API endpoint"},
     {"files": ["src/utils/helper.swift"], "message": "refactor: extract helper function"}
   ]
   ```
3. **Review phase**: Show groups to the user in a review sheet where they can:
   - See which files are in each group
   - Edit the commit message for each group
   - Move files between groups
   - Remove groups, add new files
   - Approve/cancel
4. **Execute phase**: For each group (in order):
   - Stage only the files in that group
   - Commit with the corresponding message
   - Proceed to next group
5. **Result**: Multiple atomic commits created, working tree clean

### New components

- `AtomicCommitGroup` model — files array + commit message
- `AtomicCommitReviewSheet` — SwiftUI view for reviewing/splitting groups
- `AICommitGrouperService` — new AI service that groups files by diff analysis
- GitManager methods for atomic staging/committing per group
- Integration into `MainMenuView` as a new "Create Atomic Commits" action

## Commands you will need

| Purpose   | Command                     | Expected on success |
|-----------|-----------------------------|---------------------|
| Build     | `make build`                | Build Succeeded     |
| Test      | `make test`                 | All tests pass      |
| Lint      | `make lint`                 | No violations       |

## Scope

**In scope**:
- `GitMenuBar/Models/GitModels.swift` — add `AtomicCommitGroup` model
- `GitMenuBar/Services/AI/AICommitGrouperService.swift` — **CREATE**
- `GitMenuBar/Services/AI/AICommitGrouperService+Prompt.swift` — **CREATE**
- `GitMenuBar/Services/Git/GitManager.swift` — add `stageFilesAsync(files:)`,
  `commitWithStagedFilesAsync(message:)` and `performAtomicCommits(groups:)`
- `GitMenuBar/Components/AI/AtomicCommitReviewSheet.swift` — **CREATE**
- `GitMenuBar/Pages/MainMenu/MainMenuView.swift` — add `showAtomicCommitSheet` state
- `GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift` — integrate atomic commit sheet
- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift` — add atomic commit action
- `GitMenuBar/Pages/MainMenu/MainMenuContent.swift` — add "Atomic Commits" button
- `GitMenuBar/Pages/MainMenu/MainMenuComputed.swift` — add computed properties
- `GitMenuBarTests/` — tests for grouper service

**Out of scope**:
- Branch management (plan 003)
- Merge to default (plan 004)
- Command palette expansion (plan 006)
- Existing commit composer or AI commit message flow

## Git workflow

- Branch: `advisor/005-ai-atomic-commits`
- Commit per step
- Do NOT push

## Steps

### Step 1: Add `AtomicCommitGroup` model

In `GitModels.swift`, add:

```swift
struct AtomicCommitGroup: Identifiable, Equatable, Hashable {
    let id: UUID
    var files: [String]
    var message: String

    init(id: UUID = UUID(), files: [String], message: String) {
        self.id = id
        self.files = files
        self.message = message
    }

    var fileCount: Int { files.count }
}
```

**Verify**: `make build` succeeds.

### Step 2: Create `AICommitGrouperService`

Create `GitMenuBar/Services/AI/AICommitGrouperService.swift`:

```swift
import Foundation

final class AICommitGrouperService {
    private let aiService: AICommitMessageService

    init(aiService: AICommitMessageService) {
        self.aiService = aiService
    }

    /// Analyze per-file diffs and group them into logical atomic commits.
    /// Returns groups with suggested messages, or error if AI fails.
    func generateAtomicGroups(
        changedFiles: [WorkingTreeFile],
        diffPerFile: [String: String],
        repositoryPath: String
    ) async throws -> [AtomicCommitGroup] {
        // 1. Build prompt with per-file diffs
        let prompt = buildGroupingPrompt(
            changedFiles: changedFiles,
            diffPerFile: diffPerFile
        )

        // 2. Call AI provider
        let response = try await aiService.generateRawResponse(prompt: prompt)

        // 3. Parse JSON response into groups
        return try parseGroupsFromResponse(response)
    }

    private func buildGroupingPrompt(
        changedFiles: [WorkingTreeFile],
        diffPerFile: [String: String]
    ) -> String {
        // See step 2b
    }

    private func parseGroupsFromResponse(_ response: String) throws -> [AtomicCommitGroup] {
        // Parse JSON array, return groups with fallback
    }
}
```

**Verify**: `make build` succeeds.

### Step 2b: Create prompt file

Create `GitMenuBar/Services/AI/AICommitGrouperService+Prompt.swift`:

The prompt should instruct the AI to:
- Analyze the diffs file by file
- Group files that logically belong together (same feature, same concern)
- Suggest a conventional commit message per group
- Return a JSON array
- Fallback: if AI fails or returns invalid JSON, group each file individually

Follow the pattern in `AICommitMessageService+Prompt.swift`.

**Verify**: `make build` succeeds.

### Step 3: Add per-file diff methods to `GitManager`

Add to `GitManager.swift`:

```swift
/// Returns a map of file path → diff string for all changed files
func diffForChangedFilesAsync() async -> [String: String] {
    let repositoryPath = storedRepoPath
    guard !repositoryPath.isEmpty else { return [:] }

    return await runOnBackground {
        var result: [String: String] = [:]
        let files = self.changedFiles.map(\.path)
        for file in files {
            let diffResult = self.executeGitCommand(
                in: repositoryPath,
                args: ["diff", "--", file]
            )
            if !diffResult.failure {
                result[file] = diffResult.output
            }
        }
        return result
    }
}

/// Stage specific files and commit with the given message
func commitAtomicGroupAsync(
    files: [String],
    message: String
) async -> Result<Void, Error> {
    // 1. Unstage all first to ensure clean slate
    _ = await runOnBackground {
        self.executeGitCommand(in: self.storedRepoPath, args: ["restore", "--staged", "--", "."])
    }

    // 2. Stage only the target files
    guard !files.isEmpty else {
        return .failure(NSError(domain: "GitManager", code: 30,
            userInfo: [NSLocalizedDescriptionKey: "No files to commit"]))
    }

    let stageArgs = ["add", "--"] + files
    let stageResult = await runOnBackground {
        self.executeGitCommand(in: self.storedRepoPath, args: stageArgs)
    }
    guard !stageResult.failure else {
        return .failure(NSError(domain: "GitManager", code: 31,
            userInfo: [NSLocalizedDescriptionKey: "Failed to stage files: \(stageResult.output)"]))
    }

    // 3. Commit
    let commitResult = await runOnBackground {
        self.executeGitCommand(in: self.storedRepoPath,
            args: ["commit", "--no-gpg-sign", "-m", message])
    }
    guard !commitResult.failure else {
        return .failure(NSError(domain: "GitManager", code: 32,
            userInfo: [NSLocalizedDescriptionKey: "Failed to commit: \(commitResult.output)"]))
    }

    return .success(())
}

/// Execute the full atomic commit sequence for a list of groups
func performAtomicCommitsAsync(
    groups: [AtomicCommitGroup]
) async -> Result<Void, Error> {
    for group in groups {
        let result = await commitAtomicGroupAsync(files: group.files, message: group.message)
        guard case .success = result else {
            // Restore working tree state if a group fails
            await refreshAsync()
            return result
        }
    }

    await refreshAsync()
    return .success(())
}
```

**Verify**: `make build` succeeds.

### Step 4: Create `AtomicCommitReviewSheet`

Create `GitMenuBar/Components/AI/AtomicCommitReviewSheet.swift`:

A SwiftUI sheet view with:
- Header: "Review Atomic Commits" with explanatory text
- List of `AtomicCommitGroup`, each expandable to show:
  - Editable commit message text field
  - List of files in the group with checkboxes for inclusion
  - Move file buttons (move to previous/next group)
- "Add Group" button at bottom
- Footer with:
  - "Cancel" button
  - "Create X Commits" primary button (disabled if empty groups)
- Loading state while AI is generating groups
- Error state if AI fails (with retry and fallback to one-commit-per-file)

Follow the UI conventions from `CommitMessageEditorSheet.swift`:
- `macPanelSurface()` styling
- `MacChromeMetrics` spacing
- `MacChromeTypography` fonts

Include `#Preview`.

**Verify**: `make build` succeeds.

### Step 5: Wire into `MainMenuView`

In `MainMenuView.swift`:
- Add `@State var showAtomicCommitSheet = false`
- Add `@StateObject var atomicCommitGrouperService = AICommitGrouperService(...)` or
  pass through environment
- Add `.sheet(isPresented: $showAtomicCommitSheet)` with the review sheet

In `MainMenuActions.swift`:
- Add `func startAtomicCommitFlow()` that:
  1. Collects changed files and their diffs
  2. Calls AICommitGrouperService to generate groups
  3. Presents the review sheet with generated groups
  4. On user approval, calls `performAtomicCommitsAsync`
  5. Refreshes state

In `MainMenuContent.swift`:
- Add an "Atomic Commits" button when there are staged/changed files
- Position it near the existing CommitComposer

In `MainMenuComputed.swift`:
- Add computed properties for atomic commit availability

**Verify**: Build succeeds; "Atomic Commits" button visible when there are changes.

### Step 6: Add tests

Create `GitMenuBarTests/AICommitGrouperServiceTests.swift`:
- Test that the grouping prompt is constructed correctly
- Test JSON response parsing (valid, invalid, empty)
- Test fallback to per-file grouping when AI fails
- Mock AI service and verify groups are created

Also add `GitMenuBarTests/GitManagerAtomicCommitTests.swift`:
- Test `commitAtomicGroupAsync` with known files
- Test `diffForChangedFilesAsync` returns expected map
- Mock `GitCommandRunner` and verify command sequence

**Verify**: `make test` passes.

## Test plan

- Unit tests for `AICommitGrouperService` prompt building and response parsing
- Unit tests for `GitManager` atomic commit methods
- Integration: review sheet preview renders with sample groups
- Edge case: single file change → one group
- Edge case: AI returns invalid JSON → falls back to per-file groups
- Edge case: commit fails mid-sequence → remaining groups are not committed,
  working tree is refreshed

## Done criteria

- [ ] `make build` exits 0
- [ ] `make test` exits 0; new tests exist and pass
- [ ] `make lint` exits 0
- [ ] "Create Atomic Commits" action available when there are uncommitted changes
- [ ] AI groups files into logical commits based on diff analysis
- [ ] User can review, edit messages, move files between groups
- [ ] Atomic commits are created sequentially, leaving clean working tree
- [ ] `plans/README.md` status row updated for this plan

## STOP conditions

Stop and report back if:
- The code at the locations in "Current state" doesn't match the excerpts
- `AICommitMessageService` doesn't expose a method suitable for raw prompt/response —
  you may need to add a `generateRawResponse(prompt:)` method to it
- AI response parsing is unreliable — prefer strict JSON parsing with meaningful error messages
- A step's verification fails twice after a reasonable fix attempt

## Maintenance notes

- The `AICommitGrouperService` follows the same provider/adapter pattern as
  `AICommitMessageService` — reuse `AIProviderAdapters` and `AIProviderStore`
- The review sheet will benefit from drag-and-drop file reordering in a future iteration
- Prompt engineering in `AICommitGrouperService+Prompt.swift` will need tuning
  based on real-world usage
- If the AI service times out on large diffs, consider streaming or chunking
  the file analysis
