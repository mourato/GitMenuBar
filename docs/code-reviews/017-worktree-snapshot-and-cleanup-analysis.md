# Code review: Plan 017

- **Reviewed scope**: worktree snapshot models, read-only Git queries, cleanup analyzer, facade state, and tests
- **Reviewer**: thermo-nuclear-code-quality-review with GitMenuBar review profile
- **Final verdict**: APPROVED after fixes

## Findings

### [MEDIUM] Do not run worktree analysis in every general refresh

- **Area**: performance and command scheduling
- **Location**: `GitMenuBar/Services/Git/GitManager.swift:refreshAsync`
- **Issue**: the initial implementation resolved all worktrees and ran a status command for each one during every normal repository refresh, even when the worktree visualizer was not open.
- **Impact**: repositories with several linked worktrees would pay additional filesystem and Git command latency on unrelated refreshes.
- **Resolution**: removed the implicit call from `refreshAsync`; callers explicitly load the snapshot through `resolveWorktreeSnapshotAsync()` when the visualizer needs it.

### [LOW] Keep remote cleanup eligibility explicit

- **Area**: safety contract
- **Location**: `GitMenuBar/Models/WorktreeCleanupModels.swift:GitBranchCleanupInfo`
- **Issue**: a remote-tracking branch with a merged status could otherwise appear eligible through the status enum alone, although this phase does not authorize remote deletion.
- **Impact**: a later UI or batch action could accidentally treat remote refs as local deletion candidates.
- **Resolution**: added `GitBranchCleanupInfo.isEligible`, which is true only for local references whose status is merged. Remote merge status remains visible as analysis data but is never locally eligible.

### [LOW] Cover unavailable remote merge data

- **Area**: regression coverage
- **Issue**: the analyzer had a conservative unknown path for unavailable remote default refs, but no test asserted it.
- **Resolution**: added `testUnavailableRemoteMergeStatusIsUnknown`, including the invariant that remote refs are not eligible.

## Safety review

- No fetch, push, checkout, stash, branch deletion, or worktree deletion is performed.
- Local branch eligibility requires reachability from the local default ref, exclusion of protected/current branches, and absence from all worktrees.
- Worktree eligibility requires a clean, unlocked, non-prunable, non-main, non-current, attached worktree whose local branch is merged.
- Query failures and unavailable remote state are represented as failures or unknown statuses; unknown is never eligible.
- Remote-tracking data is explicitly based on the last fetch and is not treated as permission to delete a remote branch.

## Validation

- `make agent-check`: passed. The touched `GitManager.swift` still reports 22 pre-existing line-length warnings; no serious violations were introduced.
- `make test`: passed.
- `git diff --check`: passed.

No unresolved Critical, Medium, or Low findings remain.
