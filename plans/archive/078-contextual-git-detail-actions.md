# Plan 078: Add contextual Git detail views and safe actions

> **Executor instructions**: Read this brief, Plans 076–077, ADR 0009, and
> the project Git action conventions before editing. This plan touches local
> Git state and external remotes. Follow the external-state addendum exactly.
> Stop on any scope or identity mismatch. Update only the Plan 078 bookkeeping
> row when complete; leave merge and push to the operator.
>
> **Drift check (run first)**: git diff --stat 2118aad..HEAD -- GitMenuBar/Models/GitModels.swift GitMenuBar/Services/Git/GitStashService.swift GitMenuBar/Services/Git/GitBranchService+Queries.swift GitMenuBar/Services/Git/GitBranchService+Mutations.swift GitMenuBar/Services/Git/GitManager.swift GitMenuBar/App/MainMenuActionCoordinator.swift GitMenuBar/App/StatusBarController.swift GitMenuBar/Pages/MainMenu/MainMenuInspectorView.swift GitMenuBar/Pages/MainMenu/MainMenuView.swift GitMenuBar/Pages/MainMenu/MainMenuContent.swift GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift GitMenuBarTests/GitStashServiceTests.swift GitMenuBarTests/GitManagerBranchOperationsTests.swift GitMenuBarTests/MainMenuActionCoordinatorTests.swift

## Status

- **Priority**: P0
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: [Plan 076](076-workbench-inspector-shell.md) and [Plan 077](077-project-state-overview.md)
- **Category**: correctness
- **Planned at**: commit 2118aad, 2026-09-03
- **Finding ID**: contextual-git-detail-actions
- **Publication**: local
- **Parent issue**: none
- **Issue**: none
- **Integration**: main; merge and push require explicit operator authorization

## Execution profile

- **Recommended profile**: implementer
- **Risk/lane**: High/Full
- **Parallelizable**: no — branch, stash, working-tree, push, refresh, and action-admission state share one selected repository and one operation owner
- **Reviewer required**: yes — this plan mutates the worktree/index/refs and remotes, adds a new stash command surface, and must be reviewed against ADR 0009
- **Rationale**: The UI is straightforward, but an action that outlives selection can write to the wrong repository, and stash indexes are unstable. The smallest safe implementation reuses GitManager/MainMenuActionCoordinator, adds only a concrete stash service, and tests A/B repository identity with deterministic gates.
- **Escalate when**: a new global queue, per-project GitManager, persisted action history, force-push behavior, automatic fetch, credential storage, or second Git command runner is proposed.

## Why this matters

The new overview makes repository state discoverable, but a count without a
useful next action still sends the user back to the old branch sheet or opaque
history route. The inspector should expand the selected topic into readable
branch, push, working-tree, and stash details, then offer one safe primary
action and a small set of existing secondary actions.

GitMenuBar has branch and file mutations already, but no retained stash model
or stash detail surface. Git itself does not record whether a retained stash
was previously applied, merged, or undone, so this plan reports retained stash
refs and offers Apply or Drop; it must not invent an “applied” state or add
process-local history.

## External-state addendum

- **Authority**: the actual local worktree, index, refs, stash refs, and
  configured remote are authoritative. Published UI counts are observations.
- **Identity**: capture RepositoryOperationContext before the first await. New
  stash operations must use the stable stash commit hash, never stash@{N} as
  the stored identity. Branch actions capture the normalized repository path
  and the current branch/ref at admission.
- **Scope**: an action may read or mutate only the captured repository and
  target. A later project selection must not retarget it. Do not pass a
  mutable selected path or SwiftUI state into a background closure.
- **Preflight**: before a mutation, verify that the captured repository still
  exists and that the expected current branch/ref is valid. For a non-current
  branch push, validate that the named local branch still exists and push that
  named ref explicitly.
- **Admission**: route new mutations through the existing
  MainMenuActionCoordinator operation owner. Reject a duplicate action while
  the same path is busy. If a legacy callback cannot become context-bound in
  this slice, it must keep repository switching blocked for its full lifetime;
  do not add a new unbound mutation while selection can change.
- **Git safety**: Apply, stage, unstage, switch, merge, and push are reversible
  or recoverable only to the extent Git provides. Drop, discard, delete, and
  reset require explicit native confirmation. Do not use stash pop for the new
  Apply action, do not auto-force-push after rejection, and do not add rollback
  or automatic retry.
- **Partial failure**: a failed Apply leaves the stash retained; a failed push
  may leave a local commit or changed remote state. Surface the Git error and
  never report success before the command returns success.
- **Refresh**: after success or failure, refresh the captured path through the
  existing path-scoped completion/monitor seam. Only publish selected
  GitManager state if the context is still current.
- **Concurrency**: same-repository Git mutation and refresh remain serialized.
  Do not allow a second branch/stash/file mutation to overlap the first.

## Current state

- GitMenuBar/Models/GitModels.swift:4-199 contains Commit, WorkingTreeFile,
  BranchTrackingStatus, and BranchInfo. There is no GitStashInfo.
- GitMenuBar/Services/Git/GitManager.swift:53-105 owns GitBranchService,
  GitAtomicCommitService, and GitCommitHistoryService and pipes their
  published state. Its public branch methods at :1733-1765 and mutation
  callbacks at :1980-1998 expose existing branch operations.
- GitMenuBar/Services/Git/GitBranchService+Queries.swift:95-165 resolves
  BranchInfo and :168-194 parses tracking status. It has no list of local
  branches not merged into the selected default branch.
- GitMenuBar/Services/Git/GitBranchService+Mutations.swift:9-27 pushes a
  branch through the service's mutable selected path. Existing branch
  management callbacks also capture selected state and call refreshHandler.
- GitMenuBar/App/MainMenuActionCoordinator.swift:492-546 already captures
  RepositoryOperationContext for primary operations and calls context-bound
  commit/push APIs. Its isBusy/canSwitchRepository properties are the shared
  admission boundary.
- GitMenuBar/App/StatusBarController.swift:80-85 injects a path-scoped
  ProjectMonitorStore.refresh callback for completed primary work. Extend
  that existing completion seam only if contextual actions need it; do not
  create notifications.
- GitMenuBar/Pages/MainMenu/MainMenuInspectorView.swift is the shell from Plan
  076, and Plan 077 supplies section selections and overview buttons. Keep
  detailed section bodies in this file unless a preview/compiler boundary
  makes one focused companion necessary; do not create one view per metric.
- Existing BranchManagementSheet.swift already owns full branch CRUD. The
  inspector should not duplicate create/rename/worktree management. It may
  show branch rows and a Manage Branches entry that opens the existing sheet.
- Existing WorkingTreeSectionView.swift and
  WorkingTreeDiffTreeViews.swift render working-tree files. Reuse their
  WorkingTreeFile and action patterns rather than building a second diff tree.
- ProjectStatusReader currently counts stashes with git stash list but returns
  no stash identity or message. Keep that compact count for the sidebar and
  add full stash loading only when the stashes inspector section is opened.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Drift | git diff --stat 2118aad..HEAD -- [the paths in the drift check] | Empty or explained Plan 076–078 changes only |
| Focused stash tests | make test-focused TEST_FILTER='GitMenuBarTests/GitStashServiceTests' | Parser and A/B repository stash cases pass |
| Branch regression tests | make test-focused TEST_FILTER='GitMenuBarTests/GitManagerBranchOperationsTests' | Existing and new branch health/context cases pass |
| Coordinator tests | make test-focused TEST_FILTER='GitMenuBarTests/MainMenuActionCoordinatorTests' | Admission and failure publication cases pass |
| Changed-surface check | make agent-check | Changed Swift lint and Debug build pass |
| Preview coverage | ./scripts/check-preview.sh GitMenuBar/Pages/MainMenu/MainMenuInspectorView.swift | Inspector preview coverage passes |
| Full merge gate | make lint && make test | Lint and all XCTest tests pass |
| Hygiene | git diff --check | No whitespace errors |

## Suggested executor toolkit

- Use security-credentials only if an existing authentication path is touched;
  do not inspect or print credential values.
- Use macos-app-engineering for owner/lifecycle decisions.
- Use swift-concurrency and swift-conventions for context-safe async APIs and
  Swift 6.4 Sendable boundaries.
- Use codebase-design vocabulary: keep GitManager as the facade, GitBranchService
  and the concrete GitStashService as deep modules with small value interfaces.
- Use swiftui-expert-skill, apple-design, swiftui-accessibility-audit, and
  ux-writing for the inspector controls and states.
- Use test-hygiene and the local test-strategy for A/B repositories,
  CheckedContinuation gates, and quiet tests.
- Use delivery-workflow before every build/test/lint/preview command.

## Scope

**In scope:**

- GitMenuBar/Models/GitModels.swift
- GitMenuBar/Services/Git/GitStashService.swift (create)
- GitMenuBar/Services/Git/GitBranchService+Queries.swift
- GitMenuBar/Services/Git/GitBranchService+Mutations.swift
- GitMenuBar/Services/Git/GitManager.swift
- GitMenuBar/App/MainMenuActionCoordinator.swift
- GitMenuBar/App/StatusBarController.swift
- GitMenuBar/Pages/MainMenu/MainMenuInspectorView.swift
- GitMenuBar/Pages/MainMenu/MainMenuView.swift
- GitMenuBar/Pages/MainMenu/MainMenuContent.swift
- GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift
- GitMenuBarTests/GitStashServiceTests.swift (create)
- GitMenuBarTests/GitManagerBranchOperationsTests.swift
- GitMenuBarTests/MainMenuActionCoordinatorTests.swift
- plans/README.md — only the Plan 078 bookkeeping row

**Out of scope:**

- new credentials, Keychain entries, remote-provider APIs, automatic fetch, or
  background polling
- a new generic command bus, Git runner protocol, cache, database, queue UI,
  or per-project GitManager
- full branch CRUD, worktree cleanup, or replacement of BranchManagementSheet
- moving the history list or removing MainMenuRoute.historyDetail (Plan 079)
- inferring whether a stash was previously applied/merged/undone
- force push, stash pop, silent discard, automatic conflict resolution, or
  rollback
- unrelated status/sidebar redesign

## Git workflow

- Use the assigned isolated worktree and branch from
  core/policies/worktrees.md.
- This plan is high risk. Keep implementation, review, remediation, merge,
  main validation, and push as separate states.
- Do not run destructive Git commands in the product repository as part of
  validation. Integration tests must use temporary A/B repositories and clean
  them through existing test helpers.
- Do not merge, push, amend, or clean up worktrees without authorization.

## Steps

### Step 1: Add stable stash data and a concrete service

Add GitStashInfo to GitModels.swift with a stable hash ID, display ref,
message/subject, branch text when available, and creation date. Add a concrete
GitStashService using the existing GitCommandRunner/GitExecution patterns.
Keep it as a concrete service with no one-implementation protocol.

Implement a pure parser for a NUL-delimited git stash list format containing
the stash commit hash, reflog selector, subject, and commit timestamp. Skip
malformed records and preserve an empty result for an empty list. Query with
git stash list only when the stash inspector is selected or after a stash
mutation; do not add the full list to every monitor refresh.

Add context-aware Apply and Drop operations. Apply must use the captured hash
and leave the stash retained. Drop must use the captured hash and be called
only after confirmation. Return Result values with trimmed, user-safe Git
errors; never log secrets or full auth command output.

Pipe the service's loaded stashes through GitManager only as selected-project
state. Clear it on repository reset and guard publication by the captured
repository context. Keep ProjectStatusReader.stashCount unchanged.

**Verify**: GitStashServiceTests pass parser cases for empty, valid, malformed,
multiple, reordered, and NUL-delimited input. A temporary repository test
proves Apply keeps the selected stash hash and Drop removes exactly that hash,
even after another stash changes the list order.

### Step 2: Add branch health detail without a second repository reader

Add a context/session-aware query to GitBranchService for local branches not
merged into the selected default branch. Reuse the existing default-branch
resolution and command runner. Return stable branch names and filter the
default/current branch according to the product wording; document the exact
definition as “not reachable from the selected local default branch,” not
“GitHub pull request not merged.”

Expose only the data the inspector needs through GitManager. Use existing
BranchInfo trackingStatus for unpushed/no-upstream rows. Do not add a second
branch model that copies every BranchInfo field.

Add parser/temporary-repository tests for merged, unmerged, default, current,
no-upstream, ahead, behind, diverged, and empty repositories. If the command
cannot distinguish “not merged into default” from a remote PR state, keep the
local definition and make the UI label explicit.

**Verify**: make test-focused TEST_FILTER='GitMenuBarTests/GitManagerBranchOperationsTests'
passes, and the query does not fetch or mutate remote state.

### Step 3: Put one safe action owner behind the inspector

Extend MainMenuActionCoordinator with the smallest contextual mutation helper
needed by the inspector. It must capture RepositoryOperationContext before
awaiting, set the existing busy/admission state, reject duplicate operations,
and publish success/failure only if the context is still current. Use the
existing path-scoped project monitor completion callback for a completed
non-selected repository.

Add explicit methods for the approved primary actions rather than a public
generic command bus:

- Push current or selected local branch commits using a non-force,
  context-safe GitManager path;
- Apply a selected stash by hash;
- Drop a selected stash after confirmation;
- Switch to a branch, merge a local unmerged branch, or delete a safe local
  branch using the existing branch service behavior and an explicit
  confirmation where needed;
- Stage/unstage/open/discard selected working-tree files by reusing existing
  GitManager actions and confirmation behavior.

For legacy callback mutations that cannot be made context-bound without
changing their transaction semantics, adapt them to an async completion and
keep canSwitchRepository false until they finish. Do not let a new callback
continue after the repository changes. For branch push, pass a named branch
ref to Git rather than using HEAD:target, and do not retry a rejection with
force push. Keep existing BranchManagementSheet actions behaviorally
compatible; the inspector is a compact entry point, not a replacement.

On completion, refresh the captured repository through the existing selected
or monitor path. Keep action errors in the existing MainMenuActionCoordinator
status/banner path unless a small inline inspector message is necessary for
the action's immediate result.

**Verify**: MainMenuActionCoordinatorTests prove a duplicate action is
rejected, project B cannot receive project A's result, a failed Apply retains
the stash, a failed push is not reported as success, and a branch mutation
does not start after a stale context. Use CheckedContinuation gates or existing
test seams; do not use sleeps.

### Step 4: Render detail views and actions in one inspector surface

Extend MainMenuInspectorView with section bodies:

- Working Tree: staged/unstaged groups, selected file metadata, Open,
  Stage/Unstage, and Discard with existing confirmation;
- Push and Sync: current branch ahead/behind details, commit subjects/hashes
  available locally, and Push as the single primary action;
- Branches: local branch list with tracking state, unmerged list, and
  Switch/Merge/Delete where valid; provide Manage Branches for full CRUD;
- Stashes: stable hash-backed rows with subject, branch/date, Apply primary
  action, and Drop as confirmed destructive action;
- section empty/loading/error states with accessible values and retry only
  through existing refresh behavior.

Keep one scroll owner in the inspector. Reuse existing WorkingTree and branch
row visuals where their interfaces fit. Use native Button controls, not
tapGesture on arbitrary rows. Do not show “applied” or “merged” stash badges
unless a future persisted source of truth is separately approved.

Make the primary action visually clear and keep secondary actions behind the
smallest appropriate menu or row affordance. Use sentence-case labels without
ellipsis. Disable an action while the shared coordinator is busy, and show
progress/error state without losing the selected item.

**Verify**: explicit preview coverage passes for the inspector. Manual checks
cover no branch/no stash/no remote, dirty and clean working tree, conflict
failure, protected/current branch, increased contrast, Reduce Transparency,
Reduce Motion, keyboard focus, VoiceOver labels, and Escape dismissal.

### Step 5: Run the high-risk validation gate

Run focused stash, branch, and coordinator tests, then make agent-check,
explicit preview coverage, make lint && make test, and git diff --check. Review
the final diff against the external-state addendum and ADR 0009. Confirm no
credential values or full Git command output entered source, tests, logs, or
plans.

**Verify**: every command exits successfully; any unavailable native UI check
is recorded as a handoff item rather than hidden by weakening a gate.

## Test plan

- Add GitStashServiceTests.swift with pure parser cases and temporary
  repository Apply/Drop cases using stable hashes and no sleeps.
- Extend GitManagerBranchOperationsTests.swift for local unmerged branch
  query, tracking-state mapping, and stale context rejection.
- Extend MainMenuActionCoordinatorTests.swift for admission, duplicate action,
  A/B path publication, partial push failure, Apply failure, and operation
  completion refresh.
- Reuse existing BranchManagementSheet and working-tree action tests where
  possible. Do not launch visible windows or previews from XCTest.
- Follow ADR 0009: separate A/B temporary repositories and CheckedContinuation
  gates for any operation that must stay open while selection changes.

Focused verification:

    make test-focused TEST_FILTER='GitMenuBarTests/GitStashServiceTests'
    make test-focused TEST_FILTER='GitMenuBarTests/GitManagerBranchOperationsTests'
    make test-focused TEST_FILTER='GitMenuBarTests/MainMenuActionCoordinatorTests'
    make lint && make test

## Done criteria

- [ ] The inspector contains detailed working-tree, push/sync, branch, and
      stash views with one primary action and safe secondary actions.
- [ ] Stash rows use stable hashes; Apply does not remove the stash and Drop is
      confirmed; no applied/merged/undone status is invented.
- [ ] Branch health is explicitly local reachability against the selected
      default branch; remote fetch is not added.
- [ ] New mutations capture repository identity before await, reject stale or
      duplicate operations, serialize same-path work, and do not publish A
      results into selected project B.
- [ ] Existing GitManager facade, BranchManagementSheet, file actions,
      credentials, and monitor boundary are reused.
- [ ] Focused tests, make agent-check, explicit preview coverage,
      make lint && make test, and git diff --check pass.
- [ ] No files outside Scope are modified; plans/README.md has the Plan 078
      status/evidence row only.

## STOP conditions

Stop and report if:

- the implementation needs a public generic command bus, new Git runner
  protocol, per-project manager, persistent stash/action database, or network
  fetch;
- a stash operation can only target stash@{N} or cannot prove the selected
  hash remains in the captured repository;
- an action can continue after a project switch without a captured context;
- the existing code would auto-force-push, pop a stash, discard data, or
  delete a branch without explicit confirmation;
- a branch query would claim GitHub PR merge status from local Git refs;
- the shell requires nested scroll views or one UI file per metric;
- a command mutates the user's real repository during tests;
- credentials or full authenticated command output would be persisted/logged;
- the live code differs from the Current state in an unexplained way;
- a verification command fails twice after a scoped fix; or
- an out-of-scope path must be modified.

## Maintenance notes

- Keep the stash service concrete and shallow; if a second stash backend is
  ever required, introduce an adapter at that point rather than now.
- Any future stash “applied” history needs explicit persisted product scope,
  migration, privacy, and deletion semantics; it is not derivable from
  retained Git refs.
- The existing branch-management sheet remains the full CRUD surface. Do not
  slowly grow the inspector into a second sheet.
- Reviewers should inspect context capture, branch/ref preflight, non-force
  push behavior, stable stash IDs, confirmation coverage, error/partial
  success, and project-switch publication.
- Plan 079 consumes the history section selection and should use the same
  operation owner for reset/restore.
