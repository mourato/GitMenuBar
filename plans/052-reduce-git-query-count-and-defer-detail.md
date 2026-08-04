# Plan 052: Reduce selected-project Git process count and defer noncritical detail

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat b2beedd..HEAD -- GitMenuBar/Services/Git/GitManager.swift GitMenuBar/Services/Git/WorkingTreeParser.swift GitMenuBar/Services/Git/GitBranchService+State.swift GitMenuBar/Services/Git/GitBranchService+Queries.swift GitMenuBar/Pages/MainMenu/MainMenuActions.swift GitMenuBar/Pages/MainMenu/MainMenuCommandPaletteActions.swift GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift GitMenuBar/Components/Branches/BranchManagementSheet.swift GitMenuBarTests/GitWorkingTreeStateTests.swift GitMenuBarTests/WorkingTreeParserTests.swift GitMenuBarTests/GitManagerBranchOperationsTests.swift`
> If any in-scope source file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: Plan 051
- **Category**: perf
- **Planned at**: commit `b2beedd`, 2026-08-04

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `High/Full`
- **Parallelizable**: no — refresh phases, Git output parsing, deferred UI
  entrypoints, and existing state tests must remain behaviorally aligned
- **Reviewer required**: yes — command replacement can silently change Git
  status semantics, especially for staged, untracked, detached, and tracking
  states
- **Rationale**: This plan removes duplicated or low-value processes from the
  selected-project critical path using Git's existing porcelain output and
  existing on-demand screens. It preserves the public GitManager facade and
  avoids a cache or new dependency.
- **Escalate when**: porcelain v2 cannot preserve an existing displayed state,
  a remote fetch is needed for automatic refresh, a new parser framework is
  proposed, or a deferred detail breaks a command/action that needs it
  synchronously.

## Why this matters

The selected refresh currently performs a serial chain of local reads plus
branch-detail work, an optional GitHub lookup, and `git fetch`. Several values
are queried more than once: commit-ahead count duplicates branch state, branch
details are immediately reloaded when the Branch Management sheet appears,
and each untracked file can launch its own `git diff --no-index` process. The
critical path should produce the selected repository's compact local state
quickly; branch management and network freshness can remain explicit and
on-demand under ADR 0004.

## Current state

- `GitMenuBar/Services/Git/GitManager.swift:129-140` currently awaits:

  ```swift
  updateLocalCommitCountAsync()
  updateUncommittedFilesAsync()
  updateBranchInfoAsync()
  updateRemoteUrlAsync()
  fetchCommitHistoryAsync(includeReflog: includeReflogHistory)
  fetchBranchesAsync()
  resolveBranchInfoAsync()
  getDefaultBranchNameAsync()
  checkRemoteStatusAsync()
  checkRepoVisibilityAsync()
  ```

- `GitManager.swift:520-551` runs `rev-list --count @{u}..HEAD` for
  `commitCount`; `GitBranchService+State.swift:91-147` runs a similar ahead
  query while updating branch state. The footer only needs the ahead count,
  so this is duplicate work.
- `GitManager.swift:563-633` runs status, staged numstat, unstaged numstat,
  and then delegates every untracked path to
  `WorkingTreeParser.lineDiffForUntrackedFiles`.
- `GitMenuBar/Services/Git/WorkingTreeParser.swift` currently uses
  `git diff --no-index` once per untracked path and has a file-reading fallback
  for the same line-count case. The fallback is the existing no-process seam.
- `GitMenuBar/Services/Git/GitBranchService+Queries.swift:84-190` resolves
  branch info with one tracking/ref/count query per local branch and one log
  query per local/remote-only branch. The file itself documents this N+1
  behavior at lines 143-145.
- `GitMenuBar/Components/Branches/BranchManagementSheet.swift:274-295`
  already loads branch details and worktree data when the sheet opens, so
  branch detail does not need to block the main project switch.
- `GitMenuBar/Services/Git/GitBranchService+State.swift:235-267` performs
  `git fetch` inside `checkRemoteStatusAsync`. ADR 0004 explicitly keeps
  network fetch across monitored projects user-triggered; automatic selected
  refresh must not turn into background network activity.
- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift:90-113` opens the branch
  selector without ensuring its branch list is loaded; the current refresh
  happens to preload it. If preload is deferred, the selector must request it
  at the point of use.
- `GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift:146-151` and
  `MainMenuCommandPaletteActions.swift:79-82` read the cached default branch
  synchronously when presenting merge-to-default actions. These callers need a
  safe on-demand resolution path if default-branch detection leaves the main
  refresh.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Query inventory | `rg -n 'gitManager\.refreshAsync|updateLocalCommitCount|lineDiffForUntrackedFiles|resolveTrackingStatus|lastCommitDate|checkRemoteStatusAsync|checkRepoVisibilityAsync' GitMenuBar/Services/Git GitMenuBar/Pages/MainMenu GitMenuBar/Components/Branches` | all critical-path and on-demand call sites are identified before edits |
| Porcelain fixture inspection | `/usr/bin/git status --porcelain=v2 --branch --untracked-files=all -z | od -An -tx1 -c | sed -n '1,30p'` | output boundaries and NUL handling are understood; no path is parsed by newline splitting |
| Working-tree tests | `make test` | existing staged/unstaged/untracked tests pass |
| Preview coverage | `make check-preview` | exit 0 |
| Scoped validation | `make agent-check` | changed Swift lint passes and the Debug build succeeds |
| Guidance validation | `make guidance-check` | exit 0 |
| Merge gate | `make lint && make test` | both commands exit 0 |

## Suggested executor toolkit

- Use `swift-concurrency` from Plan 051's session contract; all parallel local
  reads must still publish through that gate.
- Use `global:swift-conventions` for parser and Swift API changes.
- Use `test-strategy` for temporary Git repositories and fixture coverage.
- Use `global:macos-app-engineering` only for the branch-selector/merge action
  timing change; do not redesign those views.

## Scope

**In scope** (the only source files to modify):

- `GitMenuBar/Services/Git/GitManager.swift`
- `GitMenuBar/Services/Git/WorkingTreeParser.swift`
- `GitMenuBar/Services/Git/GitBranchService+State.swift`
- `GitMenuBar/Services/Git/GitBranchService+Queries.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuCommandPaletteActions.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift`
- `GitMenuBar/Components/Branches/BranchManagementSheet.swift`
- `GitMenuBarTests/GitWorkingTreeStateTests.swift`
- `GitMenuBarTests/WorkingTreeParserTests.swift`
- `GitMenuBarTests/GitManagerBranchOperationsTests.swift`
- `GitMenuBarTests/GitManagerRefreshTests.swift`
- `GitMenuBarTests/BranchStatusParserTests.swift` (create if a pure parser
  seam is needed)

Plan metadata files:

- `plans/052-reduce-git-query-count-and-defer-detail.md`
- `plans/README.md`

**Out of scope** (do not touch):

- `GitMenuBar/Services/Git/ProjectMonitorStore.swift` and
  `GitMenuBar/Models/ProjectStatusModels.swift` — Plan 053 owns monitored
  project snapshots.
- `GitMenuBar/Services/Git/GitRepositoryContext.swift` and refresh-session
  identity — Plan 051 owns that contract.
- Automatic `git fetch`, background GitHub API calls, new caches, a Git daemon,
  SQLite/index persistence, or a new dependency.
- Merging Staged and Unstaged UI sections, changing status labels, changing
  branch/worktree action semantics, or removing the Branch Management sheet.

## Git workflow

- Branch: `advisor/052-reduce-git-query-count-and-defer-detail` (or the
  repository's current branch convention if the operator already supplied an
  isolated implementation branch).
- Keep the implementation to one logical commit if committing is requested;
  use the repository's Conventional Commit style, e.g.
  `perf(git): reduce selected refresh process count`.
- Do not push or open a PR unless the operator explicitly instructs it.

## Steps

### Step 1: Replace untracked-file Git subprocesses with the existing file seam

In `WorkingTreeParser.lineDiffForUntrackedFiles`, preserve the method's
output type, path keys, binary/empty-file behavior, and line-diff semantics.
For an untracked regular file, use the existing direct file-reading fallback
instead of launching `git diff --no-index` once per path. Keep a conservative
fallback for unreadable files and preserve the neutral line count used today
when content cannot be read. Do not read outside the repository path supplied
to the method.

The selected working-tree flow must continue to run status plus staged and
unstaged numstat so partially staged files still appear in both sections.

**Verify**:

- `rg -n 'diff.*no-index|lineDiffForUntrackedFiles' GitMenuBar/Services/Git/WorkingTreeParser.swift GitMenuBar/Services/Git/GitManager.swift` → the untracked-path loop no longer invokes a Git subprocess per file, while the method remains used by the working-tree refresh.
- Existing `WorkingTreeParserTests` and `GitWorkingTreeStateTests` pass,
  including nested untracked files, added-line counts, binary files, and
  partially staged files.

### Step 2: Consolidate branch/ahead state and bound the critical path

Use one selected refresh session from Plan 051 and split its work into:

- a fast local phase for working-tree state, current branch/hash/ahead state,
  remote URL, and the visible commit history;
- optional independent local reads that can run concurrently only when they
  are read-only and remain bounded by the existing task/session gate;
- explicit/on-demand detail for branch metadata, default-branch detection,
  and worktree analysis.

Remove the separate `updateLocalCommitCountAsync` process from the main
refresh. Extend the branch-state result with the numeric ahead count (or the
smallest equivalent existing value) so `commitCount` is populated from the
same tracking query that already determines `isAheadOfRemote`. Preserve the
fallback behavior for repositories without an upstream, including the current
`origin/main`/`origin/master` fallback semantics until a fixture proves a
safer existing replacement.

Do not run `git fetch` in this phase. `checkRemoteStatusAsync` remains an
explicit action used by sync/remote refresh paths, and visibility validation
remains separate from local selected refresh.

**Verify**:

- `sed -n '125,145p' GitMenuBar/Services/Git/GitManager.swift` → the ordinary selected refresh no longer awaits commit-count, remote-status, visibility, or full branch-detail work; their explicit/on-demand callers remain elsewhere.
- `rg -n 'commitCount|isAheadOfRemote|behindCount' GitMenuBar/Services/Git/GitManager.swift GitMenuBar/Services/Git/GitBranchService+State.swift` → numeric ahead state has one source of truth.
- Existing branch-operation tests pass.

### Step 3: Batch branch-detail queries without changing BranchInfo semantics

Replace the per-branch `rev-parse`/`show-ref`/`rev-list`/`log` loop in
`GitBranchService+Queries.swift` with the smallest Git-native batch query that
provides the existing `BranchInfo` fields. Prefer `for-each-ref` with explicit
NUL-delimited fields for local and `origin` refs, including upstream/tracking
metadata and commit timestamps. Parse the output in a pure helper that can be
fixture-tested. Preserve:

- local versus remote-only rows;
- current-branch detection;
- `.noRemote`, `.upToDate`, `.ahead`, `.behind`, `.diverged`, and `.unknown`;
- commit dates when available;
- filtering of symbolic `origin/HEAD` entries;
- behavior for no remote and detached HEAD.

Do not parallelize one subprocess per branch. Do not generalize this into a
new Git query framework. If the installed Git version cannot expose one of the
current fields with a stable format, keep only that field's existing query and
report the measured ceiling.

**Verify**:

- `rg -n 'for localName in|resolveTrackingStatus|lastCommitDate' GitMenuBar/Services/Git/GitBranchService+Queries.swift` → no unbounded per-branch query loop remains on the normal detail path, or the explicitly documented unavoidable fallback is limited to one field.
- Add fixture tests for no upstream, up-to-date, ahead, behind, diverged,
  remote-only, and malformed/unknown tracking output.
- `make test` → all branch management tests pass.

### Step 4: Load branch/default details at the point of use

Preserve `BranchManagementSheet.reloadData()` as the owner of full branch and
worktree detail loading. Remove its dependency on main-window preloading.
When the branch selector is opened from `toggleBranchSelectorPresentation`
or `presentBranchSelector`, request the lightweight available-branch list if
it is empty/stale. Keep the existing overlay and row behavior.

For merge-to-default actions, resolve the default branch on demand before
presenting a confirmation that depends on it. The command palette may keep
its cheap cached/default fallback for listing, but must resolve the real value
before executing or presenting a destructive/branch-changing workflow. Do not
block the main actor while Git runs.

**Verify**:

- `rg -n 'fetchBranches|resolveBranchInfo|getDefaultBranchName' GitMenuBar/Pages/MainMenu GitMenuBar/Components/Branches GitMenuBar/Services/Git/GitManager.swift` → each call is either explicit/on-demand; no ordinary selected refresh call remains.
- Manual Debug check: project switch paints before opening Branch Management;
  opening the branch selector still shows branches; merge-to-default uses the
  detected default branch; branch/worktree cleanup still loads its snapshot.
- `make check-preview` → exit 0.

### Step 5: Measure the process reduction and run the gates

Use the existing `WindowOpenTrace` messages and Instruments/System Trace (or a
local Debug run with a large repository) to compare one project switch before
and after this plan. Count Git Process launches for:

- a clean repository;
- a repository with staged, unstaged, and several untracked files;
- a repository with multiple local branches.

Do not persist repository paths, command output, credentials, or machine
telemetry in the repository. The acceptance target is a materially smaller
critical-path process count with unchanged visible status; record numbers in
the review/PR, not in source.

Run `make guidance-check`, then `make lint && make test`. Request reviewer
sign-off for status parsing and branch semantics.

**Verify**: all commands exit 0; the review notes the observed before/after
process count and confirms that no automatic network fetch was introduced.

## Test plan

- Preserve and extend `WorkingTreeParserTests` for untracked files, empty and
  binary files, unreadable fallback, and nested paths.
- Preserve `GitWorkingTreeStateTests` for staged/unstaged separation and
  partially staged files.
- Add pure branch-output fixtures for all existing `BranchTrackingStatus`
  cases and branch dates/remote-only rows.
- Keep branch-management integration tests green for branch switching,
  cleanup, and worktree snapshot loading.
- Run `make check-preview`, `make agent-check`, and `make lint && make test`.

## Done criteria

- [ ] Untracked-file line counts no longer launch one Git Process per file.
- [ ] `commitCount` and ahead state share one selected refresh query/result.
- [ ] Ordinary selected refresh does not fetch, call GitHub, or resolve full
      branch details.
- [ ] Branch selector, merge-to-default, and Branch Management still load the
      data they need at the point of use.
- [ ] BranchInfo semantics and working-tree staged/unstaged semantics are
      unchanged and covered by tests.
- [ ] Branch detail no longer performs an unbounded query per branch, or the
      remaining fallback is explicitly measured and bounded.
- [ ] Before/after process-count evidence is recorded outside the repository.
- [ ] Reviewer has inspected Git output parsing and network policy.
- [ ] `make check-preview`, `make agent-check`, `make guidance-check`,
      `make lint`, and `make test` exit 0.
- [ ] No files outside the in-scope list are modified.
- [ ] `plans/README.md` status row for Plan 052 is updated only after done.

## STOP conditions

Stop and report instead of improvising if:

- Porcelain v2 or `for-each-ref` parsing loses a staged, unstaged, untracked,
  rename, detached, upstream, or diverged state.
- The only way to preserve a field is to reintroduce the same unbounded query
  loop or to add a new parser framework/dependency.
- A local read is accidentally run in parallel with `fetch`, push, pull, or
  another Git mutation against the same repository.
- Deferring a field breaks a visible action and no nonblocking on-demand seam
  exists in the current UI.
- A test requires changing public Git models or silently changing labels,
  counts, or remote-fetch behavior.
- Process count does not improve on a representative repository; record the
  result and stop before adding speculative caching.
- `make agent-check`, `make check-preview`, or the final lint/test gate fails
  twice after a reasonable scoped correction.

## Maintenance notes

- Keep Git output parsing pure and fixture-tested; do not parse NUL-delimited
  status/branch output with newline splitting.
- The selected local refresh is allowed to read concurrently only after Plan
  051's session gate is in place. All results must be tagged with that session.
- Network freshness is explicit. A future background fetch needs a separate
  product decision because it can trigger authentication, latency, and remote
  side effects.
