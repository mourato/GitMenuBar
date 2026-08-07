# Plan 059: Unify branch/worktree cleanup units behind a path-scoped repository service

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If a
> STOP condition occurs, stop and report instead of improvising. When done,
> update the status row in `plans/README.md` unless a reviewer maintains it.
>
> **Drift check (run first)**: `git diff --stat cfd5abf..HEAD -- CONTEXT.md docs/ARCHITECTURE.md docs/adr/0005-global-safe-cleanup-boundary.md GitMenuBar/Models/WorktreeCleanupModels.swift GitMenuBar/Services/Git GitMenuBar/Components/Branches GitMenuBarTests`
> If any in-scope source file changed after `cfd5abf`, compare the current
> state below with the live code before editing. A mismatch is a STOP condition.

## Status

- **Priority**: P0
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: plans/019-safe-batch-cleanup.md and plans/020-worktree-integration-hardening.md (both DONE)
- **Category**: security
- **Planned at**: commit `cfd5abf`, 2026-08-07

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `High/Full`
- **Parallelizable**: `no` — the analyzer, cleanup ordering, selected-project facade, and detailed cleanup UI form one safety contract
- **Reviewer required**: `yes` — this changes destructive behavior and the definition of what is safe to remove
- **Rationale**: The smallest safe implementation reuses the existing parser, analyzer, non-force commands, and revalidation logic behind one immutable Cleanup Unit model; it still crosses Git graph state, worktree directories, concurrency, and UI selection.
- **Escalate when**: implementation requires force deletion, automatic fetch, persistent per-project `GitManager` instances, concurrent mutations, or a change to the selected-project Git workflow.

## Why this matters

The current cleanup UI treats a local branch and the linked worktree that owns it as unrelated selections. A branch checked out in a worktree is deliberately not eligible as a standalone branch, while the clean worktree may be eligible; users must remove the worktree, refresh, and repeat the action before the branch can be removed. A Cleanup Unit makes that relationship explicit and gives both the existing detail surface and the later global surface one ordering, validation, and partial-result contract.

## Current state

- `GitMenuBar/Services/Git/GitBranchService+Worktrees.swift:9-31` resolves one snapshot from `storedRepoPath`, publishes it on the selected `GitBranchService`, and has private query helpers tied to that service's repository context.
- `GitMenuBar/Services/Git/GitBranchService+Cleanup.swift:4-23` accepts `[GitCleanupTarget]`, reads `storedRepoPath`, runs one background batch, and refreshes through the selected service's `refreshHandler`.
- `GitMenuBar/Models/WorktreeCleanupModels.swift:3-104` represents local branches, worktrees, and remote branches as separate `GitCleanupTarget` cases. `GitBranchCleanupInfo.isEligible` is false for a branch checked out elsewhere; `GitWorktreeCleanupInfo.status.isEligible` can still be true for its clean linked worktree.
- `GitMenuBar/Services/Git/WorktreeCleanupAnalyzer.swift:28-83` builds separate branch and worktree decisions. Its input currently has no set of monitored checkout paths, so a globally monitored linked worktree cannot be protected by the analyzer.
- `GitMenuBar/Components/Branches/BranchManagementSheet.swift:33-43` independently maps selected IDs to local-branch and worktree targets. `BranchManagementModeContentViews.swift:227-392` renders separate selectable branch and worktree rows.
- `GitMenuBar/Services/Git/GitExecution.swift:13-47` is the repository's existing background execution and command-runner boundary. Preserve argument arrays and `GitCommandRunner`; do not build shell command strings.
- `GitManager` is the selected-repository facade. `docs/adr/0004-multi-project-monitoring-snapshots.md` explicitly keeps it single-project, and the new proposed `docs/adr/0005-global-safe-cleanup-boundary.md` records the path-scoped boundary for this feature.
- The safety contract in `docs/ARCHITECTURE.md` requires local graph-based merge checks, no force deletion, no automatic fetch, immediate per-item revalidation, serial mutation, and continuation after individual skips/failures.
- The project uses Swift 6.0 with targeted strict concurrency in `GitMenuBar.xcodeproj/project.pbxproj:473-549`. Keep immutable values across background boundaries and match the existing `@MainActor` plus `GitExecution.runOnBackground` pattern; do not add `@unchecked Sendable` or `nonisolated(unsafe)` without a concrete invariant.

## Domain contract

Use the terms already added to `CONTEXT.md`: Cleanup Candidate, Cleanup Unit, Cleanup Analysis, Safe Cleanup, and Shared Repository. In user-facing text prefer “safe to clean”; keep `isEligible` as an internal predicate only where existing code already uses it.

The following rules are non-negotiable:

1. A branch-only Cleanup Unit contains a local branch that is merged into the local default branch and is not protected, current, or checked out in any worktree.
2. A paired Cleanup Unit contains a local branch checked out in a clean, linked, attached, non-main, non-current, non-locked, non-prunable worktree whose branch is merged into the local default branch. Remove the worktree first, then delete the branch.
3. A worktree whose normalized path is explicitly monitored as a project is protected and cannot be included in Safe Cleanup. The detailed and global surfaces use the same rule.
4. Remote branches remain outside Cleanup Units and outside global cleanup. Existing explicit remote deletion remains unchanged.
5. Unknown, stale, dirty, unmerged, protected, current, detached, locked, prunable, missing, or changed state is never silently promoted to a candidate.
6. If paired worktree removal succeeds but branch deletion fails, report a partial result and leave the branch intact. Never attempt rollback by recreating a directory or branch.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Drift | `git diff --stat cfd5abf..HEAD -- <scope>` | Empty or understood drift only |
| Focused implementation loop | `make agent-check` | Changed Swift lint and Debug build pass |
| Tests | `make test` | `Tests passed` |
| UI preview coverage | `make check-preview` | Changed UI candidates have previews |
| Guidance | `make guidance-check` | `guidance-check: passed` |
| Merge gate | `make lint && make test` | Both commands pass |
| Whitespace | `git diff --check` | Exit 0 |

## Suggested executor toolkit

- Use `global:swift-conventions` plus `.agents/overlays/swift-conventions.md` for source layout and lint.
- Use `swift-concurrency` when moving the path-scoped query/mutation boundary across background execution; preserve immutable values and targeted strict-concurrency diagnostics.
- Use `global:swiftui-accessibility-audit` plus `.agents/overlays/swiftui-accessibility-audit.md` for cleanup selection, status, focus, and directory-removal warnings.
- Use `test-strategy` for temporary-repository integration tests; follow `GitMenuBarTests/GitWorktreeIntegrationTests.swift` and `TestSupport.swift`.

## Scope

**In scope** (the only implementation files for this plan):

- `GitMenuBar/Models/WorktreeCleanupModels.swift`
- `GitMenuBar/Services/Git/WorktreeCleanupAnalyzer.swift`
- `GitMenuBar/Services/Git/GitCleanupRepository.swift` (new)
- `GitMenuBar/Services/Git/GitBranchService.swift`
- `GitMenuBar/Services/Git/GitBranchService+Worktrees.swift`
- `GitMenuBar/Services/Git/GitBranchService+Cleanup.swift`
- `GitMenuBar/Services/Git/GitManager.swift`, only for the selected-facade overloads
- `GitMenuBar/Components/Branches/BranchManagementSheet.swift`
- `GitMenuBar/Components/Branches/BranchManagementModeContentViews.swift`
- `GitMenuBar/Components/Branches/BranchManagementModeContentViews+Cleanup.swift`
- `GitMenuBar/Components/Branches/BranchManagementSheet+Cleanup.swift`
- `GitMenuBar/Components/Branches/CleanupConfirmationView.swift`
- `GitMenuBar/Components/Branches/CleanupManagementContentPreview.swift`, if its initializer changes
- `GitMenuBarTests/WorktreeCleanupAnalyzerTests.swift`
- `GitMenuBarTests/GitManagerWorktreeCleanupTests.swift`
- `GitMenuBarTests/GitWorktreeIntegrationTests.swift`
- `GitMenuBarTests/GitCleanupRepositoryTests.swift` (new if a pure service seam is needed)
- `docs/ARCHITECTURE.md`
- `plans/059-unify-cleanup-units-path-scoped-service.md`
- `plans/README.md`

**Out of scope**:

- The global project list, global page, route, or multi-project store; Plan 060 owns those.
- Remote branch deletion, fetching, GitHub/PR state, or network behavior.
- Ordinary branch CRUD outside the cleanup mode.
- A persistent `GitManager` or `GitBranchService` per monitored project.
- Force deletion, stash, checkout, branch switching, directory deletion through `FileManager`, or implicit mutation of the selected worktree.
- New dependencies, a generic repository protocol with one production implementation, a cache, or a database.

## Steps

### Step 1: Add Cleanup Units and monitored-worktree protection

Extend the immutable cleanup model in `WorktreeCleanupModels.swift` with a `GitCleanupUnit` value type and a pure builder. The unit must retain the branch identity/hash and optional linked worktree identity/head hash needed for immediate revalidation. Give branch-only and paired units stable IDs scoped by normalized repository identity and branch/worktree path; the same branch name in two repositories must never collide.

Add a monitored-worktree status to `GitWorktreeCleanupStatus` (or an equally explicit existing status shape) and add normalized `protectedWorktreePaths` to `GitWorktreeAnalysisInput`, defaulting to an empty set for existing analyzer fixtures. Precedence must keep main/current/locked/prunable/dirty/unknown reasons visible; a non-current worktree whose path is protected by monitoring must be visibly blocked and never eligible.

Build units from one analyzed snapshot:

- merged local branch with no worktree → branch-only unit;
- merged local branch checked out in a matching eligible worktree → paired unit;
- all remote refs and all blocked/unknown items → no unit;
- a linked worktree cannot produce a unit unless its attached local branch is present, merged, clean, and otherwise eligible.

Expose branch and worktree candidate counts from the unit collection. A paired unit counts once as one branch and once as one worktree; it must not appear as two independent actions.

**Verify**: `make test` → analyzer tests pass for branch-only, paired, monitored-worktree, dirty, locked, detached, protected, current, unmerged, and unknown cases.

### Step 2: Extract path-scoped analysis and mutation without duplicating Git rules

Create `GitCleanupRepository.swift` as a small non-UI service around the existing `GitCommandRunner`, `WorktreeParser`, and `WorktreeCleanupAnalyzer`. Move or delegate the private query logic currently in `GitBranchService+Worktrees.swift` so the service accepts an explicit repository path and protected-worktree set. It must return an immutable Cleanup Analysis containing the repository path, Shared Repository identity, default branch ref, snapshot, and Cleanup Units.

Resolve Shared Repository identity with Git metadata rather than string heuristics. Use `git rev-parse --git-common-dir`, resolve a relative result against the supplied checkout, normalize it, and return an analysis failure if the identity cannot be resolved. Do not group or deduplicate by project display name.

Move the existing revalidation rules from `GitBranchService+Cleanup.swift` behind the same path-scoped service. Keep the existing non-force commands and explicit remote path. Add a unit mutation method that:

1. revalidates the complete unit against the immutable snapshot;
2. for a paired unit, revalidates and removes the linked worktree with `git worktree remove <path>` without `--force`;
3. revalidates the now-detached branch and removes it with `git branch --delete <name>`;
4. returns succeeded, skipped, failed, or partially-succeeded per unit;
5. processes units serially and continues after an individual outcome.

Do not make a global coordinator call the selected `GitManager`. Instead, keep `GitBranchService` and `GitManager` as thin selected-repository facades over the path-scoped service, preserving existing public callers and default arguments. The selected facade must pass the current monitored checkout paths when resolving cleanup analysis so the detailed surface gets the same protected-worktree rule.

**Verify**: `rg -n 'branch.*-D|worktree.*--force|FileManager\.default\.removeItem|fetch' GitMenuBar/Services/Git/GitCleanupRepository.swift GitMenuBar/Services/Git/GitBranchService+Cleanup.swift` → no safe-cleanup force, filesystem, or automatic-fetch path; `make agent-check` → lint and Debug build pass.

### Step 3: Make the selected-project Cleanup mode use units

Update `BranchManagementSheet` and its cleanup content so selection IDs represent `GitCleanupUnit.id`, not independent local-branch/worktree target IDs. Keep Branches mode, Worktrees mode, branch CRUD, Finder reveal, path copy, refresh, and explicit remote actions unchanged.

In Cleanup mode render one row per unit. A paired row must name both the local branch and linked worktree path and explain that both will be removed in order. Blocked/unknown rows remain visible for diagnosis but cannot be selected. Preserve the existing detail view for all worktrees so users can inspect why an item is not safe. Adapt `CleanupConfirmationView` to enumerate branch-only and paired units separately and retain the existing directory-removal acknowledgement.

Keep cleanup disabled while loading or running, clear selections after completion, refresh the selected repository once, and show every per-unit outcome including partial success. Do not add a second selection system or persist cleanup selection.

Every changed UI-rendering Swift file must retain or gain a `#Preview`; previews must cover branch-only, paired, monitored/protected, dirty, and unknown states.

**Verify**: `make check-preview` → changed UI candidates pass; `make agent-check` → lint and Debug build pass.

### Step 4: Prove ordering, revalidation, and observable state

Extend the existing temporary-repository tests. Add cases proving:

- one paired unit removes the linked directory first and then the local branch;
- an unmerged branch, dirty/locked/prunable/detached/current worktree, monitored worktree, or changed HEAD remains intact;
- a stale unit is skipped without preventing later units from completing;
- a worktree-removal success followed by branch-delete failure reports partial success and leaves the branch ref;
- two repositories with the same branch name produce distinct unit IDs and no cross-repository command path;
- no test uses the developer checkout, network, personal Git identity, or production force cleanup.

Use `TestSupport.swift` temporary directories and isolated Git configuration. Assert actual branch refs and directory existence, not only returned strings. Update `docs/ARCHITECTURE.md` to state that a branch checked out in an eligible linked worktree is cleaned through a paired Cleanup Unit, and that explicitly monitored worktree paths are protected.

**Verify**: `make test` → all tests pass; `git diff --check` → exit 0.

### Step 5: Close the plan surface

Run `make guidance-check`, `make lint && make test`, and `make check-preview`. Review the final diff for out-of-scope files and confirm that `GitManager` still owns only the selected repository. Update the Plan 059 status row only after all done criteria pass.

**Verify**: `make guidance-check`, `make lint && make test`, `make check-preview`, and `git status --short` → guidance, lint, tests, and previews pass; only scoped files plus the plan index are modified.

## Test plan

- Extend `WorktreeCleanupAnalyzerTests.swift` for monitored paths and unit construction.
- Extend `GitManagerWorktreeCleanupTests.swift` for paired ordering, partial success, stale revalidation, and no-force behavior.
- Extend `GitWorktreeIntegrationTests.swift` with observable branch-ref and directory assertions.
- Add `GitCleanupRepositoryTests.swift` only if a pure path-scoped service seam needs direct coverage; prefer existing integration fixtures over a broad mock framework.
- Match `TestSupport.swift` and `GitWorktreeIntegrationTests.swift`: temporary repositories, isolated config, `defer` teardown, and local Git commands only.

## Done criteria

- [ ] Branch-only and paired Cleanup Units are represented by immutable values with repository-scoped IDs.
- [ ] A paired unit removes its worktree before its branch and reports partial success if the second operation fails.
- [ ] Explicitly monitored worktree paths are blocked in both selected and global-ready analysis.
- [ ] No safe-cleanup path uses `git branch -D`, `git worktree remove --force`, `FileManager.removeItem`, automatic fetch, stash, or checkout.
- [ ] Selected-project Cleanup mode no longer presents branch/worktree pairs as independent actions.
- [ ] Immediate revalidation and serial continuation remain intact.
- [ ] Tests assert real refs/directories and pass.
- [ ] Every changed UI Swift file has preview coverage.
- [ ] `make agent-check`, `make check-preview`, `make guidance-check`, `make lint`, and `make test` pass.
- [ ] No files outside the scope are modified.

## STOP conditions

- The live analyzer cannot distinguish a monitored worktree path from an ordinary linked worktree without guessing.
- Git cannot resolve a stable shared-repository identity for a supported checkout; mark the analysis unavailable and report instead of grouping by path text.
- Removing a worktree requires `--force`, direct filesystem deletion, checkout, stash, or another implicit mutation.
- The branch/worktree sequence cannot preserve the branch after a successful directory removal and failed branch deletion.
- The implementation requires a persistent `GitManager` per monitored project, automatic fetch, remote deletion, or concurrent repository mutation.
- Existing selected-project branch CRUD behavior must be rewritten rather than adapted through the path-scoped service.
- A test would need a developer repository, network, secret, or non-isolated Git configuration.

## Maintenance notes

Review future cleanup changes against the Cleanup Unit ordering and no-force invariants. If remote cleanup is ever added to the global surface, it needs a separate explicit authorization and freshness contract; do not add it by reusing local units. Keep `GitManager` selected-project-only. If the Git version on supported systems lacks the required common-directory metadata, stop and revise the identity strategy before implementing grouping.
