# Plan 036: Add shared CLI session + Commit Message policy

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 42cde45..HEAD -- GitMenuBar/Services/AI GitMenuBar/Models/AIModels.swift GitMenuBar/Services/Credentials GitMenuBar/Services/Git Makefile plans/036-companion-cli-session-and-message-policy.md CONTEXT.md docs/adr/0003-companion-cli-for-agent-commits.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: direction
- **Planned at**: commit `42cde45`, 2026-07-26

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: `no`
- **Reviewer required**: `yes` — credentials/Keychain path shared with a future CLI; message policy is a product contract
- **Rationale**: New shared non-UI session over AI + Keychain is ambiguous and security-adjacent; not a Low/Fast tweak.
- **Escalate when**: scope expands into ArgumentParser CLI target, Xcode CLI product, or rewriting `AICommitCoordinator` UI wiring beyond a thin shared helper.

## Why this matters

The menu bar already generates Conventional Commit messages and atomic groups, but agents cannot call that path. Before a Companion CLI exists, the app needs a **non-UI session** that resolves repo path + AI readiness + generation, plus a product-owned **Message policy** that strips/rejects harness authorship pollution. Plan 037 builds the `gitmenubar` binary on top of this; without it, the CLI would duplicate coordinator logic or skip policy.

## Current state

- Vocabulary (must use these names in types/docs): see `CONTEXT.md` — Companion CLI, Propose mode, Apply mode, Message policy, Harness authorship pollution, Atomic commit group, Soft dependency, Repository path scope. ADR: `docs/adr/0003-companion-cli-for-agent-commits.md`.
- Targets today: app + unit tests only (`GitMenuBar.xcodeproj` — `com.apple.product-type.application` and unit-test bundle). No CLI target yet.
- `AICommitCoordinator` (`GitMenuBar/Services/AI/AICommitCoordinator.swift`) is `@MainActor` `ObservableObject` and owns `generateMessage`, `generateAtomicGroups`, `isReadyForGeneration`.
- Keychain service string is `com.mourato.GitMenuBar` (`AIKeychainStore`).
- Prefs: `AICommitPreferences.defaultScopeMode` defaults to `.stagedWithFallbackAll` (`GitMenuBar/Models/AIModels.swift`).
- Atomic execution: `GitAtomicCommitService.performAtomicCommitsAsync` / `commitAtomicGroupAsync`.
- `UsageQuotaStore` is Codex/Cursor **display** only — do **not** hook commit generation into it in this plan.

Excerpt — readiness:

```143:152:GitMenuBar/Services/AI/AICommitCoordinator.swift
    var isReadyForGeneration: Bool {
        guard let provider = providerStore.defaultProvider else {
            return false
        }

        let hasAPIKey = !resolvedAPIKey(for: provider).isEmpty
        let hasModel = !providerStore.effectiveDefaultModel().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return hasAPIKey && hasModel
    }
```

Excerpt — prefs:

```132:141:GitMenuBar/Models/AIModels.swift
struct AICommitPreferences: Codable, Equatable {
    var defaultProviderId: UUID?
    var defaultModel: String
    var defaultScopeMode: AICommitDefaultScopeMode

    static let `default` = AICommitPreferences(
        defaultProviderId: nil,
        defaultModel: "",
        defaultScopeMode: .stagedWithFallbackAll
    )
}
```

Conventions: Foundation services under `GitMenuBar/Services/`; XCTest under `GitMenuBarTests/`; match existing AI test style (see `GitMenuBarTests/GitManagerAtomicCommitTests.swift` for git-facing tests). Prefer small types without SwiftUI imports.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift | `git diff --stat 42cde45..HEAD -- <in-scope paths>` | empty or reviewed |
| Lint/build | `make agent-check` | exit 0 |
| Tests | `make test` | exit 0 |
| Guidance | `make guidance-check` | exit 0 |

## Suggested executor toolkit

- `global:swift-conventions` + project overlay when naming/layout
- `security-credentials` (local skill) when touching Keychain account/service strings
- `swift-testing-expert` / existing XCTest patterns for new tests

## Scope

**In scope**:
- `GitMenuBar/Services/AI/` — add Message policy + non-UI session/facade types (new files OK)
- `GitMenuBar/Models/` — only if prefs need a Codable policy config struct
- `GitMenuBarTests/` — unit tests for Message policy + session readiness mapping
- Wire **optional** use of Message policy from existing generate paths in `AICommitMessageService` sanitizing **or** coordinator post-process (minimal hook so app + future CLI share one gate)
- `plans/README.md` status row for 036
- Do **not** add ArgumentParser, CLI target, `make install-cli`, or Settings Install UI (those are 037/038)

**Out of scope**:
- New Xcode CLI / tool target
- Global skill edits under `~/.claude` / Cursor user rules
- Amend/rebase/push APIs
- Interactive TTY
- Changing `UsageQuotaStore` / Codex-Cursor quota UI
- Extracting a full `GitMenuBarCore` framework unless shared-source compile fails — prefer new types in the app target first; STOP if you believe a separate framework is required

## Git workflow

- Branch: `feat/036-companion-cli-session-and-message-policy`
- Commits: Conventional Commits matching recent log (e.g. `feat(ai): …`, `test(ai): …`)
- Do NOT push or open a PR unless the operator asks

## Steps

### Step 1: Add Message policy types

Create something like `GitMenuBar/Services/AI/CommitMessagePolicy.swift` (name may vary; keep “Message policy” in docs/comments per CONTEXT):

- Built-in denylist patterns for harness authorship pollution (e.g. lines/trailers that force “Generated by …”, “Co-authored-by: harness…”, similar — keep the list small and documented in code comments).
- Allowlist for intentional trailers (at least `Signed-off-by:`).
- API shape (suggested): `func sanitize(_ message: String) -> Result<String, CommitMessagePolicyError>` or `(accepted: String?, rejection: …)` — **reject** if after strip the message is empty or still violates policy; do not silently invent a replacement message.
- Optional Codable prefs blob for future Settings editing is OK but **not required** in UI this plan; built-in defaults must work offline.

**Verify**: `rg -n "CommitMessagePolicy|Message policy" GitMenuBar/Services/AI` → finds the new type.

### Step 2: Add non-UI session/facade

Create a Foundation type (e.g. `GitMenuBarCommitSession`) that:

1. Takes an absolute **Repository path scope** (directory); resolves git root (reuse existing git helpers / `GitManager` patterns — do not invent a second git runner).
2. Loads `AIProviderStore` + `AIKeychainStore(service: "com.mourato.GitMenuBar")` the same way the app does.
3. Exposes readiness equivalent to `isReadyForGeneration` / `generationDisabledReason` without requiring SwiftUI.
4. Can generate a commit message and atomic groups by delegating to existing `AICommitMessageService` / `AICommitGrouperService` / `GitManager` (construct what you need; avoid depending on `StatusBarController`).
5. Runs generated messages through Message policy before returning.

Keep `@MainActor` only if existing stores force it; document actor assumptions. Do **not** create a second Keychain service name.

**Verify**: `make agent-check` → exit 0.

### Step 3: Hook policy into the existing app generate path

After AI returns a message (in sanitizing extension or coordinator), run Message policy so the menu bar and future CLI share one gate. On rejection, surface a clear error (fail closed) — do not fall back to the raw polluted string.

**Verify**: existing AI/commit tests still compile; `make agent-check` → exit 0.

### Step 4: Unit tests

Add `GitMenuBarTests/CommitMessagePolicyTests.swift` (name flexible):

- strips a denylisted harness line and keeps the Conventional Commit subject
- rejects when only pollution remains
- keeps allowlisted `Signed-off-by:`
- (optional) session readiness returns not-ready when no provider/key — use fakes/mocks if the suite already has AI test doubles; if constructing real Keychain is unsafe in tests, test policy thoroughly and session with injected stores only

**Verify**: `make test` → exit 0, new tests run.

### Step 5: Index

Update `plans/README.md` row for 036 to DONE (or IN PROGRESS while landing).

**Verify**: `make guidance-check` → exit 0.

## Test plan

- New `CommitMessagePolicyTests` as above.
- Pattern: existing XCTest files under `GitMenuBarTests/` (simple `XCTestCase`, `#expect` only if the suite already uses Swift Testing — match neighbors).
- `make test` must pass.

## Done criteria

- [ ] `make agent-check` exits 0
- [ ] `make test` exits 0 with new Message policy tests
- [ ] No CLI target / ArgumentParser added
- [ ] Keychain service remains `com.mourato.GitMenuBar`
- [ ] `UsageQuotaStore` untouched
- [ ] `plans/README.md` 036 status updated
- [ ] Types/docs use CONTEXT vocabulary (Companion CLI deferred to 037; Message policy + session exist)

## STOP conditions

- Drift in cited `AICommitCoordinator` / Keychain / prefs excerpts cannot be reconciled.
- Sharing AI stores requires a new Keychain service or access-group redesign.
- You conclude a separate framework target is mandatory for compile — stop and report (037 can revisit).
- Scope creeps into shipping `gitmenubar` binary or install scripts.

## Maintenance notes

- Plan 037 will call this session from ArgumentParser commands.
- Reviewers: ensure policy fail-closed behavior and no secret logging of API keys.
- Settings UI to edit denylist/allowlist is deferred; built-in list must be easy to extend.
