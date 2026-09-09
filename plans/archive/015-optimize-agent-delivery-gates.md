# Plan 015: Optimize agent delivery gates for faster feedback

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `High/Full`
- **Parallelizable**: no; this plan is serial unless a named independent workstream is added during reclassification.
- **Reviewer required**: yes; the plan has high-risk architectural, operational, or integration impact.
- **Rationale**: Altera gates, scripts e política de entrega; uma falha pode mascarar regressões.
- **Escalate when**: Se alterar CI, release, configuração global, modelos ou comandos oficiais fora do escopo.

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report. Do not improvise. When done, update the status row for this plan in
> `plans/README.md`, unless a reviewer dispatched you and told you they maintain
> the index.
>
> **Drift check (run first)**:
>
> ```bash
> git diff --stat 71e7785..HEAD -- Makefile scripts AGENTS.md .agents/skills/delivery-workflow/SKILL.md plans/README.md
> ```
>
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts below against the live files before proceeding. If
> the excerpts no longer match the same responsibilities, stop and report the
> drift instead of applying this plan mechanically.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: dx / tests
- **Planned at**: commit `71e7785`, 2026-07-10

## Why this matters

GitMenuBar already moved toward a cheaper delivery loop by adding
`make lint-changed` and by documenting `make lint && make test` as the merge
gate. The current implementation still has two gaps that cost agent time and
tokens: `make lint-changed` misses untracked Swift files, and it falls back to a
full lint when no changed Swift files are detected. Agents also lack a single
compact iteration command that means "check my current diff without running the
full merge gate." This plan makes the fast loop explicit while keeping the
pre-merge gate strong.

The target workflow is:

- During implementation: `make agent-check` for changed Swift lint plus a debug
  build.
- Before merge or push: `make lint && make test`.
- For packaging: `make build-release && make dmg`, still owned by
  `release-management`.
- No tests in pre-commit by default. If hooks are added later, keep pre-commit
  cheap and reserve the full gate for pre-push/merge.

## Current state

Relevant files and roles:

- `Makefile` - canonical command surface.
- `scripts/lint.sh` - SwiftFormat and SwiftLint checker.
- `scripts/run-build.sh` - debug/release build wrapper.
- `scripts/run-tests-xcode.sh` - full XCTest wrapper.
- `AGENTS.md` - top-level execution policy.
- `.agents/skills/delivery-workflow/SKILL.md` - detailed delivery guidance.
- `plans/README.md` - plan index to update after execution.

Current command surface, from `Makefile:1-31`:

```make
.PHONY: help build build-release test lint lint-changed lint-fix dmg clean setup

help:
	@echo "make build         Build Debug app"
	@echo "make build-release Build Release app"
	@echo "make test          Run XCTest suite"
	@echo "make lint          Run SwiftFormat/SwiftLint checks"
	@echo "make lint-changed  Lint only files changed since HEAD"

build:
	@./scripts/run-build.sh --configuration Debug

test:
	@./scripts/run-tests-xcode.sh

lint:
	@./scripts/lint.sh

lint-changed:
	@./scripts/lint.sh $$(git diff --name-only --diff-filter=ACMR HEAD -- '*.swift')
```

Problem in that excerpt:

- `git diff --name-only ... HEAD -- '*.swift'` does not include untracked Swift
  files, so new files can bypass `make lint-changed`.
- If there are no changed tracked Swift files, `scripts/lint.sh` receives no
  arguments and falls back to full-project lint.

Current lint script fallback, from `scripts/lint.sh:18-22`:

```bash
if [[ $# -gt 0 ]]; then
    TARGETS=("$@")
else
    TARGETS=(GitMenuBar GitMenuBarTests)
fi
```

This fallback is correct for `make lint`, but wrong for a changed-files target
when no changed files exist.

Current test command, from `scripts/run-tests-xcode.sh:9-30`:

```bash
DERIVED_DATA="${PROJECT_ROOT}/.xcode-build-tests"
LOG_PATH="/tmp/gitmenubar-test.log"
echo "Running tests (build-for-testing + test-without-building)..."
"${SCRIPT_DIR}/xcodebuild-safe.sh" \
    --action build-for-testing >"${LOG_PATH}" 2>&1 || {
        echo "Build-for-testing failed. Log: ${LOG_PATH}" >&2
        rg -n "error:|fatal error:|Test Suite|Failing tests" "${LOG_PATH}" | head -50 || true
        exit 1
    }

"${SCRIPT_DIR}/xcodebuild-safe.sh" \
    --action test-without-building >"${LOG_PATH}" 2>&1 || {
```

This proves the documented merge gate can skip `make build`: `make test` already
does `build-for-testing`.

Current top-level policy, from `AGENTS.md:31-37`:

```markdown
- Prefer CLI-first verification and reproducible commands.
- Keep changes small and validated incrementally.
- When working from a branch, PR, or local diff, inspect the touched files first and treat lint findings in modified code as mandatory work for the same change.
- Resolve critical lint violations in the diff before running full-project verification; do not defer issues introduced or exposed by the current change.
- Use `make lint-changed` for fast incremental linting of only modified files during development.
- Before merge, run: `make lint && make test`.
  Lint runs first -- it is cheap and fails fast. The `make test` command already compiles the project via `build-for-testing`, so a separate `make build` is redundant.
```

Current detailed guidance, from `.agents/skills/delivery-workflow/SKILL.md:14-32`:

```markdown
- `make build`: Debug build through `scripts/run-build.sh`
- `make test`: XCTest flow through `scripts/run-tests-xcode.sh`
- `make lint`: SwiftFormat + SwiftLint checks through `scripts/lint.sh`
- `make lint-changed`: SwiftFormat + SwiftLint on files changed since HEAD through `scripts/lint.sh`

Minimum before merge: `make lint && make test`.
Lint runs first -- it is cheap and fails fast. The `make test` command already compiles the project via `build-for-testing`, so a separate `make build` is redundant.
```

There are no active local git hooks in `.git/hooks/`; only sample hooks are
present. This plan should not add mandatory hooks. Keep the workflow explicit
and command-driven.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| List changed Swift files | `./scripts/changed-swift-files.sh` | Prints changed tracked and untracked `.swift` files, or prints nothing and exits 0 |
| Changed lint | `make lint-changed` | Lints changed Swift files; no-ops with a clear message when none exist |
| Compact agent gate | `make agent-check` | Runs changed Swift lint, then debug build |
| Merge gate | `make lint && make test` | Full lint and tests pass |
| Whitespace | `git diff --check` | exit 0 |

## Scope

**In scope**:

- `Makefile`
- `scripts/changed-swift-files.sh` (create)
- `scripts/lint.sh`
- `AGENTS.md`
- `.agents/skills/delivery-workflow/SKILL.md`
- `plans/README.md` status update after execution

**Out of scope**:

- Application Swift source files.
- Xcode project files.
- Release signing and DMG packaging behavior.
- Adding mandatory git hooks.
- Replacing XCTest, SwiftFormat, or SwiftLint.
- Changing the pre-merge gate away from `make lint && make test`.

## Git workflow

- Branch: `dx/agent-delivery-gates`
- Use conventional commits. Suggested commit:
  `chore(workflow): add compact agent delivery gate`
- Do not push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add a changed Swift file detector

Create `scripts/changed-swift-files.sh`:

- Use `#!/bin/bash` and `set -euo pipefail`.
- Resolve `PROJECT_ROOT` the same way the other scripts do.
- Print one Swift path per line.
- Include tracked changed files from:

  ```bash
  git diff --name-only --diff-filter=ACMR HEAD -- '*.swift'
  ```

- Also include untracked Swift files from:

  ```bash
  git ls-files --others --exclude-standard -- '*.swift'
  ```

- De-duplicate and sort the final output.
- Exit 0 when there are no files.

Implementation hint:

```bash
{
    git diff --name-only --diff-filter=ACMR HEAD -- '*.swift'
    git ls-files --others --exclude-standard -- '*.swift'
} | sort -u
```

**Verify**:

```bash
test -x scripts/changed-swift-files.sh
./scripts/changed-swift-files.sh >/tmp/gitmenubar-changed-swift.txt
```

Expected result: both commands exit 0. The output file may be empty if there
are no Swift changes.

### Step 2: Make `make lint-changed` precise and cheap

Update `Makefile`:

- Add `agent-check` to `.PHONY`.
- Add help text:

  ```make
  @echo "make agent-check   Lint changed Swift files and build Debug app"
  ```

- Replace `lint-changed` with a shell block that:
  1. reads changed Swift files from `./scripts/changed-swift-files.sh`,
  2. prints `No changed Swift files to lint` and exits 0 when empty,
  3. otherwise calls `./scripts/lint.sh` with exactly those files.

Use a temporary shell variable inside the recipe. Keep the recipe readable; do
not inline a long `git` pipeline directly in the Makefile.

Add:

```make
agent-check: lint-changed build
```

Do not change `lint` or `test`.

**Verify**:

```bash
make -n lint-changed
make -n agent-check
```

Expected result: both commands print the intended recipes and exit 0.

### Step 3: Keep `scripts/lint.sh` explicit about target mode

Update `scripts/lint.sh` so its output distinguishes full-project mode from
targeted mode.

Required behavior:

- `./scripts/lint.sh` still lints `GitMenuBar` and `GitMenuBarTests`.
- `./scripts/lint.sh file1.swift file2.swift` lints only those files.
- When arguments are present, print:

  ```text
  Linting targeted Swift paths...
  ```

- When no arguments are present, print:

  ```text
  Linting full Swift targets...
  ```

Do not make `scripts/lint.sh` no-op on empty arguments; the no-op belongs to
`make lint-changed`, not the full lint script.

**Verify**:

```bash
./scripts/lint.sh --help
```

Expected result: this may fail because `--help` is not a Swift file. If it
does, that is acceptable for this step; the real verification is the final
`make lint-changed` and `make lint`. Do not add a help mode unless needed.

Then run:

```bash
make lint-changed
```

Expected result: exits 0. It either lints the changed Swift files or prints
`No changed Swift files to lint`.

### Step 4: Update agent guidance

Update `AGENTS.md`:

- Add `make agent-check` to the command surface.
- Replace the incremental lint sentence with a concise iteration rule:

  ```markdown
  - During implementation, prefer `make agent-check` for changed Swift lint plus a Debug build.
  ```

- Keep `make lint && make test` as the before-merge gate.
- State that tests are not required before every commit by default; run targeted
  tests when behavior changes and the full test gate before merge/push.

Update `.agents/skills/delivery-workflow/SKILL.md`:

- Add command routing for `make agent-check`.
- Clarify that `make lint-changed` includes tracked and untracked Swift files.
- Add a short "Recommended Sequence" section:

  ```markdown
  1. During edits: `make agent-check`
  2. When behavior changes: add/run targeted tests where available
  3. Before merge/push: `make lint && make test`
  4. For packaging: `make build-release && make dmg`
  ```

- State that mandatory tests in pre-commit are intentionally avoided because
  they make small agent iterations slower and duplicate the merge gate.

**Verify**:

```bash
rg -n "agent-check|lint-changed|tracked and untracked|pre-commit|make lint && make test" AGENTS.md .agents/skills/delivery-workflow/SKILL.md
```

Expected result: output shows the new command and sequence in both guidance
files.

### Step 5: Final validation and plan status

Run:

```bash
make lint-changed
make agent-check
git diff --check
```

Expected result:

- `make lint-changed` exits 0.
- `make agent-check` exits 0.
- `git diff --check` exits 0.

If `make agent-check` fails because of unrelated in-progress Swift changes,
capture the first actionable error from `/tmp/gitmenubar-build-debug.log`,
leave this plan row as `BLOCKED (unrelated Swift build failure)`, and report
that the workflow script changes are ready but cannot be verified against the
current dirty worktree.

If validation passes, update Plan 015 in `plans/README.md` from TODO to DONE.

## Test plan

This plan changes shell scripts, Makefile targets, and agent guidance. Do not
add XCTest coverage.

Manual command checks are the test plan:

- `./scripts/changed-swift-files.sh` exits 0 and lists both tracked and
  untracked Swift files when present.
- `make lint-changed` exits 0 and does not run a full-project lint when there
  are no changed Swift files.
- `make agent-check` runs changed Swift lint and Debug build.
- `make lint && make test` remains the documented merge gate.

## Done criteria

All must hold:

- [ ] `scripts/changed-swift-files.sh` exists, is executable, and includes both
      tracked and untracked Swift files.
- [ ] `make lint-changed` no-ops when there are no changed Swift files.
- [ ] `make lint-changed` includes new untracked Swift files.
- [ ] `make agent-check` exists and runs `lint-changed` plus `build`.
- [ ] `AGENTS.md` documents `make agent-check` for iteration and
      `make lint && make test` for merge/push.
- [ ] `.agents/skills/delivery-workflow/SKILL.md` documents the same sequence
      and explains why tests are not required before every commit by default.
- [ ] `make lint-changed` exits 0.
- [ ] `make agent-check` exits 0, or Plan 015 is marked BLOCKED with the
      unrelated build failure evidence from `/tmp/gitmenubar-build-debug.log`.
- [ ] `git diff --check` exits 0.
- [ ] `plans/README.md` marks Plan 015 DONE or BLOCKED with a one-line reason.

## STOP conditions

Stop and report back if:

- The drift check shows `Makefile`, `scripts/lint.sh`, `AGENTS.md`, or
  `.agents/skills/delivery-workflow/SKILL.md` changed after `71e7785` and the
  current workflow no longer matches this plan.
- Implementing `make agent-check` requires touching app Swift source or Xcode
  project files.
- The repo already has a different authoritative hook manager or CI workflow
  that requires tests before every commit.
- `make lint-changed` cannot include untracked Swift files without adding a new
  dependency.

## Maintenance notes

- Keep the fast iteration command cheap. If future checks are added to
  `make agent-check`, they should be scoped and should not duplicate the full
  merge gate.
- If GitMenuBar later adds CI or versioned hooks, keep pre-commit limited to
  formatting/linting staged files and keep full tests at pre-push, PR, or merge.
- If the test suite gains reliable file/test mapping, add a separate targeted
  test command instead of making `make agent-check` run the full suite.
