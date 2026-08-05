# Plan 057: Establish the Swift 6.2 agent baseline for GitMenuBar

> **Executor instructions**: Read this plan completely before editing. Use an
> isolated branch/worktree and preserve the existing dirty worktree changes;
> this migration is serial and requires a reviewer. Update the plan ledger only
> after the full build/test/lint/guidance gate passes.
>
> **Drift check (run first)**: `git diff --stat 2cb71db..HEAD -- GitMenuBar
> GitMenuBarTests gitmenubar GitMenuBar.xcodeproj .swiftformat .swiftlint.yml
> Makefile scripts AGENTS.md .agents plans`

## Status

- Priority: P0
- Effort: L
- Risk: HIGH
- Depends on: Existing delivery-gate work in plan 015; reconcile current dirty
  source/project changes first
- Category: migration / tooling / concurrency
- Planned at: commit `2cb71db`, 2026-08-05

## Execution profile

- Recommended profile: `implementer`
- Risk/lane: High / Full
- Parallelizable: No. The app, tests, CLI target, Xcode settings, and changed
  file gate share the same migration contract.
- Reviewer required: Yes — Swift 6.2/concurrency, CLI, and release-gate review.
- Rationale: GitMenuBar has the best targeted changed-file workflow in the
  group, but Swift 6.0, inconsistent strict-concurrency settings, and a few
  warning sites prevent it from being the common baseline.
- Escalate when: a compiler fix changes Git operation semantics, requires a
  broad unsafe-concurrency escape, or reaches unrelated dirty files.

## Why it matters

GitMenuBar is the second reference project for agent delivery: it has
`changed-swift-files.sh`, `lint-changed`, `agent-check`, preview checks, and
guidance validation. Its project settings still declare Swift 6.0; Debug uses
targeted strict concurrency while Release is not normalized; and the lint
script mishandles `--help` and currently reports a small warning debt while
exiting 0. This plan keeps the strongest workflow pieces and makes their
quality contract trustworthy under Swift 6.2.

This is **not a config-only change**. Formatter rewrites and Swift 6.2
diagnostics may require source/test/CLI rewrites for actor isolation,
`Sendable`, async boundaries, and lint findings. Only behavior-preserving
migration work is authorized; Git semantics and user-facing behavior must not
be redesigned here.

## Current state

- `GitMenuBar.xcodeproj/project.pbxproj` has six `SWIFT_VERSION = 6.0` entries
  across GitMenuBar, GitMenuBarTests, and the `gitmenubar` CLI target.
- `SWIFT_STRICT_CONCURRENCY = targeted` appears in Debug configurations but is
  not consistently present in Release configurations.
- `.swiftformat` declares Swift 6.0 and four-space formatting.
- `.swiftlint.yml` covers app/tests, uses file thresholds of 500/600, disables
  several length/body rules, and enables useful opt-ins. It needs an explicit
  baseline policy rather than silent warning tolerance.
- `scripts/lint.sh` accepts optional file paths and otherwise checks the full
  app/tests scope. Passing `--help` is treated as a path and does not provide a
  safe help flow. `scripts/lint-fix.sh` masks failures with `|| true`.
- `scripts/changed-swift-files.sh`, `make lint-changed`, and `make agent-check`
  already provide the desired fast loop; preserve and document them.
- Current read-only lint exits 0 but emits warning sites in
  `GitBranchService+Queries.swift` and `CodexUsageParsing.swift`.
- `scripts/validate-agent-guidance.sh` passes. Plan 015 is DONE and is the
  foundation to extend, not a duplicate plan to rerun.
- The repository has no substantive CI workflow for this gate, so the local
  Makefile/agent command contract must be exact and fail closed.

## Commands and evidence

| Check | Command | Expected result |
|---|---|---|
| Toolchain | `swift --version && xcodebuild -version && swiftformat --version && swiftlint version` | Swift 6.2-compatible toolchain; versions recorded in the baseline doc |
| Xcode settings | `rg -n 'SWIFT_VERSION|SWIFT_STRICT_CONCURRENCY|SWIFT_DEFAULT_ACTOR_ISOLATION' GitMenuBar.xcodeproj/project.pbxproj` | All app/test/CLI configurations are 6.2 with normalized explicit concurrency settings |
| Format | `swiftformat --lint --config .swiftformat GitMenuBar GitMenuBarTests gitmenubar` | Exit 0 |
| Full lint | `make lint` | Exit 0, fail closed, no unreviewed warnings |
| Changed lint | `make lint-changed` | Uses tracked/untracked changed Swift files and exits 0 when clean |
| Agent gate | `make agent-check` | Changed lint plus build pass |
| Build/test | `make build && make test` | Exit 0 for app, CLI, and tests as supported by the Makefile |
| Guidance/preview | `make guidance-check && make check-preview` | Exit 0, or a documented environment-only manual handoff for preview |
| Hygiene | `git diff --check` | No whitespace errors |

Commands added or tightened by the plan should be run after their step and
included in the handoff with exact exit status.

## Suggested executor toolkit

- Reuse `swift-conventions` with the GitMenuBar overlay.
- Reuse `delivery-workflow` and the completed plan 015 command surface.
- Use the existing local Swift concurrency/testing specialist skills.
- Use the existing preview/guidance checks; do not build a second agent runner.

## Scope

In scope:

- Set every owned app/test/CLI configuration to Swift 6.2 and complete strict
  concurrency, with explicit actor-isolation policy. Target nonisolated by
  default and explicit `@MainActor` at UI/AppKit/lifecycle boundaries after
  reviewing current semantics.
- Set SwiftFormat to Swift 6.2 and retain four-space formatting/exclusions.
- Remove or remediate current SwiftLint warnings and make the warning/error
  policy explicit. No blanket suppression as a migration shortcut.
- Preserve `changed-swift-files.sh`, improve `lint.sh` help/argument handling,
  keep targeted and full modes, and remove masked verification failures.
- Rewrite Swift in `GitMenuBar/**`, `GitMenuBarTests/**`, and `gitmenubar/**`
  only where Swift 6.2/concurrency/lint/format diagnostics require it.
- Update `AGENTS.md`, `.agents/overlays/`, and
  `docs/adr/0005-swift-6-2-agent-baseline.md` with the common baseline and
  rewrite/exception policy.

Out of scope:

- Git operation semantics, AI behavior, UI redesign, release-signing changes,
  CI expansion, or architectural decomposition unrelated to migration.
- Existing dirty source/project changes outside the migration scope; generated
  artifacts, DerivedData, dependency caches, secrets, and global skills.

## Git workflow

Use `chore/gitmenubar-swift-6-2-baseline` in an isolated worktree. Use scoped
Conventional Commits such as `chore(swift): establish Swift 6.2 agent baseline`;
do not push, reset, or rewrite history. Reconcile the current dirty files before
formatting so no user work is silently rewritten.

## Ordered implementation steps

### 1. Freeze baseline and isolate current changes

Run the drift check, `git status --short`, `git diff --check`, full/changed lint,
build, test, guidance, and preview checks. Record the existing warning sites and
confirm whether the known preview failure is environment-only or a source
regression.

**Verify:** the baseline evidence is reproducible and no unowned file will be
formatted or migrated.

### 2. Normalize all targets and configurations

Set all six owned `SWIFT_VERSION` entries to 6.2. Make complete strict
concurrency explicit in Debug and Release rather than leaving Release weaker
than Debug. Normalize default actor isolation and add explicit `@MainActor` at
UI/menu-bar/lifecycle boundaries; preserve CLI/background Git work off the main
actor.

**Verify:** `rg` shows no owned Swift 6.0/older setting and every app/test/CLI
configuration has the selected values. The project builds far enough to expose
source diagnostics under the new settings.

### 3. Align formatter and lint policy

Change `.swiftformat` to Swift 6.2 and run it in the isolated branch. Review the
mechanical source rewrite. Revisit disabled SwiftLint rules only when they
improve signal; retain generated exclusions and set a fail-closed verification
policy.

**Verify:** full SwiftFormat is clean and SwiftLint has no unreviewed warning
sites. Any temporary exception is listed with path/rule/owner/removal condition.

### 4. Rewrite Swift source, tests, and CLI seams

Build/test in small slices. Fix actor isolation, `Sendable`, async/await, and
lint diagnostics across app, tests, and CLI while preserving Git command
ordering, error handling, and output contracts. Do not paper over diagnostics
with broad `@preconcurrency`, `@unchecked Sendable`, or disabled rules.

**Verify:** `make build`, `make test`, and `make agent-check` pass; each
non-mechanical rewrite maps to a migration diagnostic or selected lint rule.

### 5. Harden the fast agent loop without duplicating it

Keep `scripts/changed-swift-files.sh` as the source of changed-file discovery.
Make `scripts/lint.sh --help` print usage and exit without running tools; keep
explicit path arguments and full-scope fallback. Ensure `lint-changed` handles
the no-changed-file case deterministically. Remove `|| true` from verification
paths while keeping autofix explicitly separate.

**Verify:** targeted lint, full lint, `--help`, no-change, and intentionally
bad-fixture cases all return truthful exit codes and useful agent output.

### 6. Document the shared baseline

Add `docs/adr/0005-swift-6-2-agent-baseline.md` covering compiler settings,
formatter/lint rules, agent command tiers, expected source rewrites, and the
exception/upgrade process. Update `AGENTS.md` and overlays to link to it and
state that `make agent-check` is fast feedback while full lint/build/test is the
merge gate.

**Verify:** a fresh agent can discover the same policy from `AGENTS.md`, the
overlay, the config files, and the baseline decision without copied global
skill text.

### 7. Run final validation and update the ledger

Run the entire Commands and evidence table, inspect the diff, and obtain the
required concurrency/delivery review. Add plan 057 to `plans/README.md` only
after all checks pass.

**Verify:** status contains only approved migration/config/docs/plan files;
the final reviewer confirms no Git behavior change.

## Test plan

- Build app, test, and CLI targets in Debug and Release where supported.
- Run the existing unit tests and add characterization tests only for touched
  concurrency seams.
- Run full and changed SwiftFormat/SwiftLint paths.
- Run `make agent-check`, `make guidance-check`, and `make check-preview`.
- Manually smoke-test menu-bar lifecycle and representative Git operations if
  actor isolation changed those boundaries.

## Done criteria

- All owned Swift targets use Swift 6.2 with complete, normalized concurrency
  settings.
- Formatter and lint gates are clean/fail closed; targeted agent checks work.
- Required source rewrites are behavior-preserving and documented.
- Build, tests, agent, guidance, and preview checks pass or have an explicit
  environment-only handoff.
- Plan 015 is extended, not duplicated; plan 057 and project policy agree.

## STOP conditions

- Current dirty changes cannot be isolated or the live tree differs from the
  drift check.
- The migration requires changing Git semantics, persistence/API contracts, or
  product behavior.
- Broad unsafe concurrency escapes or permanent lint suppressions are proposed.
- A dependency/generated artifact must be edited directly.
- A baseline build/test failure is unrelated and cannot be reproduced cleanly.

## Maintenance notes

Future Swift/Xcode upgrades must update project settings, `.swiftformat`, lint
policy, Make targets/scripts, overlays, and the baseline decision together.
Keep `agent-check` fast and changed-scope; retain the full fail-closed gate for
handoff. Exceptions need an owner and removal condition.
