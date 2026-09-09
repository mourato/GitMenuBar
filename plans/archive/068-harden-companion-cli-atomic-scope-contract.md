# Plan 068: Honor the Companion CLI atomic scope contract

> **Executor instructions**: Read this plan completely before editing. Use one
> isolated worktree, preserve unrelated changes, and keep the public JSON
> schema file-level and backward compatible. This plan requires a root-session
> review after implementation; do not delegate that review to a child agent.
> Reconcile Plan 057's Swift 6.4 toolchain baseline before starting.
>
> **Drift check (run first)**: `git diff --stat 11a88dd..HEAD --
> GitMenuBar/Services/CLI GitMenuBar/Services/Git GitMenuBar/Services/AI
> GitMenuBar/Services/AI/GitMenuBarCommitSession.swift
> GitMenuBar/Models/AIModels.swift GitMenuBarTests/CompanionCLIServiceTests.swift
> GitMenuBarCLI plans`

## Status

- Priority: P1
- Effort: M
- Risk: HIGH
- Depends on: Plan 057 (Swift 6.4 toolchain baseline); Plans 036–038 and
  064 are DONE
- Category: correctness / CLI / Git mutation safety
- Planned at: commit `11a88dd`, 2026-08-11

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: High / Full
- **Parallelizable**: Yes after Plan 057, because the primary source slice is
  Companion CLI/Git scope code; integrate and validate serially.
- **Reviewer required**: Yes — root-session review of scope semantics, staged
  content preservation, JSON compatibility, and mutation safety.
- **Rationale**: `--staged` and `--all` are accepted by the CLI but atomic
  proposal ignores them, while apply currently validates against every change
  and restages whole files. A small-looking fix crosses the Git index boundary.
- **Escalate when**: safe staged application requires a new persisted hunk
  contract, changes exit-code meaning, or cannot preserve unrelated index and
  worktree state.

## Why it matters

`gitmenubar atomic --staged` can report no changes when only the index has
changes because `buildAtomicPlan` always reads `changedFilesCLI`. `--all` also
omits staged-only files. Even after proposal is corrected, apply must not turn a
staged-only request into a full-worktree commit or silently discard unrelated
index state. Agents need the scope flag to mean the same thing for proposal,
validation, and commit execution.

This plan repairs the existing file-level CLI contract. It does not add
hunk-aware CLI JSON; that is the separate design spike in Plan 072.

## Current state

- `GitMenuBarCLI/Commands.swift:8-12,109-134` exposes shared `--staged` and
  `--all` flags for `atomic` and rejects using both together.
- `GitMenuBar/Services/CLI/CompanionCLIService.swift:105-138` declares the
  atomic `options` argument but ignores it, calls `updateUncommittedFilesAsync`,
  always uses `gitManager.changedFilesCLI`, and obtains diffs through the
  unstaged-only `diffForChangedFilesAsync()` path.
- The same service's apply path at `:149-187` validates against the union of
  changed, staged, and uncommitted paths regardless of the requested scope,
  then calls file-level `commitAtomicGroupAsync` for each group.
- `GitMenuBar/Services/CLI/CompanionCLIOutput.swift:29-40` already resolves
  `DiffScope.staged` and `.all`; `CompanionCLIService.filePaths(for:)` already
  centralizes file-path selection for single-commit plans.
- `GitManager` maintains separate `stagedFiles`, `changedFiles`, and
  `uncommittedFiles`; `diffStagedAsync`, `diffUnstagedAsync`, and
  `diffAllAsync` already exist. `GitAtomicCommitService.diffForChangedFilesAsync`
  is currently unstaged tracked-file diffing.
- `GitAtomicCommitService.commitAtomicGroupAsync` restores the real index and
  runs `git add -- <files>` before committing. That behavior is valid for the
  existing file-level all/unstaged flow only if its scope is explicit; it is not
  a safe staged-only implementation when a file has both staged and unstaged
  content or unrelated paths are staged.
- `GitMenuBarTests/CompanionCLIServiceTests.swift:1-180` covers message policy,
  one file-level commit, JSON for message output, and option parsing, but has no
  atomic proposal or scope-preserving apply regression.

## Commands and evidence

| Check | Command | Expected result |
|---|---|---|
| Scope references | `rg -n 'buildAtomicPlan|applyAtomicPlan|changedFilesCLI|stagedFilesCLI|resolvedDiffScope|diffForChangedFilesAsync' GitMenuBar GitMenuBarCLI GitMenuBarTests` | Every atomic proposal/apply path resolves one explicit scope |
| Focused tests | `make test TEST_FILTER=CompanionCLIServiceTests` | Scope and apply regressions pass, using the repository's supported filter syntax |
| Focused gate | `make agent-check` | Changed lint and build pass |
| Full tests | `make test` | Existing tests plus CLI regressions pass |
| Full lint | `make lint` | No new warnings; Plan 057's fail-closed policy applies |
| Guidance/hygiene | `make guidance-check && git diff --check` | Exit 0 |

If the Makefile does not support `TEST_FILTER`, use its documented focused-test
argument or the smallest existing `xcodebuild ... -only-testing` equivalent;
do not invent a second test runner.

## Suggested executor toolkit

- Use `code-quality` and `delivery-workflow` for the narrow mutation boundary.
- Reuse `DiffScope`, `filePaths(for:)`, the existing Git diff helpers, and the
  current `AtomicCommitPlan` validator.
- Use `swift-conventions` after Plan 057; do not add a protocol or dependency
  solely to make this testable if the existing temp-repository/test seams work.
- If full service coverage is otherwise impossible because
  `GitMenuBarCommitSession` constructs its grouper internally, add only an
  optional concrete grouper injection with the current production default—no
  new protocol or dependency.

## Scope

In scope:

- Resolve one explicit atomic scope for proposal and apply: preserve current
  no-flag behavior as an explicit compatibility decision, make `--staged`
  staged-only, and make `--all` include staged, unstaged, and untracked paths.
- Supply per-file diffs that match the selected scope to the existing grouping
  service; do not feed staged files an unstaged diff or concatenate away file
  identity.
- Validate submitted groups against the same selected scope used to propose
  them.
- Make staged-only apply either preserve staged/unstaged boundaries through a
  safe existing temporary-index approach or refuse with a clear operational
  error when the file-level contract cannot guarantee that boundary. Never
  silently broaden staged scope.
- Add deterministic temp-repository tests for staged-only, mixed `--all`,
  default compatibility, JSON output, and safe apply/index behavior.

Out of scope:

- Hunk-aware Companion CLI schema, persisted plan files, stale fingerprints, or
  new exit codes; those belong to Plan 072.
- Rewriting the app's hunk executor, changing menu-bar Atomic Commit behavior,
  changing push/rebase/reset policy, or adding a new Git abstraction layer.
- Changing the existing file-level JSON schema unless a backward-compatible
  field is strictly required and approved in the root review.

## Git workflow

Use `fix/companion-cli-atomic-scope` in an isolated worktree. Use a scoped
Conventional Commit such as `fix(cli): honor atomic scope flags`; do not push,
reset, or rewrite history. Keep generated artifacts and credentials out of the
diff.

## Ordered implementation steps

### 1. Characterize the three scope paths

Add or run temp-repository characterization cases with staged-only changes,
unstaged-only changes, a file with both staged and unstaged content, an
untracked file, and mixed staged/unstaged files. Record what the current CLI
does before changing it. Confirm the intended no-flag behavior from the live
implementation and preserve it unless the root review explicitly changes the
contract.

**Verify:** each case identifies the exact expected path set and diff source;
the test setup does not call a real AI provider or persist secrets.

### 2. Route proposal through one scope decision

Resolve `DiffScope` once in `buildAtomicPlan`. Select files using the existing
manager arrays and `filePaths(for:)` pattern. Add the smallest scope-aware
per-file diff helper adjacent to the existing Git atomic diff seam, reusing
`diffStagedAsync`, `diffUnstagedAsync`, and untracked-file handling rather than
creating a second parser or a second scope enum. Keep paths sorted and stable.

**Verify:** a stub grouping response receives staged-only content for
`--staged`, the union for `--all`, and the preserved default for no flag; a
staged-only repository no longer returns “no changed files”.

### 3. Make apply obey the same scope and index boundary

Pass the resolved scope into apply validation. The allowed-file set must match
the proposal scope, and the apply primitive must not restore or stage content
outside the selected scope. Reuse the existing temporary-index machinery if it
already supports the required file-level operation. If staged-only file groups
cannot be applied without leaking unstaged content or disturbing unrelated
index entries, fail closed with an actionable error and add that case to the
contract tests; do not silently fall back to `--all`.

Preserve Plan 0003's guarantees: apply creates new commits only, stops on the
first failure, and does not add rollback, push, amend, rebase, or force logic.

**Verify:** applying `--staged` never includes an unstaged line, never commits
an unrelated staged path, and leaves the unrelated index/worktree state
unchanged; `--all` retains the existing file-level behavior.

### 4. Add CLI and service regression coverage

Extend `CompanionCLIServiceTests` (or add one focused test file only if the
existing file cannot stay readable). Assert scope-specific file sets and diff
content before the AI grouping call, JSON round-trip compatibility for the
existing schema, and apply behavior/progress for successful and partial
failure cases. Use the smallest existing AI stub or grouping seam; if a
concrete session injection is required, keep it optional and production-safe.
Do not make tests dependent on network providers.

**Verify:** the new tests fail against the pre-fix behavior for staged-only and
mixed `--all`, then pass with the fix and remain deterministic across repeated
runs.

### 5. Validate the handoff

Run the Commands and evidence table, inspect the diff for scope expansion, and
obtain the required root-session review. Update this plan and the relevant
ledger row only after behavior, tests, lint, and guidance checks pass.

**Verify:** the final diff is limited to the CLI/Git/test slices and no schema,
policy, or hunk contract changed without explicit review.

## Test plan

- Staged-only proposal with no unstaged files.
- `--all` proposal with staged-only, unstaged-only, untracked, and mixed paths.
- No-flag proposal preserving the current compatibility behavior.
- Staged/unstaged overlap: no unstaged content leaks into a staged apply; safe
  refusal is acceptable when the file-level contract cannot represent it.
- Unrelated staged path preservation and multi-group partial-failure progress.
- Existing `CompanionCLIServiceTests`, `make agent-check`, `make test`, and
  `make lint`.

## Done criteria

- Atomic proposal honors `--staged`, `--all`, and the documented no-flag mode.
- Proposal diffs, allowed files, and apply behavior use the same scope.
- Staged apply either preserves index/worktree boundaries or fails closed with
  a tested, actionable error; it never silently broadens scope.
- Existing file-level JSON remains backward compatible.
- Focused tests, full tests, lint, agent-check, guidance, and diff hygiene pass;
  root review accepts the mutation boundary.

## STOP conditions

- The no-flag default cannot be established without changing product behavior.
- Safe staged application requires persisted hunk JSON or a new CLI lifecycle;
  record the boundary and hand it to Plan 072 instead of shipping a guess.
- The fix would restore/reset/overwrite user changes outside the selected scope.
- A test needs a live provider, real credentials, or network access.
- The diff expands into menu-bar UI, push policy, or unrelated Git refactors.

## Maintenance notes

Any future CLI scope must update proposal selection, per-file diff generation,
apply validation, index-safety tests, and the Companion CLI ADR together. Keep
scope semantics explicit at the command boundary; do not let a convenience
helper silently choose unstaged/all behavior.
