# Plan 018: Add the Branches, Worktrees, and Cleanup visualizer

> Executor instructions: follow every step and verification command. Stop and report instead of improvising when a STOP condition occurs.
>
> Drift check: git diff --stat b56c93d..HEAD -- GitMenuBar/Components/Branches GitMenuBar/Pages/MainMenu GitMenuBar/Models/GitModels.swift GitMenuBar/Services/Git/GitManager.swift plans/README.md

## Status

- Priority: P1
- Effort: L
- Risk: MED
- Depends on: plans/017-worktree-snapshot-and-cleanup-analysis.md
- Category: direction
- Planned at: commit b56c93d, 2026-07-17

## Execution profile

- **Recommended profile**: implementer
- **Risk/lane**: Medium/Full
- **Parallelizable**: no; BranchManagementSheet is the single presentation surface
- **Reviewer required**: yes; destructive-looking controls and accessibility states need product review
- **Rationale**: contained SwiftUI work changes a frequently used menu-bar sheet
- **Escalate when**: a new window/controller, status-item behavior, persistence, or second repository context is introduced

## Why this matters

Users currently see branches but cannot understand which checkout owns a branch or why a branch is blocked. This phase makes worktrees and cleanup status visible while leaving mutations to Plan 019.

## Current state

- BranchManagementSheet has fixed width, search, local/remote sections, refresh, and branch CRUD.
- BranchManagementRowView renders branch badges and context-menu actions.
- MainMenuOverlays presents BranchManagementSheet through showBranchManagement.
- New UI files must contain #Preview and use MacChromeTypography, MacChromeMetrics, macPanelSurface, and native SwiftUI controls.

## Commands

| Purpose | Command | Expected |
|---|---|---|
| Build | make build | exit 0 |
| Tests | make test | Tests passed |
| Agent loop | make agent-check | lint and Debug build pass |

## Scope

In scope:

- GitMenuBar/Components/Branches/BranchManagementSheet.swift
- GitMenuBar/Components/Branches/BranchManagementRowView.swift
- GitMenuBar/Components/Branches/WorktreeManagementRowView.swift
- GitMenuBar/Components/Branches/CleanupStatusBadgeView.swift
- GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift only if sheet wiring needs adjustment
- GitMenuBar/Pages/MainMenu/MainMenuContent.swift only if the entry label needs clarification
- plans/README.md status row

Out of scope:

- Git query or mutation implementation
- remote fetch/delete behavior
- status-item lifecycle changes
- persistence of filters or selection

## Steps

### Step 1: Add the management modes

Extend BranchManagementSheet with a native segmented control or equivalent picker for Branches, Worktrees, and Cleanup. Preserve existing branch CRUD and refresh behavior. Load the worktree snapshot through GitManager on appear and refresh.

Keep mode, query, loading, and selected IDs local to the sheet. Do not introduce AppStorage.

Verify: make build -> exit 0.

### Step 2: Render worktree rows

Create WorktreeManagementRowView with branch/detached label, abbreviated HEAD, path, clean/dirty state, and locked/prunable/main/current badges. Add Reveal in Finder and Copy Path only through existing platform boundaries. Accessibility labels must explain why removal is unavailable.

Do not display a worktree as removable merely because it is clean; use snapshot eligibility.

Verify: make test -> Tests passed.

### Step 3: Render cleanup status and selection

Create CleanupStatusBadgeView and Cleanup mode. Show default branch, analysis source, eligible/blocked/unknown counts, and local cleanup candidates. Use checkboxes with eligible items selected only when the analyzer permits it. Show explicit reasons for blocked and unknown items.

Add a disabled or non-operative cleanup affordance until Plan 019; do not call existing -D paths.

Verify: make agent-check -> lint and Debug build pass.

### Step 4: Add previews and manual accessibility behavior

Add previews for every new UI file with clean, dirty, locked, detached, merged, and blocked sample data. Verify keyboard navigation, VoiceOver labels, Light/Dark appearances, and repeated open/dismiss behavior from the menu bar.

Verify: make build -> exit 0; manually open and dismiss the sheet repeatedly.

## Test plan

- Keep business-state decisions in Plan 017 analyzer tests.
- Add lightweight adapter tests only if a pure adapter is introduced.
- Use previews for visual coverage, not as Git verification.

## Done criteria

- [ ] Existing branch actions still work.
- [ ] Worktrees have a dedicated mode and readable path/status presentation.
- [ ] Cleanup distinguishes eligible, blocked, and unknown items.
- [ ] No destructive action is wired in this phase.
- [ ] Every new UI file has #Preview.
- [ ] make agent-check and make test pass.
- [ ] plans/README.md status row remains accurate.

## STOP conditions

- Paths/reasons cannot fit without making the sheet unusable.
- A row must mutate Git to render its state.
- A new view needs AppKit lifecycle ownership beyond an existing adapter.
- Existing branch CRUD must be rewritten rather than preserved.

## Maintenance notes

Keep cleanup explanations visible in the row, not only in tooltips. If density becomes a problem, split modes into child views while retaining one presentation owner. Defer gestures and animation until the destructive flow is stable and accessible.
