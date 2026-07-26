# Plan 037: Ship Companion CLI (`gitmenubar`) Propose/Apply commands

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 42cde45..HEAD -- GitMenuBar.xcodeproj GitMenuBar/Services/AI GitMenuBar/Services/Git Makefile scripts plans/037-companion-cli-commands.md`
> Also confirm Plan 036 types exist (`rg -n "CommitMessagePolicy|GitMenuBarCommitSession" GitMenuBar || true`). If 036 is not DONE, STOP.

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: plans/036-companion-cli-session-and-message-policy.md
- **Category**: direction
- **Planned at**: commit `42cde45`, 2026-07-26

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `High/Full`
- **Parallelizable**: `no`
- **Reviewer required**: `yes` — new executable target, git mutation surface, AI credentials from CLI, JSON contract for agents
- **Rationale**: Product CLI with `--apply` is high-risk architecture and security-adjacent.
- **Escalate when**: notarization/signing redesign, XPC to running app, or porcelain parity (`push`/`branch`) is requested.

## Why this matters

Agents need a PATH-callable Companion CLI that proposes atomic/AI commits as versioned JSON and applies only when asked — without opening the menu bar, without inventing messages when ready, and without amend/force. This plan ships the `gitmenubar` binary and command contract defined in ADR 0003.

## Current state

- ADR: `docs/adr/0003-companion-cli-for-agent-commits.md`
- CONTEXT terms: Companion CLI, Propose mode, Apply mode, Message policy, Soft dependency, Repository path scope
- After 036: shared session + Message policy in the app target (exact type names from 036 — re-read before coding)
- Xcode: only `GitMenuBar` app + `GitMenuBarTests`. SPM: KeyboardShortcuts + Settings only — **no** ArgumentParser yet
- Makefile has no `install-cli` (that is Plan 038)

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build app | `make build` | exit 0 |
| Tests | `make test` | exit 0 |
| Lint | `make lint-changed` / `make agent-check` | exit 0 |
| Guidance | `make guidance-check` | exit 0 |
| CLI help (after build) | path-to-built `gitmenubar --help` | prints subcommands |

## Suggested executor toolkit

- `global:macos-app-engineering` for target/signing basics
- `global:swift-conventions`
- `security-credentials` for Keychain use from a second binary
- `test-strategy` for CLI contract tests

## Scope

**In scope**:
- New Xcode **command-line tool** target producing binary named `gitmenubar` (product name / executable name must be `gitmenubar`)
- Add Apple `swift-argument-parser` SPM dependency for the CLI target only (app target must not need it)
- Share sources with the session/policy/AI/Git services from 036 (target membership or thin internal library — prefer membership; STOP if a framework extract is required and report)
- Subcommands: `message`, `commit`, `atomic`
- Flags: `--path <dir>` (Repository path scope; default cwd), `--staged` / `--all` overriding prefs scope, `--json` (default for agent-oriented output), `--plain`, `--apply`, `--message <text>` escape hatch (still runs Message policy)
- Propose mode default; `--apply` performs stage + new commits only
- Versioned JSON schema (`schemaVersion` field, start at `1`) for propose output
- Stable exit codes: `0` ok, `2` not ready, `3` invalid repo, `4` policy rejected, other non-zero for AI/git failures (document in `--help` or a small `GitMenuBar/CLI/ExitCode.swift`)
- Mid-atomic failure: stop, no automatic reset; JSON/stderr lists completed vs remaining groups
- Refuse `--apply` when `.git/index.lock` exists
- Unit/process tests for argument parsing, exit code mapping, and policy-on-`--message`
- `plans/README.md` status for 037

**Out of scope**:
- `make install-cli`, DMG PATH install, Settings “Install CLI” (Plan 038)
- Global skill patches under `~/.claude` (038 documents them)
- Interactive TTY review sheets
- `push`, `pull`, `branch`, `amend`, `rebase`, `reset`, `force`
- Human-oriented progress UI beyond stderr

## Git workflow

- Branch: `feat/037-companion-cli-commands` (from main after 036 merges, or stacked on 036 if operator says so)
- Conventional Commits; do not push/PR unless asked

## Steps

### Step 1: Confirm 036 landed

**Verify**: `rg -n "struct CommitMessagePolicy|class CommitMessagePolicy|enum CommitMessagePolicy" GitMenuBar` and session type from 036 exist; else STOP.

### Step 2: Add ArgumentParser package + CLI target

- Add `swift-argument-parser` via Xcode SPM to the project; link **only** the CLI target.
- Create target (suggested folder `GitMenuBarCLI/` or `CLI/`) with `@main` struct.
- Ensure Release/Debug build of the tool lands under the existing `.xcode-build` conventions if possible; otherwise document the product path in Makefile comments for 038.
- Embed or build the tool as a sibling product; bundling **into** `.app/Contents/MacOS/gitmenubar` may be a Copy Files phase — do it here if straightforward, else produce the binary and leave PATH install to 038 (prefer Copy Files into the app bundle so ADR “binary inside app” holds).

**Verify**: `xcodebuild -list` (or project open) shows the new target; `make build` still builds the app (exit 0).

### Step 3: Implement `message` / `commit` / `atomic`

Behavior contract:

| Command | Propose (default) | `--apply` |
|---------|-------------------|-----------|
| `message` | Print generated message (JSON: `{schemaVersion,message}` or plain) | N/A or same as propose (no git write) |
| `commit` | JSON plan for one commit (files/scope + message) | Stage+commit once |
| `atomic` | JSON plan of Atomic commit groups | Commit groups in order; stop on first failure |

- Use 036 session for readiness + generation + policy.
- `--message` skips AI generation but **must** pass Message policy; on reject → exit `4`.
- Not ready → exit `2` with stderr reason (and JSON error object if `--json`).
- Invalid git path → exit `3`.
- Never read the menu bar’s selected repository from app state.

**Verify**: built binary `--help` lists the three subcommands; a dry invoke on a non-git dir exits `3`.

### Step 4: Tests

- Parser/exit-code unit tests without network where possible.
- Policy rejection on `--message` with denylisted-only text → exit `4` (subprocess test or invoke internal entrypoints).
- Do not call real paid AI APIs in CI; mock session or inject fakes.

**Verify**: `make test` → exit 0.

### Step 5: Wire build + docs in-repo

- Ensure `make build` / `make agent-check` build the CLI product (extend `scripts/run-build.sh` only if required; keep changes minimal).
- Short developer note in plan README section (not a new user markdown doc unless needed).

**Verify**: `make agent-check` → exit 0; `make guidance-check` → exit 0.

## Test plan

- Exit code matrix tests (2/3/4/0 paths with fakes).
- JSON `schemaVersion == 1` present on propose success.
- Atomic stop-without-rollback covered with a fake git layer **or** documented manual STOP if faking is impossible — prefer a test double around commit apply.
- Pattern neighbors: `GitMenuBarTests/GitManagerAtomicCommitTests.swift`.

## Done criteria

- [ ] `gitmenubar` binary builds; `--help` shows `message|commit|atomic`
- [ ] Default is Propose mode; `--apply` mutates only via stage+commit
- [ ] Exit codes 2/3/4 behavior implemented and tested
- [ ] Message policy applied to AI and `--message` paths
- [ ] No install-cli / Settings install yet
- [ ] `make test` and `make agent-check` exit 0
- [ ] `plans/README.md` 037 status updated

## STOP conditions

- Plan 036 missing.
- Codesigning/Keychain prevents CLI from reading `com.mourato.GitMenuBar` items — report; do not invent a second key store.
- Requested to add push/amend to unblock agents — refuse and report (ADR forbids).
- Copy-into-`.app` is blocked by project structure — report options; do not silently ship only an orphan binary without noting 038 impact.

## Maintenance notes

- Schema bumps must stay backward compatible or bump `schemaVersion` and update Soft dependency skills (038).
- Reviewers: verify no secrets in JSON output; API keys never printed.
- Plan 038 owns PATH installation and global skill soft-dep text.
