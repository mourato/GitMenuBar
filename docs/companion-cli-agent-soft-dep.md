# Companion CLI soft dependency (agent handoff)

Use this snippet when updating **global** delivery skills outside this repository (`ship-ship`, `delivery-workflow`, Cursor commit-on-request rules). Do **not** hard-require the CLI in CI or agent routing.

Reference: [ADR 0003](adr/0003-companion-cli-for-agent-commits.md), `CONTEXT.md` (Soft dependency vocabulary).

## Install on PATH

From the GitMenuBar repo:

```sh
make install-cli
# ensure ~/.local/bin is on PATH
export PATH="$HOME/.local/bin:$PATH"
command -v gitmenubar
```

Or use **Settings → AI → Install CLI** in the app (symlinks `~/.local/bin/gitmenubar` to the running app bundle’s binary).

## Soft dependency contract

When an agent is asked to **commit** (and only then):

1. **CLI on PATH and ready** (`command -v gitmenubar` succeeds; `gitmenubar message` / `commit` / `atomic` Propose mode works):
   - Use the Companion CLI for Propose (JSON + stable exit codes).
   - Use `--apply` **only** when the user explicitly asked to commit (stage + new commits; no amend/rebase/push/reset/force).
2. **CLI missing or not ready** (not on PATH, no providers/keys, repo invalid):
   - Fall back to plain `git` and the agent’s own commit message flow.
   - Tell the user the CLI is unavailable and how to install (`make install-cli` or Settings → Install CLI).
3. **CLI ready but AI or Message policy fails** (non-zero exit, policy rejection):
   - **Fail closed** — do not invent or substitute a commit message in the skill/harness.
   - Surface the CLI error; stop without `--apply`.

Propose-only tasks may use the CLI when available; do not `--apply` unless the user requested a commit.

## Surfaces to update (operator paste)

Add a short **Companion CLI (soft dependency)** subsection to:

| Surface | Location (typical) |
|---------|-------------------|
| `ship-ship` | Commit step: check `command -v gitmenubar`, Propose vs `--apply` gate, fail closed on policy/AI errors |
| `delivery-workflow` | Verification/commit guidance: optional `make install-cli`; same three-way branch as above |
| Cursor commit-on-request rule | When user asks to commit: prefer CLI if on PATH and ready; fallback to git; never invent message if CLI failed while ready |

Project overlay (in-repo, already maintained): `.agents/overlays/delivery-workflow.md`.

## Example commit-on-request flow (pseudocode)

```text
if user did not ask to commit:
  use git / CLI Propose only as needed; never --apply
else if command -v gitmenubar && repo ready:
  run gitmenubar … (Propose)
  if success && user asked to commit:
    run gitmenubar … --apply
  else if CLI error while ready:
    STOP — report CLI error; do not write git commit -m …
else:
  git add / git commit with agent message; mention make install-cli
```

## Out of scope for this handoff

- Homebrew formula or DMG PATH hooks
- Hard-failing CI when `gitmenubar` is absent
- Changing CLI subcommands or JSON schema (see plans 037+)
