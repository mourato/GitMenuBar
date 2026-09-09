# Plan 038: Install Companion CLI on PATH + soft-dep workflow docs

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 42cde45..HEAD -- Makefile scripts GitMenuBar/Pages/Settings .agents/overlays/delivery-workflow.md AGENTS.md plans/038-companion-cli-install-and-workflow.md`
> Confirm Plan 037 DONE (binary `gitmenubar` exists in build/app bundle). If not, STOP.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/037-companion-cli-commands.md
- **Category**: dx
- **Planned at**: commit `42cde45`, 2026-07-26

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: `no`
- **Reviewer required**: `yes` — PATH install + Settings action + workflow contract for agents
- **Rationale**: Crosses packaging, Settings UI, and delivery guidance; Medium, not Low/Fast.
- **Escalate when**: Homebrew formula, notarization pipeline changes, or editing global skills outside this repo without an operator-approved handoff note.

## Why this matters

A Companion CLI that agents cannot find on `PATH` does not change the global workflow. This plan installs `gitmenubar` from the app bundle into `~/.local/bin`, exposes an in-app Install action, and documents the Soft dependency for delivery skills (in-repo overlay + operator handoff for global skill files).

## Current state

- ADR 0003: binary inside `.app`; `make install-cli` + Settings install; Soft dependency (not hard-require).
- Makefile today: build/test/lint/dmg/setup — no install-cli (`Makefile` `.PHONY` list).
- Overlay: `.agents/overlays/delivery-workflow.md` — make targets and merge gates only.
- Global skills (`ship-ship`, `delivery-workflow` core, Cursor commit rules) live **outside** this repo; this plan must not silently edit `~/.claude` unless the operator’s environment is explicitly in scope — prefer an in-repo handoff snippet.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `make build` / `make build-release` as needed | exit 0 |
| Install | `make install-cli` | symlink/copy on `~/.local/bin/gitmenubar`; `command -v gitmenubar` works if `~/.local/bin` is on PATH |
| Lint/UI | `make agent-check` | exit 0 |
| Guidance | `make guidance-check` | exit 0 |
| Tests | `make test` | exit 0 |

## Suggested executor toolkit

- `global:delivery-workflow` + project overlay
- `global:macos-app-engineering` / `menubar` only if Settings control patterns need alignment
- `ux-writing` for the Settings button label/help string

## Scope

**In scope**:
- `Makefile` target `install-cli` (+ `help` text); optional `uninstall-cli`
- `scripts/install-cli.sh` (or equivalent) that locates built/installed `GitMenuBar.app`’s `Contents/MacOS/gitmenubar` (document search order: `dist/`, `/Applications/`, derived data path used by `run-build.sh`) and symlinks to `$(HOME)/.local/bin/gitmenubar`
- Settings UI control: “Install CLI” (AI or General pane — prefer AI pane next to commit generation) that runs the same install logic or opens instructions if app-translocated; include short help caption
- `#Preview` if a new View file is introduced (AGENTS.md SwiftUI Preview Policy)
- Update `.agents/overlays/delivery-workflow.md` with Soft dependency behavior for commits when `gitmenubar` is on PATH
- Add `docs/companion-cli-agent-soft-dep.md` (short) with copy-paste guidance for updating **global** `ship-ship`, `delivery-workflow`, and Cursor commit rules — do not require those files to change inside this PR if they are outside the repo
- `AGENTS.md` one-line pointer under Command Surface: `make install-cli`
- `plans/README.md` status for 038

**Out of scope**:
- Changing CLI JSON schema / subcommands (037)
- Homebrew tap
- Hard-failing CI if CLI missing
- Implementing the global skill edits in `~/.claude` unless operator explicitly asks in the same task

## Git workflow

- Branch: `feat/038-companion-cli-install-and-workflow`
- Conventional Commits; no push/PR unless asked

## Steps

### Step 1: `make install-cli`

Implement script + Makefile target:

- Create `~/.local/bin` if needed
- Symlink preferred over copy so app updates are picked up when the app bundle path is stable; if symlink to DerivedData is too fragile, copy from Release app in `/Applications` or `dist/` and document `make install-cli` after `make build-release` / DMG install
- Idempotent re-run
- Print clear errors if binary missing (“build/install the app first”)

**Verify**: after a local build that includes the CLI binary, `make install-cli` exits 0 and `~/.local/bin/gitmenubar --help` works (PATH may need `export PATH="$HOME/.local/bin:$PATH"` in the verify command).

### Step 2: Settings “Install CLI”

- Add a button + footer help in Settings (AI pane preferred).
- On success, show a brief confirmation (existing alert/toast patterns if any; else `NSAlert` / simple state string).
- Do not require App Sandbox exceptions you cannot justify — if blocked, STOP and report.

**Verify**: `make agent-check` → exit 0; new/changed UI file has `#Preview`.

### Step 3: Soft dependency documentation

Update overlay + add `docs/companion-cli-agent-soft-dep.md` describing:

1. If `command -v gitmenubar` && ready → use Propose then `--apply` only when the user asked to commit
2. If missing/not ready → existing `git` + agent message fallback
3. If ready but AI/policy fails → **fail closed** (no agent-invented message)
4. Surfaces: `ship-ship`, `delivery-workflow`, Cursor commit-on-request rule

**Verify**: `make guidance-check` → exit 0; `rg -n "install-cli|gitmenubar|Soft dependency" AGENTS.md .agents/overlays/delivery-workflow.md docs/companion-cli-agent-soft-dep.md` finds the pointers.

### Step 4: Index

Mark 038 DONE in `plans/README.md`.

## Test plan

- Script smoke: install when binary present / fail when absent (can be a small shell assertion in the PR description or a `scripts/` check run manually — optional `tests` only if the repo already tests scripts).
- No new network AI tests.
- UI: preview compiles.

## Done criteria

- [ ] `make install-cli` documented in `Makefile` help and `AGENTS.md`
- [ ] Settings Install CLI control exists with preview coverage if new view file
- [ ] Overlay + `docs/companion-cli-agent-soft-dep.md` describe Soft dependency accurately per ADR 0003
- [ ] `make agent-check`, `make guidance-check`, `make test` exit 0
- [ ] `plans/README.md` 038 status updated

## STOP conditions

- Plan 037 binary not findable in app bundle or build products.
- Sandbox/translocation prevents install from Settings — report rather than shipping a broken button.
- Operator demands hard-requiring CLI in CI — conflicts with ADR; stop.

## Maintenance notes

- After merge, operator should paste soft-dep into global `ship-ship` / delivery-workflow / Cursor rules using the docs snippet.
- DMG release checklist (release-management skill) should eventually mention `install-cli` / Settings install — deferred unless editing that skill is requested.
- Reviewers: ensure symlink does not point at world-writable temp paths in the documented happy path.
