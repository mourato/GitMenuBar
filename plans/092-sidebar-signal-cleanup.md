# Plan 092: Reduce noise and add severity to the Projects sidebar

> **Executor instructions**: Read this brief, `AGENTS.md`,
> [project workflow facts](../docs/agents/project-workflow.md),
> [UI contract](../docs/ui.md) (especially "Visual hierarchy rules"), and
> [ADR 0020](../docs/adr/0020-toolbar-actions-and-history-list.md) before
> editing. Work in a dedicated worktree. Use Workbench tokens only; no raw
> sizes, colors, or opacities in views. On a STOP condition, stop and report;
> do not widen scope. Leave merge and push to the operator. The UI owner
> reviews the diff and screenshots before merge.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MEDIUM
- **Depends on**: none
- **Category**: ui (premium main-window pass)
- **Planned at**: commit e48a916, 2026-10-28
- **Integration**: main; merge and push require explicit operator authorization

## Execution profile

- **Recommended profile**: Standard/full
- **Risk/lane**: MEDIUM (attention model)
- **Executor**: Antigravity Gemini 3.8, reasoning high
- **Parallelizable**: Yes
- **Reviewer required**: Yes
- **Rationale**: Changes the attention signal users rely on; severity belongs in the model with tests.
- **Escalate when**: severity needs a new Git query or changes how projects are sorted into Needs Attention.

## Problem

Every row repeats "main". All attention rows use the same orange dot. The
change count competes with the project name. The Clean section shows a count
but no disclosure control.

## Scope

1. Add a small severity type next to the existing project attention model
   (not in the view): diverged/behind, uncommitted changes, unmerged only.
2. `ProjectsSidebarView.swift`: dot color from severity per the hierarchy
   rules; branch name only when it is not the default branch; change count as
   a compact trailing badge.
3. Clean section uses a native disclosure with its count.
4. Agent badge (`AgentBadgeIconView`) gets a help tooltip and aligns with the
   badge column.

## Acceptance

- Unit tests for severity mapping.
- Row accessibility label includes name, branch when shown, and status.
- Matches the approved prototype and `docs/ui.md` hierarchy rules.

## Validation

- `make lint-changed`
- `make check-preview` (add or update previews for every changed view)
- `make build`
- Screenshots of the changed surface in Dark and Light, plus Increase
  Contrast, attached to the handoff.
- `make test-focused TEST_FILTER='GitMenuBarTests/ProjectMonitorStoreTests'` plus the new severity test

## STOP conditions

- An unexpected changed path outside this scope.
- A rule in `docs/ui.md` blocks the change: report it; the UI owner decides.
