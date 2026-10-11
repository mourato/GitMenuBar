# Plan 088: Harden sidebar agent-activity badges

> **Executor instructions**: Read this brief, `AGENTS.md`,
> [project workflow facts](../docs/agents/project-workflow.md),
> [architecture guide](../docs/ARCHITECTURE.md), and [UI contract](../docs/ui.md)
> before editing. Work in a dedicated worktree. Follow the steps in order and
> run each verification command. On a STOP condition, stop and report; do not
> widen scope. Leave merge and push to the operator.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MEDIUM
- **Depends on**: uncommitted agent-activity diff on `main` (base for this plan)
- **Category**: feature hardening (sidebar agent badges)
- **Planned at**: commit 8429902 + uncommitted working tree, 2026-10-11
- **Integration**: main; merge and push require explicit operator authorization

## Execution profile

- **Recommended profile**: Standard/full
- **Risk/lane**: MEDIUM (reads other tools' private stores; background polling; store ownership change)
- **Parallelizable**: No; slices touch `ProjectMonitorStore` in sequence
- **Reviewer required**: Yes
- **Rationale**: The first implementation works on the happy path but mixes an unrelated refactor, couples agent data to Git snapshots, polls aggressively, and uses detection heuristics with known false positives (Gemini/T3 Antigravity paths, Cursor IDE helpers) and likely false negatives (Claude native/npm installs).
- **Escalate when**: A harness has no reliable per-project signal; a store schema is undocumented and changes between versions; the change needs a new dependency or entitlement.

## Problem

Review of the agent-activity diff found:

1. **Out-of-scope refactor.** `ProjectStatusReader`/`ProjectStatusPorcelainParser`
   moved to `Services/Git/ProjectStatusReader.swift`, `import Combine` and a doc
   comment removed, and `localizedCaseInsensitiveContains` changed to
   `localizedStandardContains` (behavior change hidden in a move).
2. **Coupling.** `activeAgents` lives in `ProjectStatusSnapshot`, forcing a
   19-parameter memberwise init, `withActiveAgents(_:)`, and a merge hack in
   `ProjectMonitorStore.publishSnapshots` that keeps old agents when a Git
   refresh returns none.
3. **Detection accuracy** (`AgentSessionQuerier`, `AgentActivityDetector`):
   - `checkGeminiRegistry` returns the global `~/.gemini/history` mtime for
     every registered project; Gemini CLI is conflated with Antigravity.
   - `checkProjectLocalGemini` treats `<project>/.gemini` mtime as activity.
   - Default `~/.t3/userdata/providers/antigravity` is a T3 Code path, not
     Antigravity's; slug match uses `contains`, so `-a-b` matches `-a-bc`.
   - `hasPrefix("cursor")` matches Cursor.app and helper processes.
   - Claude via npm runs as `node`; native install execs
     `~/.local/share/claude/versions/<x.y.z>`, so `proc_name` is likely the
     version, not `claude`.
   - Multi-project servers (`codex-app-server`) report launch cwd only.
4. **Cost.** A 10 s timer always runs; each cycle opens the Codex and OpenCode
   SQLite databases once per project and enumerates the Antigravity tree per
   project. `LIMIT 50` is global, so busy projects hide others. The 5 s cache
   never hits with a 10 s timer. Overlapping refreshes are not deduplicated.
5. **Duplication.** `AgentIconCache` copies `ProviderIconRenderer` in
   `UsageQuotaSummaryView.swift`.
6. **Ceremony.** `public`, `@unchecked Sendable` on immutable classes,
   unused `shared`/`forceRefresh`/`clearCache` outside tests.
7. **No opt-in** for reading `~/.claude`, `~/.codex`, `~/.cursor`, OpenCode data.

## Scope

1. Split the unrelated refactor out (revert or separate commit, operator choice).
2. Store agent activity separately: `ProjectMonitorStore.agentActivities:
   [String: [AgentProjectActivity]]`. Remove `activeAgents` from
   `ProjectStatusSnapshot`, its custom init, `withActiveAgents`, and the merge
   hack. Sidebar reads the dictionary by project path.
3. Detection, per harness, only from reliable signals:
   - Running: resolve executable via `proc_pidpath` and argv
     (`sysctl KERN_PROCARGS2`) so `node …/claude-code/cli.js` and versioned
     native binaries classify as Claude Code. Match Cursor only on the agent
     CLI (`cursor-agent`), not Cursor.app or helpers.
   - Recent: Claude/Cursor project directories by exact slug; Codex and
     OpenCode via SQLite with per-row `cwd`/`directory` match.
   - Remove `checkGeminiRegistry`, `checkProjectLocalGemini`, and the
     T3 default path. Keep Antigravity on running-process detection only until
     a documented per-project store exists.
4. Cost: query each database once per cycle for all projects (no global
   `LIMIT` that hides projects; filter by cutoff and group in Swift).
   Discover the Codex state file instead of hardcoding `state_5.sqlite`, or
   fail closed with a log. Run the timer only while the sidebar is visible;
   use `.utility` priority. Drop the dead cache. Coalesce overlapping refreshes
   (in-flight flag or generation check so stale results never overwrite newer).
5. Reuse one SVG icon loader for usage quota and agent badges.
6. Remove `public`, `@unchecked Sendable` where values are immutable, and
   test-only API on production types.
7. Add a Settings toggle "Show agent activity" (default on); when off, no
   timer and no file or database reads.

Out of scope: new harnesses, per-session detail UI, click actions on badges,
network calls, new dependencies, sandbox changes.

## Invariants

- Git snapshot refresh behavior and `ProjectStatusSnapshot` shape match
  commit 8429902.
- No reads of other tools' data when the toggle is off.
- Detection never writes to other tools' stores; SQLite opened read-only.
- Badge row never truncates the project name below its current minimum.

## Steps

1. Drift check: `git status` and `git diff --stat` match the reviewed diff.
2. Slice 1: isolate the `ProjectStatusReader` move (operator decides keep as
   separate commit or revert). `make agent-check`.
3. Slice 2: move agent data to the store dictionary; delete snapshot plumbing.
   Add a `ProjectMonitorStore` test: Git refresh does not clear agents; agent
   refresh does not touch Git snapshots.
4. Slice 3: detection fixes with tests per harness (fixture directories and
   temporary SQLite files; process classifier tests with argv samples for
   npm and native Claude, `cursor-agent`, Cursor helpers).
5. Slice 4: cost and scheduling (single DB open per cycle, visibility-gated
   timer, coalescing). Test that stale results are discarded.
6. Slice 5: shared icon loader, Sendable/public cleanup, Settings toggle.
7. Manual check with app running: start Claude Code, Codex, OpenCode in two
   projects; confirm badges, tooltips, VoiceOver labels, and no badge on
   projects only opened in Cursor IDE or registered in Gemini.

## Verification

- `make agent-check`
- `make test-focused TEST_FILTER="GitMenuBarTests/AgentActivityDetectorTests GitMenuBarTests/AgentSessionQuerierTests GitMenuBarTests/ProjectMonitorStoreTests"`
- `make test`
- Manual check from Step 7; record results and any harness left undetected.

## STOP conditions

- A harness's store schema cannot be confirmed locally; drop that harness's
  "recent" signal and report.
- Visibility gating needs AppKit shell changes beyond observing sidebar
  presence.
- Any change alters Git refresh results or timing outside agent code.
