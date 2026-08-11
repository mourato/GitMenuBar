# Plan 069: Include bounded hunk content in AI grouping prompts

> **Executor instructions**: Read this plan completely before editing. Use one
> isolated worktree and keep the change limited to prompt construction and
> regression tests. Preserve the existing parser, hunk IDs, fallback behavior,
> and snapshot/index safety. Root-session review is required after the change.
> Reconcile Plan 057's Swift 6.4 toolchain baseline before starting.
>
> **Drift check (run first)**: `git diff --stat 11a88dd..HEAD --
> GitMenuBar/Services/AI/AICommitGrouperService.swift
> GitMenuBar/Services/AI/AICommitGrouperService+Prompt.swift
> GitMenuBar/Models/GitModels.swift GitMenuBarTests/AICommitGrouperServiceTests.swift
> plans`

## Status

- Priority: P1
- Effort: M
- Risk: MEDIUM
- Depends on: Plan 057 (Swift 6.4 toolchain baseline); Plan 064 hunk-aware
  menu-bar execution is DONE
- Category: correctness / AI prompt / atomic commits
- Planned at: commit `11a88dd`, 2026-08-11

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: Medium / Full
- **Parallelizable**: Yes after Plan 057; the source slice is isolated to AI
  grouping prompt/tests, but integrate serially with other plan work.
- **Reviewer required**: Yes — root-session review of prompt fidelity,
  truncation behavior, and fallback safety.
- **Rationale**: The hunk model already stores exact patches, but the hunk
  prompt sends only IDs, headers, and line counts. Adding content is small, yet
  an unbounded prompt can create a new latency/cost failure.
- **Escalate when**: the fix requires changing hunk identity/fingerprint
  semantics, provider adapters, or the user-facing atomic review flow.

## Why it matters

The file-level grouping prompt includes diffs, but the hunk-level prompt gives
the model only metadata. Two unrelated hunks can therefore look identical when
their headers and additions/removals match. The model may group the wrong
hunks, undermining the atomic-commit safety that Plan 064 already provides at
execution time.

The fix should expose enough exact patch context to distinguish changes while
retaining a deterministic budget and a safe fallback when content is omitted or
truncated.

## Current state

- `GitMenuBar/Services/AI/AICommitGrouperService+Prompt.swift:47-65`
  `buildHunkGroupingPrompt` emits each hunk's ID, header, and
  `(+additions/-removals)` only; it never reads `AtomicCommitHunk.patch`.
- `GitMenuBar/Models/GitModels.swift:420-427` stores the exact patch on every
  `AtomicCommitHunk`; `AtomicCommitSnapshot` exposes the hunk collection and
  lookup by ID.
- The file-level prompt in the same prompt extension includes full per-file
  diffs, so this is a hunk-path fidelity gap rather than a missing provider
  capability.
- `AICommitMessageService` already uses a deterministic 40,000-character diff
  budget with baseline allocation and truncation notices for message prompts.
  Reuse the principle and existing helpers where practical; do not blindly
  duplicate a large generic prompt-budget framework.
- `GitMenuBarTests/AICommitGrouperServiceTests.swift:16-41` asserts file-level
  diff content. Hunk tests at `:208-218` cover response parsing but do not
  assert prompt content or bounded output.
- `AICommitGrouperService.generateHunkGroups` already falls back when the AI
  fails or returns invalid/empty groups. That behavior must remain unchanged.

## Commands and evidence

| Check | Command | Expected result |
|---|---|---|
| Prompt references | `rg -n 'buildHunkGroupingPrompt|AtomicCommitHunk|\.patch|maxDiffCharacters|truncat' GitMenuBar/Services/AI GitMenuBar/Models/GitModels.swift` | Hunk prompt includes bounded patch content and explicit omission markers |
| Focused tests | `make test TEST_FILTER=AICommitGrouperServiceTests` | Prompt-content, ambiguity, cap, and existing parser/fallback tests pass |
| Focused gate | `make agent-check` | Changed lint and build pass |
| Full tests/lint | `make test && make lint` | Existing behavior remains green under the Swift 6.4 baseline |
| Hygiene | `make guidance-check && git diff --check` | Exit 0 |

If the Makefile does not support `TEST_FILTER`, use its documented focused-test
argument or the smallest existing `xcodebuild ... -only-testing` equivalent.

## Suggested executor toolkit

- Use `code-quality` and `swift-conventions` for the narrow prompt change.
- Reuse `AICommitMessageService`'s budget/truncation ideas; prefer a small local
  helper over a new shared abstraction unless the existing helper can be made
  genuinely reusable without changing message behavior.
- Use the existing `StubGroupingAI` test seam; no network calls or credentials.

## Scope

In scope:

- Include each hunk's exact patch content, with its stable ID and metadata, in
  the hunk grouping prompt.
- Apply one deterministic total-character budget (bounded before provider
  invocation), preserve metadata for every hunk, and mark omitted/truncated
  patch content explicitly.
- Keep file ordering, hunk ordering, JSON response format, parser validation,
  fallback groups, and snapshot/index execution semantics unchanged.
- Add tests proving two same-shaped hunks with different patch lines are both
  visible to the model and that oversized input remains bounded and explicit.

Out of scope:

- Changing hunk IDs, patch parsing, snapshot fingerprints, temporary-index
  execution, model/provider selection, or prompt behavior for file-level
  grouping.
- Sending arbitrary persisted patches through the CLI; Plan 072 owns that
  contract design.
- Adding a new dependency or a configurable budget exposed to users.

## Git workflow

Use `fix/atomic-hunk-prompt-context` in an isolated worktree. Use a scoped
Conventional Commit such as `fix(ai): include hunk context in grouping prompt`;
do not push, reset, or rewrite history.

## Ordered implementation steps

### 1. Capture the current prompt contract

Add a focused fixture with at least two hunks that share header/count metadata
but contain distinct changed lines. Record the current prompt omission so the
regression test proves the behavioral gap rather than only checking a new
format.

**Verify:** the fixture uses `AtomicCommitSnapshot`/`AtomicCommitHunk` directly,
contains no credentials, and fails against the pre-fix prompt because the
distinct patch lines are absent.

### 2. Add bounded patch rendering

Extend `buildHunkGroupingPrompt` to render each hunk's patch in a clearly
delimited section below its identity metadata. Use a fixed total budget and a
deterministic allocation/order. Preserve all IDs, headers, and counts even when
patch text is truncated; include a truthful marker with the omitted amount or
at least the fact that content is incomplete. Do not concatenate patches in a
way that loses the hunk ID/path association.

Prefer the existing 40,000-character budget convention. If sharing the exact
allocator would require broad refactoring, use the smallest local bounded
renderer and document why it is intentionally separate. Never emit an
unbounded `snapshot.hunks.map(\.patch)` result.

**Verify:** the generated prompt contains distinctive patch lines, remains
within the selected limit for a large synthetic snapshot, and identifies every
omitted hunk/content segment explicitly.

### 3. Preserve grouping failure behavior

Run the existing hunk generation/parser tests and confirm that AI errors,
invalid JSON, empty groups, duplicate IDs, unknown IDs, and file/hunk overlap
still follow their current fallback or validation paths. Prompt truncation must
not be treated as a valid complete patch by the executor.

**Verify:** no change to hunk IDs, `AtomicCommitPlan` validation, snapshot
fingerprints, or temporary-index execution is required.

### 4. Validate the handoff

Run the Commands and evidence table, inspect prompt output in tests (not in
logs containing credentials), and obtain the required root-session review.
Update this plan and the ledger only after the focused and full checks pass.

**Verify:** the diff contains only prompt/test changes plus any minimal local
helper required for the budget; no provider, CLI, or UI surface changed.

## Test plan

- Distinct same-shaped hunks: prompt contains both exact distinguishing lines.
- Complete small patches: prompt contains the full patch and stable metadata.
- Oversized synthetic snapshot: prompt stays within the fixed budget and emits
  an omission/truncation marker.
- Empty patch or unavailable patch: metadata remains visible and grouping keeps
  its existing fallback behavior.
- Existing hunk response parsing and invalid/duplicate/unknown reference tests.
- `make agent-check`, `make test`, `make lint`, `make guidance-check`, and
  `git diff --check`.

## Done criteria

- Hunk grouping receives real patch context rather than only counts/headers.
- Prompt size is deterministically bounded and truncation is explicit.
- Existing IDs, parser contracts, fallbacks, and execution safety are intact.
- Regression tests fail on the old prompt and pass on the new one.
- Root review accepts the prompt shape and budget tradeoff; all required gates
  pass.

## STOP conditions

- The implementation changes hunk identity or snapshot validation.
- The only proposed fix sends unbounded patches or silently drops context.
- Provider-specific prompt branches or new dependencies are required.
- Existing fallback/error behavior changes without a separate product decision.
- A test requires a live AI provider, credentials, or network access.

## Maintenance notes

If hunk metadata or patch parsing changes later, update this prompt and its
fixtures together. Keep the budget local and observable; do not let a future
model-context increase remove the omission marker or the regression tests.
