# Plan 016: Add Git worktree models and porcelain parsing

> Executor instructions: follow the steps and run the verification commands.

## Status

- Priority: P1
- Effort: M
- Risk: MED
- Depends on: none
- Category: direction
- Planned at: commit b56c93d, 2026-07-17

## Execution profile

- **Recommended profile**: implementer
- **Risk/lane**: Medium/Full
- **Parallelizable**: no; this establishes the shared model contract for later phases
- **Reviewer required**: no; this phase is pure parsing and immutable value modeling
- **Rationale**: the parser is bounded, but its output becomes the contract for destructive later phases
- **Escalate when**: Git output requires shell parsing, the parser mutates repository state, or the model must expose remote-provider data

## Why this matters

GitMenuBar currently models branches but has no representation of linked Git worktrees. Later phases need a stable, testable value model before adding service queries or UI. This phase parses Git’s machine-oriented porcelain output without relying on locale-sensitive human output.

## Current state

- GitMenuBar/Models/GitModels.swift contains BranchInfo and BranchCleanupOption but no worktree types.
- GitMenuBar/Services/Git/GitCommandRunner.swift executes /usr/bin/git with argument arrays and captures combined output.
- GitMenuBarTests/TestSupport.swift provides runGit and temporary repository helpers.
- Project convention: immutable structs conform to Hashable/Equatable where useful; tests use XCTest and temporary repositories.

## Commands

| Purpose | Command | Expected |
|---|---|---|
| Targeted tests | make test | Tests passed |
| Debug build | make build | exit 0 |
| Changed-file validation | make agent-check | lint and Debug build pass |

## Scope

In scope:

- GitMenuBar/Models/GitModels.swift
- GitMenuBar/Services/Git/WorktreeParser.swift
- GitMenuBarTests/WorktreeParserTests.swift
- plans/README.md status row

Out of scope:

- GitBranchService queries or mutations
- SwiftUI views
- remote fetch/delete behavior
- changes to existing branch deletion semantics

## Steps

### Step 1: Define immutable worktree value types

Add worktree-specific types to GitModels.swift without changing BranchInfo’s existing initializer or identity. Include a model containing path, HEAD hash, optional branch name, main-worktree flag, lock/prunable metadata, and a working-tree state that can represent clean, dirty, or unknown. Use explicit enums instead of optional booleans that permit contradictory states.

Keep the model independent of SwiftUI and AppKit.

Verify: make build -> exit 0.

### Step 2: Implement a pure porcelain parser

Create WorktreeParser.swift with a pure function that accepts git worktree list --porcelain output and returns parsed records or a typed parse error. Support worktree path, HEAD hash, refs/heads/name conversion, detached records, locked/prunable reasons, blank-line separation, and values containing spaces.

Do not silently invent a path or branch when a required field is malformed. Use argument-independent parsing only; the parser must not execute Git or touch the filesystem.

Verify: make test -> Tests passed.

### Step 3: Add parser regression tests

In WorktreeParserTests.swift, cover a normal main and linked worktree, detached worktree, locked/prunable records, blank-line separation, paths with spaces, and malformed required fields. Assert parsed values, following WorkingTreeParserTests.swift and XCTest conventions.

Verify: make test -> Tests passed with all parser tests.

## Test plan

- Parser unit tests for normal, detached, locked, prunable, whitespace, and malformed input.
- No integration mutation tests belong in this phase.

## Done criteria

- [ ] Worktree model types exist without changing BranchInfo’s public shape.
- [ ] Parser handles all listed porcelain variants.
- [ ] Malformed required records fail explicitly.
- [ ] make build exits 0.
- [ ] make test exits 0.
- [ ] No files outside the scope are modified.
- [ ] plans/README.md status row remains accurate.

## STOP conditions

- The installed Git version does not emit the documented porcelain fields.
- A required field cannot be represented without changing unrelated existing models.
- The parser needs Git execution or filesystem access.
- Existing BranchInfo tests or initializers need unrelated changes.

## Maintenance notes

Keep parsing separate from repository I/O. Future Git versions may add porcelain fields; unknown optional fields should not break valid records. Later phases must use these models as immutable snapshots and must not infer cleanup eligibility inside the parser.
