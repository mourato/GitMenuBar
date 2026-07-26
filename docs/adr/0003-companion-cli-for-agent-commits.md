# Companion CLI for agent commits

Agents in the global delivery workflow commit via plain `git` and often cannot use the menu bar AI commit / atomic-commit surface. We add a **Companion CLI** (`gitmenubar`) in the **same product** (same Xcode project, Keychain service, AI prefs, and Message policy) so agents get controlled commit messages and atomic grouping without a second tool or skill-side message invention when the CLI is ready.

**Status:** accepted (2026-07-26)

## Considered options

- **Skill-only / better prompts** — rejected; does not stop harness authorship pollution or share the app’s grouping/policy.
- **Separate CLI product or repo** — rejected; duplicates credentials, prompts, and policy drift.
- **XPC to a running app** — rejected for v1; agents need the binary with the app quit.
- **Hard-require CLI in global skills** — rejected; soft dependency with fallback when absent or not ready.

## Consequences

- v1 commands: `message`, `commit`, `atomic`; default Propose mode (versioned JSON + stable exit codes); `--apply` only stage + new commits (no amend/rebase/push/reset/force).
- Operate on cwd / `--path`, never the menu bar’s selected repo by default.
- Fail closed when the CLI is ready but AI/policy fails; skill fallback only when CLI is missing or not ready.
- Mid-atomic apply failure stops without automatic rollback; earlier commits remain.
- Binary lives inside the app bundle; `make install-cli` (and later Settings) puts `gitmenubar` on `PATH`.
- No interactive TTY review in v1; humans keep using the menu bar UI.
- Do not invent a parallel usage ledger for the CLI; share the app’s AI path. (`UsageQuotaStore` today is Codex/Cursor **display**, not commit-provider metering — do not misuse it as a commit meter.)
