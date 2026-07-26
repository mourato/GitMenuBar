# Companion CLI soft dependency (agent handoff)

Use this snippet when updating **global** delivery skills outside this repository (`ship-ship`, `delivery-workflow`, Cursor commit-on-request rules). Do **not** hard-require the CLI in CI or agent routing.

Reference: [ADR 0003](adr/0003-companion-cli-for-agent-commits.md), `CONTEXT.md` (Soft dependency vocabulary), `CompanionCLIExitCode` in the app/CLI.

## Install on PATH

From the GitMenuBar repo:

```sh
make install-cli
# ensure ~/.local/bin is on PATH
export PATH="$HOME/.local/bin:$PATH"
command -v gitmenubar
```

Or use **Settings → AI → Install CLI** in the app (symlinks `~/.local/bin/gitmenubar` to the running app bundle’s `Contents/Helpers/gitmenubar`). Settings install refuses App Translocation and other unstable bundle paths — copy the app to `/Applications` and reopen first.

> **Note:** The CLI must live under `Contents/Helpers/`, not `Contents/MacOS/`. On case-insensitive APFS, `MacOS/gitmenubar` collides with `MacOS/GitMenuBar` and overwrites the GUI executable.

## Soft dependency contract

When an agent is asked to **commit** (and only then):

1. **CLI on PATH and ready** (`command -v gitmenubar` succeeds; Propose exits `0`):
   - Use the Companion CLI for Propose (JSON + stable exit codes).
   - Use `--apply` **only** when the user explicitly asked to commit (stage + new commits; no amend/rebase/push/reset/force).
2. **CLI missing or not usable** — fall back to plain `git` and the agent’s own commit message flow; mention install:
   - CLI not on PATH.
   - Exit `2` (`notReady`) — missing AI provider, API key, or model.
   - Exit `3` (`invalidRepository`) — cwd/`--path` is not a valid Git repo scope.
3. **CLI ready but Propose failed after a ready attempt** — **fail closed** (do not invent or substitute a commit message):
   - Exit `4` (`policyRejected`) — Message policy rejected the draft.
   - Exit `1` (`operationalFailure`) — operational error after the CLI was ready (I/O, Git, unexpected failure).
   - Surface the CLI error; stop without `--apply`.

Propose-only tasks may use the CLI when available; do not `--apply` unless the user requested a commit.

## Exit codes (`CompanionCLIExitCode`)

| Code | Name | Agent branch |
|------|------|--------------|
| `0` | success | Propose succeeded; `--apply` only if user asked to commit |
| `1` | operationalFailure | Fail closed when CLI was ready |
| `2` | notReady | Fallback to plain `git` |
| `3` | invalidRepository | Fallback to plain `git` |
| `4` | policyRejected | Fail closed when CLI was ready |

## Surfaces to update (operator paste)

| Surface | Status |
|---------|--------|
| Global `ship-ship` (`~/.agents/core/skills/ship-ship`) | Updated in core skill + `references/ship-protocol.md` |
| Global `delivery-workflow` (`~/.agents/core/skills/delivery-workflow`) | Updated in portable rules |
| GitMenuBar Cursor rule | `.cursor/rules/companion-cli-soft-dep.mdc` (project) |
| Cursor **User Rules** (Settings UI) | Optional global paste — Cursor has no stable file API; use the contract above if you want the soft-dep outside GitMenuBar projects |

Project overlay (in-repo): `.agents/overlays/delivery-workflow.md`.

## Example commit-on-request flow (pseudocode)

```text
if user did not ask to commit:
  use git / CLI Propose only as needed; never --apply
else if command -v gitmenubar:
  run gitmenubar … (Propose); capture exit code
  if exit 0 && user asked to commit:
    run gitmenubar … --apply
  else if exit 2 or exit 3:
    git add / git commit with agent message; mention make install-cli or fix repo scope
  else if exit 1 or exit 4:
    STOP — report CLI error; do not write git commit -m …
  else:
    STOP — unexpected exit; do not invent a commit message
else:
  git add / git commit with agent message; mention make install-cli
```

## Out of scope for this handoff

- Homebrew formula or DMG PATH hooks
- Hard-failing CI when `gitmenubar` is absent
- Changing CLI subcommands or JSON schema (see plans 037+)
