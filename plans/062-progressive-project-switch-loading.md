# Plan 062: Show selected-project content progressively with skeleton states

> **Executor instructions:** Read this plan completely before editing. Keep
> the selected-project refresh session as the single owner of cancellation and
> freshness. The goal is earlier useful content and stable loading geometry,
> not a new rendering architecture. Update the ledger only after
> implementation and review pass.
>
> **Drift check (run first):** `git diff --stat f2c84e5..HEAD -- GitMenuBar/Services/Git/GitManager.swift GitMenuBar/App/StatusBarController.swift GitMenuBar/App/MainMenuPresentationModel.swift GitMenuBar/Pages/MainMenu/MainMenuContent.swift GitMenuBar/Pages/MainMenu/MainMenuSupportViews.swift GitMenuBar/Components/History/HistoryTimelineSectionView.swift GitMenuBarTests/GitManagerRefreshTests.swift GitMenuBarTests/MainMenuPresentationModelTests.swift GitMenuBarTests`
> Plan 061 must be complete first because this plan shares the window
> presentation controller and refresh scheduling path.

## Status

- **Priority:** P0
- **Effort:** L
- **Risk:** HIGH
- **Depends on:** Plan 061; Plan 057 (Swift 6.2 baseline); Plans 050–052 (DONE)
- **Category:** perf / SwiftUI state / concurrency / UX
- **Planned at:** commit `f2c84e5`, 2026-08-07

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: High / Full
- **Parallelizable**: no — GitManager's refresh session, presentation state,
  and both loading surfaces must agree on one phase contract.
- **Reviewer required**: yes — review cancellation/freshness, callback order,
  layout stability, accessibility, and reduced-motion behavior.
- **Rationale**: The existing refresh is serial and the UI treats all work as
  one spinner. A small fast/detail phase boundary lets working-tree and branch
  content appear first while history and remote detail continue under the
  existing cancellation session.
- **Escalate when**: a second refresh owner, render store, debounce, detached
  task, or broad `ObservableObject`/`EquatableView` rewrite is proposed.
- **Reuse → extend → create**: reuse the existing GitManager refresh session,
  presentation model, and Workbench placeholder styling; extend the current
  refresh callback/state contract; create no new renderer or coordinator.

## Why it matters

When switching projects, `GitManager.refreshAsync` waits for local
working-tree state, branch state, remote URL, and history before
`StatusBarController.refreshMainWindowData` finishes the refresh. During
that time `MainMenuContent` replaces useful regions with a small
`ProgressView`, and the history section does the same. The result feels like
a blank app even when the first useful local state is already available.

The desired contract is progressive: show stable placeholders immediately,
publish local working-tree/branch state as soon as it is ready, and keep only
the still-pending detail region loading. This improves perceived speed without
pretending history is ready or allowing stale project data across a switch.

## Current state

- `GitMenuBar/Services/Git/GitManager.swift:157-177` performs local working
  tree, branch, commit count, remote URL, and history work in sequence.
- `GitManager.refreshSelectedRepository` already owns cancellation and a
  refresh session/generation; its single completion fires after the entire
  refresh.
- `GitMenuBar/App/StatusBarController.swift:1049-1060` starts the
  presentation-model refresh and finishes it only from final completion.
- `GitMenuBar/Pages/MainMenu/MainMenuContent.swift:42-44` shows
  `loadingStateView` while refreshing and there are no working-tree changes.
- `MainMenuContent.swift:271-303` passes the same refresh flag to history;
  `HistoryTimelineSectionView.swift:21-42` renders a spinner/text empty
  state instead of preserving timeline geometry.
- `MainMenuPresentationModel` has one refresh state and no distinction
  between local state ready and detail still loading.

## Product and technical contract

1. On initial presentation and project switch, working-tree and branch regions
   use stable skeleton geometry until fast local state arrives.
2. When the fast phase completes, the working-tree region renders actual state.
   History may continue showing a skeleton until detail completes.
3. The existing selected-refresh session remains the only freshness authority.
   Fast and final callbacks are ignored if their session is no longer current.
4. Remote URL/history may be reordered or split only to improve the visible
   critical path. Git semantics, history ordering, branch labels, errors, and
   manual refresh behavior remain unchanged.
5. Skeletons do not flash after data is ready, do not change row height while
   loading, and are hidden from VoiceOver as decorative placeholders. The
   containing region still exposes a concise loading status.
6. Do not add a global overlay, custom shimmer, animation framework, or second
   render store. Respect Reduce Motion.

## Scope

**In scope (the only implementation files for this plan):**

- `GitMenuBar/Services/Git/GitManager.swift`
- `GitMenuBar/App/StatusBarController.swift`
- `GitMenuBar/App/MainMenuPresentationModel.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuContent.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuSupportViews.swift`
- `GitMenuBar/Components/History/HistoryTimelineSectionView.swift`
- `GitMenuBarTests/GitManagerRefreshTests.swift`
- `GitMenuBarTests/MainMenuPresentationModelTests.swift`
- `plans/062-progressive-project-switch-loading.md`
- `plans/README.md`

**Out of scope:**

- Window alpha/presentation scheduling and monitor seed; Plan 061 owns those.
- Sidebar monitor line-diff reads; Plan 063 owns that.
- Broad SwiftUI invalidation/render-snapshot redesign, memoization, debounce,
  new persistence, or a network/cache layer.
- Changing the selected GitManager facade or creating one GitManager per
  monitored project.

## Commands and evidence

| Purpose | Command | Expected result |
|---|---|---|
| Drift | `git diff --stat f2c84e5..HEAD -- <scope>` | Empty or understood Plan 061/057 drift only |
| Focused loop | `make agent-check` | Changed Swift lint and Debug build pass |
| Tests | `make test` | Refresh/session/model tests pass |
| Preview gate | `make check-preview` plus `./scripts/check-preview.sh GitMenuBar/Pages/MainMenu/MainMenuSupportViews.swift GitMenuBar/Pages/MainMenu/MainMenuContent.swift GitMenuBar/Components/History/HistoryTimelineSectionView.swift` when the changed-file set is empty | Changed UI candidates have previews |
| Guidance | `make guidance-check` | `guidance-check: passed` |
| Hygiene | `git diff --check` | No whitespace errors |
| Merge gate | `make lint && make test` | Both commands pass |
| Manual timing | shortcut open and project switch on a slow/large repo | first useful local state appears before history; no stale late state |

## Suggested executor toolkit

- `performance-profiling` for phase timestamps and before/after evidence.
- `swift-concurrency` for the existing refresh-session callback contract.
- `swiftui-expert-skill` for invalidation and stable skeleton composition.
- `swiftui-accessibility-audit` plus the project overlay for loading,
  focus, reduced motion, and contrast.
- `ux-writing` for any changed loading/empty-state copy.

## Ordered implementation steps

### 1. Freeze the current refresh contract

Run the drift check and inspect every caller of
`refreshSelectedRepository`, `refreshAsync`, `startRefresh`,
`finishRefresh`, and both current loading views. Capture callback order and
superseded-refresh tests before editing.

**Verify:** the implementation identifies exact fast-local and detail fields
without adding a second refresh entry point.

### 2. Add a fast/detail phase boundary to the existing session

Keep the selected-refresh session/generation and introduce only the smallest
callback/state distinction needed for two milestones:

- **Fast phase:** working-tree state and branch state, plus commit-count state
  if the existing branch refresh already produces it without another blocking
  operation.
- **Detail phase:** remote URL and commit history, preserving current
  ordering/error behavior for those fields.

Publish the fast callback only after fast fields are committed and only for the
current session. Continue the same task/session for detail work; do not launch
an unrelated task that can outlive cancellation. The final callback still
clears detail loading and remains session-gated.

If an existing GitManager method can express the milestone with one optional
callback, extend it. Do not create a protocol or coordinator with one
implementation.

**Verify:** `GitManagerRefreshTests` proves fast callback precedes final
completion, final state still contains remote/history data, and a superseded
session cannot invoke old-project callbacks.

### 3. Represent the two UI phases in the presentation model

Reuse the current refresh state and add only the smallest detail-loading
property or phase needed by both content regions. The transitions are:

```text
startRefresh       -> fast loading + detail loading
fast phase ready   -> fast loading false + detail loading true
final completion   -> both loading flags false
superseded refresh -> old callbacks ignored; new start owns the state
```

Start presentation state before the window's first frame when opening a
refresh, but do not perform Git work before the window is visible. Preserve
manual `.refreshable` and project-switch behavior.

**Verify:** `MainMenuPresentationModelTests` covers every transition and
ensures a stale final callback cannot clear a newer refresh.

### 4. Replace spinner replacement with stable skeletons

In `MainMenuSupportViews.swift`, replace the working-tree spinner-only view
with a compact native SwiftUI skeleton: fixed-height rows, muted fills, and
`.redacted(reason: .placeholder)` or equivalent existing Workbench styling.
In `HistoryTimelineSectionView.swift`, use the same approach for a few
timeline rows. Keep actual content layout as the source of truth; do not add
a parallel data model solely for placeholders.

Render the working-tree skeleton only while fast phase is loading. Render the
history skeleton while detail is loading and history is unavailable. Once each
phase is ready, render the actual empty/content state. Skeleton shapes are
decorative (`accessibilityHidden(true)`); the containing section exposes the
existing concise loading status. Do not animate under Reduce Motion.

Add/maintain `#Preview` coverage in edited UI files using existing Workbench
tokens. Do not introduce new copy unless current loading wording is
insufficient; if copy changes, review it through `ux-writing`.

**Verify:** `make check-preview` passes; previews show loading, empty, and
loaded states without titlebar overlap; a slow refresh no longer collapses
main content into a spinner.

### 5. Validate real switching behavior

Run the command table. Manually test first open, clean/dirty project switches,
slow history, rapid switches, explicit refresh, unavailable repository, and
Reduce Motion. Use existing traces for fast and final completion timestamps.

**Verify:** useful local content appears before history, timeline geometry stays
stable, rapid switches show only the latest project, and GitManager tests stay
green.

## Test plan

- Extend `GitManagerRefreshTests` for fast-before-final ordering, detail
  completion, cancellation, and stale-session suppression.
- Extend `MainMenuPresentationModelTests` for fast/detail transitions and
  replacement refreshes.
- Run `make agent-check`, `make test`, `make check-preview`, and
  `make guidance-check`.
- If `make check-preview` hits the known clean-tree `files[@]`/Bash
  `set -u` failure, run the explicit candidate-file command from the table
  and record the script issue separately; do not fix it in this plan.
- Run `make lint && make test` before handoff.
- Perform manual keyboard, mouse, labels/VoiceOver where available, reduced
  motion, and rapid-switch smoke tests.

## Done criteria

- Working-tree/branch content is visible as soon as fast local phase is ready;
  history continues independently until detail completes.
- Spinner replacement is gone from main working-tree and history loading
  surfaces; skeletons preserve layout and accessibility basics.
- Cancellation/session behavior prevents stale project content and callbacks.
- Focused tests, preview, agent, guidance, lint, and test gates pass, with
  timing and manual evidence recorded.
- No new cache, renderer, debounce, or parallel refresh owner was introduced.

## STOP conditions

- Fast publication requires weakening the existing session freshness guard.
- A Git operation cannot be split without changing displayed semantics/errors.
- Skeletons require a second copy of the content layout or animation dependency.
- Stale history/branch state survives a project switch.
- Plan 061/057 changed shared APIs and drift cannot be reconciled locally.

## Maintenance notes

Keep phase boundaries tied to user-visible readiness, not arbitrary task
completion. If the fast phase is still over budget, measure its Git
operations first; do not hide the problem with longer skeletons or another
loading layer.
