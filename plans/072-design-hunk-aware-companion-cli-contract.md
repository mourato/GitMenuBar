# Plan 072: Design the hunk-aware Companion CLI contract

> **Executor instructions**: Read this plan completely before editing. This is
> a design spike, not a source implementation. Use one isolated worktree and
> write the decision record only after Plans 057 and 068 have settled the Swift
> 6.4/toolchain and file-level scope contracts. Root-session review owns the
> final API decision; do not delegate it to a child agent.
>
> **Drift check (run first)**: `git diff --stat 11a88dd..HEAD --
> GitMenuBar/Services/CLI GitMenuBar/Services/Git/GitAtomicCommitService.swift
> GitMenuBar/Models/GitModels.swift GitMenuBarCLI docs/adr/0003-companion-cli-for-agent-commits.md
> plans`

## Status

- Priority: P2
- Effort: M for the spike; implementation effort is intentionally not estimated
  until the contract is accepted
- Risk: HIGH
- Depends on: Plans 057 and 068; Plan 064 hunk-aware menu-bar execution is DONE
- Category: architecture / API contract / CLI mutation safety
- Planned at: commit `11a88dd`, 2026-08-11

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: High / Full
- **Parallelizable**: No. The spike consumes the file-level scope and existing
  hunk/index contracts; its decisions must be reviewed as one artifact.
- **Reviewer required**: Yes — root-session review of JSON versioning, stale
  admission, index safety, exit codes, and backward compatibility.
- **Rationale**: The current CLI can only persist file/message groups, while the
  menu-bar path already has hunk IDs, patches, HEAD, and fingerprints. Shipping
  hunk CLI fields before deciding how plans are rehydrated and rejected when
  stale would create an unsafe half-contract.
- **Escalate when**: the design requires arbitrary patch execution, breaking
  schema v1, interactive TTY review, or a new credential/IPC channel.

## Why it matters

Agents need to propose, inspect, and safely apply hunk selections without
re-running a model against a changed worktree. Today the CLI DTO contains only
files and messages; `CompanionCLIService` drops hunk IDs and applies through the
file-level path. The UI executor has stronger snapshot and temporary-index
invariants, but those are not yet a versioned non-interactive CLI contract.

The right next step is a short decision record that makes the lifecycle
explicit before code is written: what a plan identifies, how apply consumes it,
how stale work is reported, what remains backward compatible, and how partial
failure is represented.

## Current state

- `GitMenuBar/Services/CLI/CompanionCLIOutput.swift:78-103` defines
  `CompanionCLIAtomicGroupDTO` with `files` and `message` only; atomic plan and
  progress payloads are schema version 1.
- `CompanionCLIService.swift:141-146` converts DTO groups back to
  `AtomicCommitGroup` without hunks. Apply at `:149-187` validates file paths and
  calls file-level `commitAtomicGroupAsync`.
- `GitMenuBar/Models/GitModels.swift:273-280,332-418` already models groups,
  file/hunk validation, and overlap errors. `AtomicCommitHunk` at `:420-427`
  stores ID, path, ordinal, header, counts, and exact patch; a snapshot at
  `:430-475` stores HEAD, fingerprint, files, and hunks.
- `GitAtomicCommitService.swift:220-323` revalidates HEAD/fingerprint, requires
  a clean real index for the current hunk path, uses a temporary index, applies
  selected patches, commits in order, and reconciles the real index.
- `docs/adr/0003-companion-cli-for-agent-commits.md` requires versioned JSON,
  stable exit codes, non-interactive operation, new commits only, fail-closed
  AI/policy behavior, and no rollback after a mid-atomic apply failure.
- `plans/064` and the architecture ledger explicitly defer hunk-aware CLI until
  a versioned JSON and stale-plan contract exists.
- Existing CLI exit codes are success 0, operational failure 1, not-ready 2,
  invalid repository 3, and policy rejected 4. There is no stale-plan code.

## Commands and evidence

| Check | Command | Expected result |
|---|---|---|
| Contract inventory | `rg -n 'schemaVersion|CompanionCLIAtomic|AtomicCommitHunk|fingerprint|GIT_INDEX_FILE|CompanionCLIExitCode' GitMenuBar GitMenuBarCLI docs/adr plans` | The ADR covers every existing version, identity, and mutation boundary |
| ADR numbering | `ls docs/adr | sort` | The chosen next ADR number is unused; never overwrite an existing record |
| Guidance | `make guidance-check` | Plan/ADR links and required execution profiles pass |
| Markdown hygiene | `git diff --check` | Exit 0 |
| Source protection | `git diff --name-only -- GitMenuBar GitMenuBarTests GitMenuBarCLI` | Empty for this spike |

No build or source test is required for a docs-only spike; implementation plans
must add the appropriate test matrix after the contract is accepted.

## Suggested executor toolkit

- Use `code-quality`, `domain-modeling`, `delivery-workflow`, and the existing
  Companion CLI/hunk implementation as evidence.
- Reuse existing terms: `AtomicCommitSnapshot`, `AtomicCommitHunk`,
  `AtomicCommitPlan`, `DiffScope`, `schemaVersion`, and stable exit code.
- Do not create a prototype DTO or add placeholder fields to production Swift
  during the spike.

## Scope

In scope:

- Add `docs/adr/0008-companion-cli-hunk-plan-contract.md` (or the next unused
  ADR number if execution finds 0008 occupied) documenting the accepted
  contract and rejected alternatives.
- Define proposal/apply lifecycle, including whether persisted apply consumes a
  JSON file/stdin plan and how the existing same-process `--apply` behavior
  remains compatible.
- Define hunk identity and snapshot admission using current repository path
  scope, HEAD, status/diff fingerprint, path, hunk ID, and the minimum metadata
  needed to explain a stale rejection.
- Define schema evolution from file-level atomic plan v1 to a hunk-capable
  version without breaking existing consumers.
- Define staged/all scope interaction, clean-index requirements, partial-failure
  progress, stable stale/error exit semantics, and bounded output/privacy rules.
- Include representative JSON examples for proposal, accepted apply, stale
  rejection, and partial failure.

Out of scope:

- Editing production Swift, CLI argument parsing, JSON DTOs, exit-code enums, or
  Git execution in this spike.
- Implementing hunk staging, temporary-index handling, patch transport, model
  prompts, or a plan-file CLI.
- Changing Plan 0003's no-push/no-reset/no-rollback policy or adding an
  interactive review mode.

## Git workflow

Use `docs/design/companion-cli-hunk-contract` in an isolated worktree if the
repository permits a docs branch; otherwise use the normal isolated plan
worktree. Use a scoped Conventional Commit such as
`docs(adr): define hunk-aware CLI plan contract`; do not push, reset, or rewrite
history. This spike must not modify source files.

## Ordered implementation steps

### 1. Inventory the existing contracts

Read ADR 0003, Plan 064, Plan 068, the CLI DTO/service, the atomic models, and
the temporary-index executor. Build a one-page compatibility matrix showing
file-level v1, current same-process `--apply`, proposed persisted hunk plan,
scope, snapshot identity, and failure behavior.

**Verify:** every proposed field or decision is tied to an existing model or a
specific unresolved product choice; no source file changes exist.

### 2. Decide plan lifecycle and stale admission

Record one concrete lifecycle: proposal emits a versioned JSON plan; apply
consumes the plan under the same repository path scope; the CLI rehydrates the
current snapshot and refuses mutation unless HEAD/fingerprint and selected
scope match. Decide whether raw patches are omitted from authoritative apply
input and regenerated from the validated current snapshot (preferred for
avoiding arbitrary patch execution), with any preview representation explicitly
non-authoritative and bounded.

Define what happens when the worktree changes, the repository path differs, a
hunk ID disappears, the index is not clean, or a plan version is unsupported.
The stale path must be fail-closed and must not create a commit.

**Verify:** the ADR names the exact admission inputs, no-mutation stale path,
and user/agent-readable reason for each rejection.

### 3. Decide schema, compatibility, and failure payloads

Keep file-level schema v1 decodable for existing agents. Choose whether the
hunk contract is schema v2 or a new plan kind with an explicit version, then
define DTO fields for scope, repository identity, snapshot identity, complete
files, hunk selections/metadata, and commit messages. Do not duplicate raw
patches as a second source of truth unless the root review explicitly accepts
that risk.

Add a stable stale-plan exit result without renumbering existing codes; if a
new code is required, document its numeric value, JSON error payload, and
compatibility fallback. Keep partial failure as completed/remaining groups with
the current no-rollback rule.

**Verify:** representative JSON is deterministic/sorted, bounded, backward
compatible for v1 consumers, and sufficient for a non-interactive agent to
decide whether to retry or ask for review.

### 4. Reconcile with scope and index safety

Document how `--staged`, `--all`, and the no-flag mode interact with hunk plans,
including clean-index or temporary-index requirements. Reuse Plan 068's
file-level scope meaning and Plan 064's snapshot/temporary-index invariants;
do not create a contradictory CLI-only interpretation.

Document path validation, allowed files/hunks, file/hunk overlap, index lock,
partial commit, and process interruption behavior. Explicitly state whether
the first implementation supports staged hunk plans or refuses them until a
safe primitive exists.

**Verify:** the ADR has a state/decision table for propose → inspect → apply →
stale/failure and names the owner of every safety check.

### 5. Review and hand off the implementation boundary

Run the Commands and evidence table, inspect the ADR for unresolved alternatives
and accidental source edits, and obtain root-session review. If accepted, split
the future implementation into the smallest follow-up plan(s) with exact DTO,
CLI, executor, and test scope. Do not implement any of those changes here.

**Verify:** the ledger marks this spike complete only with an accepted ADR and
an explicit follow-up boundary; unresolved choices remain STOP conditions.

## Test plan

This spike uses documentation validation rather than production tests:

- Validate all JSON examples with a small review fixture or existing encoder
  reasoning; do not add production DTOs just to validate examples.
- Check v1 compatibility and v2/next-kind rejection behavior in the ADR matrix.
- Check stale HEAD, stale fingerprint, missing hunk, changed scope, locked
  index, partial failure, and unsupported version scenarios are all specified.
- Run `make guidance-check` and `git diff --check`; confirm no source paths are
  modified.

The accepted implementation plan must add focused Codable/CLI/temporary-index
tests before changing production behavior.

## Done criteria

- An accepted ADR defines a versioned, non-interactive hunk plan lifecycle.
- Snapshot identity, stale rejection, scope, index, and partial-failure
  semantics are concrete and fail closed.
- Existing file-level schema v1 and ADR 0003 behavior remain compatible.
- Raw patch authority, output bounds, privacy, and stable exit semantics are
  explicitly decided.
- Root review accepts the contract and follow-up implementation boundary; only
  the ADR/plan ledger/docs links changed.

## STOP conditions

- Any required decision remains “implementation will decide later”.
- The design relies on applying arbitrary patches from untrusted JSON without
  snapshot validation.
- The proposal breaks schema v1, silently changes `--apply`, or invents a new
  interactive/IPC dependency.
- Stale or partial failure can mutate the repository before being reported.
- The spike starts changing production Swift or adds placeholder API fields.

## Maintenance notes

When the contract is implemented, keep this ADR and ADR 0003 synchronized with
schema versions, exit codes, CLI help, JSON fixtures, and rollback/index rules.
Any future schema change needs a compatibility example and a stale-plan test;
do not treat JSON as an incidental print format.
