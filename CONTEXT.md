# GitMenuBar

Native macOS menu bar app for day-to-day Git workflows, with a companion CLI for agent-driven commit flows that share the app’s AI and message policy.

## Language

### Product surfaces

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

**Soft dependency**:
Optional use of the Companion CLI from global delivery skills when the binary is on `PATH` and AI generation is ready; otherwise fall back to plain `git` without failing the harness setup.
_Avoid_: hard requirement, mandatory gitmenubar, CLI gate

**Repository path scope**:
The git work tree resolved from the process current working directory or an explicit `--path`, independent of which repository is selected in the menu bar UI.
_Avoid_: active repo (for CLI defaults), selected project (for CLI defaults)
