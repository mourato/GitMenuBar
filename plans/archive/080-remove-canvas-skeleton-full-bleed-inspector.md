# Plan 080: Remove canvas skeleton and extend the inspector under the toolbar

> **Executor instructions**: Keep the selected repository's existing refresh
> generation and publication gates unchanged. This is a serial, UI-only change
> in `MainMenuContent`; leave merge and push to the operator.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: MEDIUM
- **Depends on**: [Plan 079](079-history-inspector-drilldown.md)
- **Category**: visual / accessibility
- **Planned at**: commit 34ba65c, 2026-09-04
- **Publication**: local
- **Integration**: main; merge and push require explicit operator authorization
- **Execution status**: REVIEWED — root review PASS; Debug build, tests,
  guidance-check, and diff-check passed. Lint remains blocked by pre-existing
  SwiftFormat findings in `MainMenuContent.swift` and
  `ChangedFilesSummaryView.swift`; preview detector checked zero candidates.

## Execution profile

- **Recommended profile**: implementer
- **Risk/lane**: Medium / Normal
- **Parallelizable**: no — both slices share `MainMenuContent`
- **Reviewer required**: yes — root-session review covers stale content, toolbar clearance, and VoiceOver state
- **Rationale**: The implementation is a small native SwiftUI change, but the
  shared loading container and inspector safe-area behavior need a serial root
  review against stale-data and toolbar/a11y invariants.
- **Escalate when**: freshness gates, `StatusBarController`, a custom AppKit bridge, a second scroll owner, or a new layout metric is proposed

## Objective

Keep the current repository overview and branch footer visible during the fast
refresh phase, disable those stale controls while they update, and let the
always-present native inspector reach the top edge behind the transparent
unified toolbar.

## Scope

In scope:

- `GitMenuBar/Pages/MainMenu/MainMenuContent.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuSupportViews.swift`
- this plan and its bookkeeping row in `plans/README.md`

Out of scope:

- refresh state, generation gates, GitManager, toolbar items/style, overview
  cards, history loading, fetch behavior, or any AppKit bridge
- `WorkbenchMetrics` unless existing tokens prove insufficient
- `docs/ui.md` and ADRs unless the implementation changes a reusable UI rule

## Implementation

1. Remove the central and footer skeleton call sites; remove their now-dead
   helper views after a repository-wide caller check.
2. Keep overview and footer in place, disable the shared main-route container
   while `isFastLoading`, and expose the concise VoiceOver value “Updating
   project”.
3. Replace the inspector's uniform padding with horizontal/bottom panel
   padding and a top clearance composed from `iconHitTarget + compactSpacing`.
   Apply `ignoresSafeArea(.container, edges: .top)` only to the inspector.
4. Preserve the existing single scroll owner per surface and all detail/history
   loading behavior. If the native inspector ignores the safe-area override,
   retain the internal clearance-only fallback and record it in the handoff.

## Acceptance

- [ ] Switching repositories shows stale overview/footer content with no
      skeleton flash or layout-height change.
- [ ] Overview/footer controls are disabled while `isFastLoading`; VoiceOver
      reports “Updating project”; refresh generation/publication remains intact.
- [ ] Inspector content reaches behind the transparent toolbar with readable
      header spacing, without changing central route padding or toolbar items.
- [ ] Card spinners, detail/history loading, scroll ownership, focus, and
      accessibility labels remain otherwise unchanged.
- [ ] No dead skeleton helpers or out-of-scope files remain.

## Validation

- `make validate`
- `make check-preview` and explicit candidate check for the two MainMenu files
- `make guidance-check`
- `git diff --check`
- `make lint && make test` before merge
- Manual wide-window Light/Dark, increased contrast, Reduce Transparency/Motion,
  VoiceOver, and fast/slow repository-switch smoke checks when a native window
  is available

## Review and integration

Root review: PASS. Keep the isolated branch/worktree intact; do not merge, push,
or clean it up without operator authorization. Native window and VoiceOver
smoke checks remain an operator handoff because no live macOS window was
available to inspect here.
