# Versioned hunk-aware Companion CLI plan contract

## Status

Accepted (2026-08-11).

## Context

ADR 0003 established `gitmenubar` as a non-interactive, soft-dependency CLI
for agent-oriented propose/apply commits. Its atomic JSON is currently
file-level schema v1: each group has `files` and `message`. The current
same-process `atomic --apply` command proposes a plan and applies that plan in
one process; it does not persist a plan for inspection or edit.

The menu-bar hunk flow now has the stronger primitives needed for a safe
contract: `DiffScope`, `AtomicCommitSnapshot`, `AtomicCommitHunk`,
`AtomicCommitPlan`, stable hunk IDs, a snapshot fingerprint, and a temporary
Git index. Plans 064 and 068 establish that hunk execution must reject stale
input, protect the real index, and keep file-level CLI scope semantics
explicit. This record defines the persisted, non-interactive boundary without
claiming that the CLI implementation exists.

## Decision

Add a persisted hunk-aware plan kind using explicit **schema v2**. A v2 plan
is emitted as deterministic JSON, reviewed or edited by an agent, then passed
to `atomic --apply --plan <file>` or `atomic --apply --plan -` (stdin) with
the same repository path scope used to propose it. Apply rehydrates the
current snapshot and admits the plan only when every identity and safety check
matches. A v2 plan is never applied to a different repository path scope.

The existing same-process `atomic --apply` remains compatible with file-level
schema v1 and its Plan 068 meanings: no flag means unstaged compatibility
scope, `--staged` means staged-only, and `--all` means staged, unstaged, and
untracked. V1 remains decodable and remains the file-level fallback; v2 does
not silently reinterpret it as a hunk plan.

The first hunk CLI implementation supports only ordinary unstaged text hunks
with a clean real index. It refuses staged hunk plans, including v2 requests
using `--staged` or `--all`, until a safe primitive preserves staged and
unstaged boundaries. File-level v1 keeps its existing scope contract, subject
to Plan 068's safe refusal where a file-level staged apply cannot preserve the
boundary.

## Contract

### Plan identity and fields

A v2 plan has these fields. Arrays are sorted by path, hunk ID, then group
order; object keys use the existing sorted-key JSON encoder. The `schema` and
`schemaVersion` fields are both explicit so a command can reject an unknown
plan kind before decoding selections.

```text
schema: "gitmenubar.atomic-hunk-plan"
schemaVersion: 2
repository: {
  identity: { canonicalRoot: String, gitDirectory: String },
  pathScope: String
}
scope: "unstaged" | "staged" | "all"
snapshot: {
  head: String,
  fingerprint: String,
  statusIdentity: String,
  diffIdentity: String,
  completeFiles: [{ path: String, status: String }],
  hunks: [{ id: String, path: String, ordinal: Int, header: String,
            additions: Int, removals: Int }]
}
groups: [{ id: String, completeFiles: [String], hunks: [HunkSelection],
           message: String }]
messages: { policy: String, maxLength: Int }
```

`repository.identity` identifies the resolved repository/worktree used for
the proposal; `pathScope` is the canonical repository path supplied by
`--path` or resolved from cwd. `gitDirectory` is the resolved Git directory,
not an arbitrary user-supplied path. Implementations must not include remote
URLs, credentials, tokens, or environment dumps.

Each `HunkSelection` contains the selected `id` and the same immutable
metadata (`path`, `ordinal`, `header`, `additions`, `removals`) that was shown
in the proposal. Metadata is admission evidence, not an instruction to apply
text. `completeFiles` is for whole-file selections and may not overlap a path
selected by `hunks`. `messages` identifies the message-policy contract and
bounded message rules; the message in each group remains the value subject to
policy validation at apply time. The `maxLength` bound is a v2 contract rule
for the future implementation; it does not claim that the current
`CommitMessagePolicy` already has this field.

`statusIdentity` and `diffIdentity` are deterministic digests of the sorted
status records and sorted diff snapshot respectively. `fingerprint` is the
existing combined snapshot identity (including HEAD, status, paths, statuses,
and diff bytes). All three are required so an agent-readable rejection can
say whether repository state, status, or content changed.

Raw patches are not authoritative v2 fields. A bounded patch preview may be
added to proposal output for inspection only, with a fixed byte and line cap
and an explicit `authoritative: false` marker. Apply regenerates the current
snapshot and obtains the selected patch fragments from the validated current
snapshot; it never executes arbitrary patch text from JSON.

### Lifecycle/state table

| State | Input/output | Required behavior |
| --- | --- | --- |
| Propose | repository path plus scope | Resolve and canonicalize the path, capture the snapshot, generate groups, validate messages, and emit one sorted v2 JSON document. |
| Inspect/edit | proposal JSON | An agent may reorder groups, select known complete files/hunks, and edit messages. It must preserve identity, scope, and hunk metadata. |
| Apply admission | v2 JSON file or stdin plus same `--path` scope | Decode the declared version/kind, resolve the same repository, rebuild the snapshot, validate all identities and selections, then check index safety before mutation. |
| Apply accepted | admitted groups | Regenerate/validate current hunk fragments, use the temporary-index executor, and create new commits in group order. |
| Stale/rejected | failed admission or policy/safety check | Emit an actionable agent-readable JSON error, create no commit, and return the stable rejection code. |
| Partial failure | a later group fails after earlier commits | Stop immediately; report completed and remaining groups. Do not rollback earlier commits or retry implicitly. |

The apply command must not silently read a second plan source, broaden the
path scope, or regenerate AI grouping after an edited plan is rejected.

## Schema/versioning

Schema v1 remains decodable exactly as currently defined: `schemaVersion: 1`
and file-level groups containing `files` and `message`. Existing consumers
may ignore new optional error fields. Schema v2 is a different explicit plan
kind and is rejected by v1 consumers rather than being misread as a file
plan. Future incompatible changes increment `schemaVersion`; additive fields
must remain optional and retain deterministic ordering. Unknown versions and
unknown plan kinds fail before any Git mutation.

The compatibility and decision table is:

| Payload/command | Decode/apply status | Scope | Snapshot admission | Authority |
| --- | --- | --- | --- | --- |
| v1 file-level proposal | Existing consumers and current CLI continue to decode | Plan 068 no-flag/`--staged`/`--all` semantics | Current file-level validation | Files and messages only; no hunk claims |
| v1 same-process `atomic --apply` | Compatible | Same scope flag used for proposal and apply | File-level allowed-path/index checks | Current file-level service |
| v2 persisted proposal | New hunk-aware consumer | Proposal scope is retained; first implementation admits `unstaged` only | HEAD, path scope, status/diff identities, fingerprint, hunk IDs/metadata, lock/index checks | Current snapshot regenerates patches |
| v2 edited apply | Accepted only if edits stay within snapshot selections and policy | Must equal proposal and invocation scope | Same as v2 persisted proposal | JSON patch previews are never authority |
| Unknown v2+ or wrong kind | Rejected before mutation | N/A | Unsupported-version reason | None |

## Admission/rejection matrix

Admission is fail-closed and occurs before the first stage or commit. The
agent receives the named reason and a remediation such as “regenerate the
proposal” or “unstage changes”.

| Check | Reject when | Reason/actionable response | Commit created |
| --- | --- | --- | --- |
| Repository identity/path | canonical root, Git directory, or `pathScope` differs | `repository_scope_mismatch`; apply with the original `--path` | No |
| HEAD | current HEAD differs from `snapshot.head` | `stale_head`; regenerate | No |
| Status/fingerprint | status identity or combined fingerprint differs | `stale_worktree`; inspect changes and regenerate | No |
| Diff identity | diff identity differs or a selected diff cannot be regenerated | `stale_diff`; regenerate | No |
| Complete file | path is outside `completeFiles`, missing, or has changed status | `unknown_or_stale_file`; regenerate | No |
| Hunk identity | selected ID is absent, duplicated, reordered into overlap, or metadata differs | `unknown_or_stale_hunk`; regenerate | No |
| Selection overlap | a complete file and any hunk from that path are both selected, or a hunk is in two groups | `selection_overlap`; edit the plan | No |
| Schema/kind | version or plan kind is unsupported or malformed | `unsupported_plan_version`; use a compatible CLI | No |
| Index lock | `.git/index.lock` exists or appears during preflight | `index_locked`; close the other Git operation and retry | No |
| Hunk index safety | real index is not clean, or scope is staged/all for the first hunk implementation | `hunk_scope_not_supported`; unstage or use file-level v1 | No |
| Message policy | any edited message is rejected | Existing policy-rejected code and message | No for the rejected plan |

The service rechecks the lock and snapshot immediately before mutation. A
race after that point is an operational Git failure; it must stop and report
the failing group/hunk rather than guess or execute a supplied raw patch.

## Scope/index safety

Plan 068 is the source of truth for file-level scope: no flag is unstaged
compatibility scope, `--staged` is staged-only, and `--all` is the union of
staged, unstaged, and untracked paths. The same resolved scope must appear in
proposal, JSON, and apply invocation; a mismatch is a scope rejection.

For the first v2 implementation, only `scope: "unstaged"` with no staged
content is admitted. This deliberately refuses staged hunk plans and `--all`
hunk plans, because the existing safe hunk primitive initializes a temporary
index from HEAD and cannot yet preserve arbitrary pre-existing staged content
in a non-interactive persisted contract. `--staged` and `--all` remain valid
for v1 file-level plans. A future staged-hunk implementation must define its
index transaction and fixtures before changing this refusal.

The executor validates repository-relative, normalized paths; rejects `..`,
absolute paths, path aliases, missing files, path/hunk overlap, duplicate
hunks, unknown hunks, and selections outside the captured snapshot. It uses a
temporary index under the system temporary directory, never the repository's
real index, and removes it on normal or interrupted process cleanup. An
existing `index.lock` is a hard preflight rejection; the implementation must
not remove or overwrite a lock.

## Failure/exit semantics

Existing values are immutable: `0` success, `1` operational failure, `2`
not-ready, `3` invalid repository, and `4` policy rejected. Add `5` as
`stalePlan` for snapshot, scope, selection, unsupported-version, and locked-
index admission failures that are safe to retry after inspection. No existing
number is renumbered. A malformed CLI invocation may still be handled by the
argument parser rather than this contract.

JSON errors retain the current v1 envelope fields `schemaVersion`, `error`,
and `exitCode`, then add optional fields: `errorCode`, `retryable`,
`repositoryPathScope`, `completedGroups`, and `remainingGroups`. The latter
two are bounded group summaries with only `id` and `message`, never patch
content. Existing v1 decoders can ignore unknown fields; v2-aware agents use
`errorCode` instead of parsing prose. `error` remains concise and actionable
and is bounded with all other output.

Apply creates only new commits. It never pushes, resets, amends, rebases,
force-updates, or rolls back earlier commits. If group N fails, groups before
N are completed and groups N onward are remaining. If the process is
interrupted, temporary files are cleaned best-effort, earlier commits remain,
and the result is unknown to the caller; a retry must first inspect HEAD and
the working tree. A changed HEAD then causes stale admission and no additional
commit.

Output is bounded by fixed limits for number of files, hunks, groups, message
length, JSON bytes, and any preview bytes/lines. Truncation is an explicit
error, never silent. No output contains secrets, tokens, credentials, raw
environment state, or unbounded raw patches.

## JSON examples

Examples use sorted object keys and stable illustrative identities. The
`hunks` metadata in a group repeats the snapshot metadata deliberately so an
edited plan can be checked without treating it as patch authority.

### Proposal

```json
{"groups":[{"completeFiles":[],"hunks":[{"additions":2,"header":"@@ -10,2 +10,4 @@","id":"Sources/App.swift#hunk-1","ordinal":1,"path":"Sources/App.swift","removals":0}],"id":"group-1","message":"feat: add menu action"}],"messages":{"maxLength":120,"policy":"default"},"repository":{"identity":{"canonicalRoot":"/work/repo","gitDirectory":"/work/repo/.git"},"pathScope":"/work/repo"},"schema":"gitmenubar.atomic-hunk-plan","schemaVersion":2,"scope":"unstaged","snapshot":{"completeFiles":[{"path":"Sources/App.swift","status":"modified"}],"diffIdentity":"diff-sha256:2222","fingerprint":"sha256:3333","head":"1111111111111111111111111111111111111111","hunks":[{"additions":2,"header":"@@ -10,2 +10,4 @@","id":"Sources/App.swift#hunk-1","ordinal":1,"path":"Sources/App.swift","removals":0}],"statusIdentity":"status-sha256:4444"}}
```

### Accepted apply input

```json
{"groups":[{"completeFiles":[],"hunks":[{"additions":2,"header":"@@ -10,2 +10,4 @@","id":"Sources/App.swift#hunk-1","ordinal":1,"path":"Sources/App.swift","removals":0}],"id":"group-1","message":"feat: add menu action"}],"messages":{"maxLength":120,"policy":"default"},"repository":{"identity":{"canonicalRoot":"/work/repo","gitDirectory":"/work/repo/.git"},"pathScope":"/work/repo"},"schema":"gitmenubar.atomic-hunk-plan","schemaVersion":2,"scope":"unstaged","snapshot":{"completeFiles":[{"path":"Sources/App.swift","status":"modified"}],"diffIdentity":"diff-sha256:2222","fingerprint":"sha256:3333","head":"1111111111111111111111111111111111111111","hunks":[{"additions":2,"header":"@@ -10,2 +10,4 @@","id":"Sources/App.swift#hunk-1","ordinal":1,"path":"Sources/App.swift","removals":0}],"statusIdentity":"status-sha256:4444"}}
```

### Stale rejection

```json
{"completedGroups":[],"error":"Working tree fingerprint changed; regenerate the proposal before applying.","errorCode":"stale_worktree","exitCode":5,"remainingGroups":[{"id":"group-1","message":"feat: add menu action"}],"repositoryPathScope":"/work/repo","retryable":true,"schemaVersion":1}
```

### Partial failure

```json
{"completedGroups":[{"id":"group-1","message":"feat: add menu action"}],"error":"Group group-2 failed while applying hunk Sources/App.swift#hunk-2; inspect the repository before retrying.","errorCode":"operational_failure","exitCode":1,"remainingGroups":[{"id":"group-2","message":"fix: handle failure"},{"id":"group-3","message":"test: cover failure"}],"repositoryPathScope":"/work/repo","retryable":false,"schemaVersion":1}
```

## Consequences

- Agents can inspect and edit a complete, versioned hunk selection without
  rerunning the model against a changed worktree.
- Snapshot admission is explicit and fail-closed; the cost is that ordinary
  edits, rebases, status changes, and index activity require a new proposal.
- The first hunk implementation is intentionally narrower than file-level v1:
  unstaged text hunks only, with staged/all support deferred.
- Deterministic, bounded JSON is suitable for fixtures and automation, while
  privacy and patch-authority rules prevent the plan from becoming an
  arbitrary patch execution channel.
- Mid-apply interruption and failure can leave earlier new commits, matching
  ADR 0003; agents must inspect before retrying.

## Rejected alternatives

- **Reuse schema v1 and add optional `hunks`.** Rejected because old
  consumers could silently ignore hunk selections and apply whole files.
- **Use a new plan kind without an explicit version.** Rejected because
  version and kind answer different compatibility questions and need explicit
  rejection paths.
- **Trust raw patches supplied in JSON.** Rejected because a stale or edited
  patch could bypass snapshot and path validation.
- **Apply against the current worktree without a fingerprint.** Rejected
  because an agent could commit changes it did not inspect.
- **Support staged hunk plans immediately.** Rejected until a temporary-index
  transaction can preserve staged/unstaged boundaries and unrelated index
  entries.
- **Interactive TTY review or XPC to the menu-bar app.** Rejected per ADR
  0003's non-interactive, app-quit-compatible boundary.
- **Rollback after partial failure.** Rejected to preserve ADR 0003's
  observable completed-commit semantics and avoid destructive reset behavior.

## Implementation boundary

This ADR is a documentation-only spike. It does not add production DTOs,
CLI flags, parsing, service admission, hunk execution, fixtures, or tests.

The exact future implementation boundary is one follow-up plan:
**Plan 073: Implement versioned hunk-aware Companion CLI apply**.

That plan must add, and only add:

1. DTOs/`Codable` for v2 plans, hunk selections, bounded previews, enriched
   error payloads, and v1 decoding fixtures.
2. CLI parsing for `--plan <file>|-`, same-path-scope enforcement, and stable
   exit code 5 without changing 0–4.
3. Service admission that canonicalizes repository identity, rebuilds status
   and diff identities, validates HEAD/fingerprint/hunk metadata/overlap,
   checks policy and index lock, and refuses staged/all hunk plans.
4. A hunk executor that reuses `AtomicCommitSnapshot`,
   `AtomicCommitPlan`, and the existing temporary-index seam; it regenerates
   current patch fragments and never executes JSON patch text.
5. Deterministic fixtures/tests for sorted proposal and apply JSON, v1
   decoding, every admission rejection, path/index safety, no commit on
   rejection, partial failure, interruption guidance, bounded output, and
   staged/all refusal.

Plan 073 must update this ADR and ADR 0003 if the accepted implementation
changes any field, exit meaning, or scope boundary. It must not claim that
this spike itself implements the contract.
