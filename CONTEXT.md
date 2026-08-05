# GitMenuBar

Native macOS menu-bar Git client with a companion CLI for agent-driven commit
flows that share the app’s AI and message policy. This glossary records product
language for GitMenuBar surfaces; keep it free of implementation detail.

## Language

**AI provider credential**:
The API credential shared by product surfaces that call the same AI backend.
It remains distinct from the AI usage quotas and AI Commit Generation surfaces.

### Product surfaces

**AI usage quotas**:
The monitored AI quota surface in the main panel (Settings → AI → Usage Quotas),
distinct from AI Commit Generation. Each **Usage Provider** (Codex, Cursor,
OpenRouter) publishes one **Snapshot**: last successful non-secret quota reading.
_Avoid_: quota as part of AI commit generation, usage meter, AI status

**Credit Balance**:
The OpenRouter quota measurement: monetary credits on the account
(`total credits purchased − total usage`), shown as a remaining percent of
purchased credits plus a `$` balance. Unlike Codex/Cursor it has no reset
window, so the card shows no reset countdown.
_Avoid_: window, reset (for OpenRouter), token budget

**Companion CLI**:
The shell-facing product binary `gitmenubar`, shipped with the macOS app and intended primarily for agents. It is the same product as the menu bar app, not a separate tool.
_Avoid_: GitMenuBar CLI tool (as a different product), agent git helper, standalone commit CLI

**Propose mode**:
The default CLI mode that prints a versioned structured plan (groups, files, messages) without mutating the repository.
_Avoid_: dry-run (unless as a synonym in flags), preview-only, plan mode

**Apply mode**:
The explicit CLI mode that stages and creates new commits from a propose result or equivalent inputs.
_Avoid_: execute, commit-now, write mode

### Commit authorship

**Message policy**:
Product-owned rules that generate, sanitize, and accept or reject commit message text (including harness authorship pollution), shared by app and Companion CLI.
_Avoid_: skill-side strip, harness scrubber (as a skill concern), commit linter (generic)

**Harness authorship pollution**:
Forced attribution or trailer text injected into commit messages by an agent harness or wrapper, outside Conventional Commit intent.
_Avoid_: co-author trailer (when intentionally allowlisted), Signed-off-by (when allowlisted)

**Atomic commit group**:
A reviewed unit of one or more file paths plus one commit message intended to become a single commit in sequence.
_Avoid_: patch set, hunk group, logical commit (as a synonym in code names)

### Workflow integration

**Monitored Project**:
A local project that GitMenuBar keeps in its Projects surface so its Git attention state can be scanned alongside other projects. Monitoring is local app metadata; it does not rename, move, fetch, push, pull, or otherwise mutate the repository by itself.
_Avoid_: watched repo, tracked repo, workspace, recent project (when monitoring intent is meant)

**Attention State**:
The compact project-level Git state that tells whether a Monitored Project needs developer action, is clean, is unavailable, or is still refreshing. It summarizes Git facts for scanning; it is not a replacement for the selected project's full working-tree view.
_Avoid_: health status, repo score, notification state

**Soft dependency**:
Optional use of the Companion CLI from global delivery skills when the binary is on `PATH` and AI generation is ready; otherwise fall back to plain `git` without failing the harness setup.
_Avoid_: hard requirement, mandatory gitmenubar, CLI gate

**Repository path scope**:
The git work tree resolved from the process current working directory or an explicit `--path`, independent of which repository is selected in the menu bar UI.
_Avoid_: active repo (for CLI defaults), selected project (for CLI defaults)

### Changed files

**Changed Files Summary**:
The collapsible overview of files touched by a commit or by the current
working tree, with aggregate insertions/deletions and a hierarchical path tree.
_Avoid_: card (for this surface — it uses Workbench section chrome, not a
chat-style bordered card), turn diff, checkpoint files

**Diff Tree**:
The hierarchical folder/file listing inside a Changed Files Summary, including
aggregated per-folder stats and optional single-child path compaction.
_Avoid_: file list (when the hierarchical tree is meant), outline view

**Path Compaction**:
Merging a chain of single-child directories into one path label
(e.g. `GitMenuBar/Pages/MainMenu`).
_Avoid_: flatten, collapse path (ambiguous with UI collapse)

**Compact Preview**:
The collapsed Changed Files Summary state that shows top-level scope labels and
a small set of file chips before the full Diff Tree is revealed.
_Avoid_: teaser, snippet row

**Open Diff**:
The primary navigation action from a Changed Files Summary into the external
diff destination (GitHub commit or file-at-commit URL when available; otherwise
the on-disk file).
_Avoid_: show diff (implies an in-app diff viewer we do not ship yet)

### Working tree

**Staged** / **Unstaged**:
The two working-tree buckets GitMenuBar keeps separate; each may host its own
Diff Tree without merging into a single unified changed-files list.
_Avoid_: index / workdir as user-facing labels

**Working Tree Status Letter**:
The trailing `M` / `D` / `U` mark on a working-tree file row.
_Avoid_: badge (unless referring to the status-item glyph)

### Icons

**File Type Icon**:
The glyph beside a file name in a Diff Tree. Phase 1 uses SF Symbols by
extension/name; a later phase may add colored language icons.
_Avoid_: Pierre icon (reference-only name unless documenting the T3Code source)
