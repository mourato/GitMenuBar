# Plan 065: Unify Workbench scroll edge dissolve and thin scrollbar

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan in
> `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 9d7e99d..HEAD -- GitMenuBar/Components/Common/WorkbenchScrollEffects.swift GitMenuBar/Components/Common/WorkbenchMetrics.swift GitMenuBar/Components/Common/WorkbenchMotion.swift GitMenuBar/Pages/MainMenu/MainMenuContent.swift GitMenuBar/Components/History/CommitDetailPageView.swift GitMenuBar/Components/Projects/ProjectCleanupPage.swift GitMenuBar/Pages/MainMenu/MainMenuCommandPalette.swift GitMenuBarTests/WorkbenchScrollEffectsTests.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: tech-debt
- **Planned at**: commit `9d7e99d`, 2026-08-10

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: no — the shared scroll-effects core and four callers must agree on one contract
- **Reviewer required**: yes — the custom AppKit pointer bridge can affect scrolling, focus, and VoiceOver behavior
- **Rationale**: The visible diff is bounded, but the implementation combines SwiftUI scroll geometry, masking, native scroller suppression, AppKit hit testing, and four different scroll owners. The normal implementer profile gives enough room for compile/runtime judgment while keeping the work isolated.
- **Escalate when**: The custom thumb requires changes to the window shell, sidebar scroll ownership, sheet behavior, deployment target, or accessibility semantics outside the `ScrollView` containers.

## Why this matters

Gordon already established a calm list-to-bar treatment: content dissolves into adjacent surfaces and a thin scrollbar appears only when needed. GitMenuBar currently uses native overlay scrollers and no shared edge mask, so its main content, Commit Details, Project Cleanup, and Command Palette can expose hard scroll boundaries or inconsistent scrollbar chrome. This plan ports the behavior once, keeps each existing scroll owner intact, and records the contract so future routes do not invent another scroll treatment.

## Current state

- `GitMenuBar/Pages/MainMenu/MainMenuContent.swift:120-165` owns the main route's vertical layout: `CommitWorkflowView`, one vertical `ScrollView` for banners → Staged → Unstaged → History, then a fixed branch footer. Preserve `refreshable`, `scrollDisabled(isCommandPalettePresented)`, and the fixed composer/footer placement.
- `GitMenuBar/Components/History/CommitDetailPageView.swift:30-46` owns the Commit Details scroll and caps it at 520 pt. Add the shared modifiers to this scroll only; do not change route header or detail layout.
- `GitMenuBar/Components/Projects/ProjectCleanupPage.swift:31-52` owns the loaded-project list scroll. Candidate/result sheets are separate surfaces and are out of scope.
- `GitMenuBar/Pages/MainMenu/MainMenuCommandPalette.swift:139-161` owns the palette result scroll inside `ScrollViewReader`, already hides native indicators, and uses `scrollSelectionIntoView(using:animated:)` for keyboard selection. Preserve that programmatic scrolling.
- `GitMenuBar/Components/Common/WorkbenchScrollViewStyle.swift:4-18` configures all discovered `NSScrollView`s with transparent backgrounds and overlay scrollers. It does not provide the custom thumb and must remain the general native style hook.
- `GitMenuBar/Components/Common/WorkbenchMetrics.swift:64-79` is the shared spacing/radius/hit-target token source. `WorkbenchMotion.swift:3-25` is the shared animation source. Add only the scrollbar geometry/timing tokens that the four surfaces genuinely share.
- Gordon's reference implementation is `/Users/usuario/Documents/Projects/gordon/Gordon/PanelEffects.swift:90-355`: `EdgeDissolveMetrics` uses `onScrollGeometryChange`, the mask is active only when content is scrollable, and `ThinScrollbarModifier` hides native indicators, draws a 6→10 pt thumb, supports hover/drag/track-jump, and fades after 800 ms. Port the behavior, not Gordon's panel materials or token names.
- The accepted GitMenuBar visual contract is in `.interface-design/system.md` and ADR 0006. The main composition remains `header → composer → scroll → footer`; the four opted-in scroll owners use the shared modifiers explicitly. Do not add this implementation detail to `CONTEXT.md`, which is reserved for product vocabulary.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Drift/status | `git diff --stat 9d7e99d..HEAD -- <in-scope paths>` | no unexpected pre-existing drift, or drift is reviewed before editing |
| Focused changed-file lint/build | `make agent-check` | changed Swift paths lint and Debug app build pass |
| Unit/UI test suite | `make test` | build-for-testing and test-without-building pass |
| Preview coverage | `./scripts/check-preview.sh GitMenuBar/Components/Common/WorkbenchScrollEffects.swift GitMenuBar/Pages/MainMenu/MainMenuContent.swift GitMenuBar/Components/History/CommitDetailPageView.swift GitMenuBar/Components/Projects/ProjectCleanupPage.swift GitMenuBar/Pages/MainMenu/MainMenuCommandPalette.swift` | preview check passes for all listed UI candidates |
| Guidance/docs | `make guidance-check` | guidance, plan structure, and links pass |
| Patch hygiene | `git diff --check` | no whitespace errors |
| Pre-merge full gate | `make lint && make test` | full lint and full test suite pass |

`make check-preview` is also required by project policy for UI work. If it is
run on a clean tree and hits the repository's known Bash `set -u` empty-array
baseline, use the explicit candidate command above and record the baseline; do
not repair the script in this plan.

## Scope

**In scope** (the only application files to modify):

- `GitMenuBar/Components/Common/WorkbenchScrollEffects.swift` (create) — shared edge-dissolve mask, thin-scrollbar state, native-scroller hider, AppKit pointer bridge, and self-contained previews.
- `GitMenuBar/Components/Common/WorkbenchMetrics.swift` — shared edge-band and scrollbar geometry tokens if needed by the port.
- `GitMenuBar/Components/Common/WorkbenchMotion.swift` — shared fade/morph timing tokens if existing motion tokens cannot express the Gordon behavior without raw durations.
- `GitMenuBar/Pages/MainMenu/MainMenuContent.swift` — explicitly opt the main content scroll into the shared contract.
- `GitMenuBar/Components/History/CommitDetailPageView.swift` — explicitly opt the detail scroll into the shared contract.
- `GitMenuBar/Components/Projects/ProjectCleanupPage.swift` — explicitly opt the loaded project list into the shared contract.
- `GitMenuBar/Pages/MainMenu/MainMenuCommandPalette.swift` — explicitly opt the result scroll into the shared contract while preserving `ScrollViewReader` selection behavior.
- `GitMenuBarTests/WorkbenchScrollEffectsTests.swift` (create) — focused tests for the pure scroll metrics and boundary math.

**Out of scope**:

- `GitMenuBar/Components/Projects/ProjectsSidebarView.swift` and its scroll.
- Candidate/result/confirmation sheets, Branch Management sheets, Settings, and other popovers.
- Window shell materials, titlebar chrome, route transitions, Git state/loading behavior, or new preferences.
- Replacing the `ScrollView` containers with `List`, `ScrollPosition`, or a new scrolling architecture.
- New dependencies, persisted prompts/transcripts, or runtime state written to the repository.

## Steps

### Step 1: Add the shared scroll-effects core and metric tests

Create `WorkbenchScrollEffects.swift` in `GitMenuBar/Components/Common`. Keep
the implementation as one shared surface module with these responsibilities:

1. `workbenchEdgeDissolve()` observes only the smallest useful
   `ScrollGeometry` projection (`contentOffset`, `contentSize`,
   `containerSize`, and insets) through `onScrollGeometryChange`.
2. It computes `isScrollable`, top distance, bottom distance, and edge alpha
   with the Gordon contract. A short list returns an all-white mask. A long
   list uses transparent edge stops, a fully opaque middle, and the adaptive
   top/bottom floors; keep the mask full-frame and do not reintroduce a native
   scroll-edge rectangle.
3. `workbenchThinScrollbar()` hides the native visible scroller for that
   specific owner, keeps the custom overlay above the mask, and renders no
   thumb or hit target when the content is not scrollable.
4. Port Gordon's pointer behavior: the thumb expands on hover/drag, the track
   jumps on click, dragging maps pointer travel to the `NSClipView` offset, and
   wheel events are forwarded to the target scroll view. The overlay must
   return `nil` from `hitTest` outside the active thumb/rail so it never blocks
   rows, buttons, text fields, refresh, or keyboard focus.
5. Use `@Environment(\.accessibilityReduceMotion)` to replace fade/morph
   animation with the shared reduced-motion path. Keep the underlying
   `ScrollView` as the accessibility and programmatic-scroll owner; do not
   expose the decorative thumb as a competing VoiceOver control.
6. Add a focused long-list and short-list `#Preview` in the same file. The
   preview must exercise both the no-mask/no-thumb state and the scrollable
   state; it should use local data only.

Keep new values in `WorkbenchMetrics`/`WorkbenchMotion` rather than scattering
raw constants. Match Swift 6.0 syntax, existing `@MainActor` annotations, and
the AppKit bridging style already used by `WorkbenchScrollViewStyle`.

Add `WorkbenchScrollEffectsTests.swift` with small `XCTest` cases for:

- content that fits reports not scrollable;
- content that exceeds the viewport reports scrollable;
- top and bottom distances clamp correctly at the bounds;
- thumb geometry clamps to the minimum height and remains within the track.

Do not make the views depend on those tests; test pure metric values only.

**Verify**: `make agent-check` → the new shared Swift file compiles, changed
Swift lint passes, and the Debug build succeeds. `make test` → metric tests and
the existing suite pass.

### Step 2: Opt the four scroll owners into the contract

Apply the modifiers explicitly in this order — edge dissolve first, thin
scrollbar second — to the four existing vertical scroll owners:

- Main project content in `MainMenuContent.swift`.
- Commit Details in `CommitDetailPageView.swift`.
- Loaded Project Cleanup rows in `ProjectCleanupPage.swift`.
- Command Palette results in `MainMenuCommandPalette.swift`.

Set native indicator visibility consistently so the custom thumb is the only
visible scrollbar. Preserve these existing behaviors exactly: the main
`refreshable` action and command-palette disable state, detail scrolling, the
cleanup page's load-state branches, and the palette's `ScrollViewReader`
selection-to-center behavior. Do not attach the modifiers to sidebar or sheet
scrolls.

**Verify**: `./scripts/check-preview.sh GitMenuBar/Components/Common/WorkbenchScrollEffects.swift GitMenuBar/Pages/MainMenu/MainMenuContent.swift GitMenuBar/Components/History/CommitDetailPageView.swift GitMenuBar/Components/Projects/ProjectCleanupPage.swift GitMenuBar/Pages/MainMenu/MainMenuCommandPalette.swift` → all listed UI candidates have preview coverage. `make agent-check` → lint and Debug build pass.

### Step 3: Validate visual and interaction states

Use the new preview plus the existing route previews/harnesses. For the main
window, use `MainMenuPreviewHarness(showsTransparentTitlebar: true)` as required
by `AGENTS.md`; component-only scroll previews should remain standalone.

Exercise each opted-in surface with short content, long content, top/middle/
bottom scroll positions, hover, track click, thumb drag, wheel scrolling,
keyboard navigation, and command-palette selection changes. Check System/Light/
Dark appearance, increased contrast, Reduce Transparency, and Reduce Motion.
Confirm that:

- short content has no dissolve and no thumb;
- long content fades softly at both edges without a hard rectangle/divider;
- the thumb remains above the mask and does not steal row/control hit testing;
- main composer/footer and route headers keep their existing geometry;
- command-palette selection scrolling remains centered and keyboard-driven;
- VoiceOver/focus still follow the underlying scroll content;
- Reduce Motion removes only scrollbar animation, not scrolling or feedback;
- Reduce Transparency remains legible without introducing a new material plate.

**Verify**: `make check-preview` → passes, or the known clean-tree baseline is
recorded alongside the explicit candidate check. `make test` → full test suite
passes. Manual WindowServer/VoiceOver checks are reported separately if the
environment cannot run them.

### Step 4: Run the delivery gates and hand off

Run `make guidance-check` after any plan or documentation adjustment, then run
`git diff --check`, `make lint && make test`, and the explicit preview check.
Review the final diff for scope: only the shared effect, tokens, four callers,
and focused metric tests may change.

**Verify**: `git status --short` → only the in-scope paths are modified;
`make guidance-check`, `git diff --check`, `make lint && make test`, and the
explicit preview command all exit 0, with any environment-only manual limitation
recorded in the handoff.

## Test plan

- Model pure metric assertions after the small XCTest style in
  `GitMenuBarTests/GitMenuBarTests.swift`; use `@testable import GitMenuBar` and
  no live services, files, or WindowServer state.
- Cover fit/overflow, top/bottom distance clamping, minimum thumb size, and
  track-boundary clamping in `WorkbenchScrollEffectsTests.swift`.
- Use previews and manual interaction for the `LinearGradient` mask, AppKit
  hit testing, hover/drag/track-jump behavior, appearance, VoiceOver, and
  reduced-feature modes; those are not meaningfully proven by model tests.

## Done criteria

- [ ] `workbenchEdgeDissolve()` and `workbenchThinScrollbar()` exist in one shared Workbench scroll-effects source file and use shared tokens.
- [ ] Main, Commit Details, Project Cleanup, and Command Palette use the modifiers in the documented order.
- [ ] Sidebar, sheets, and unrelated popovers do not use the modifiers.
- [ ] Native visible scrollers are suppressed only for opted-in surfaces; custom thumbs remain above the mask and do not block content interaction.
- [ ] Short content has no mask/thumb; long content follows the Gordon edge-alpha contract.
- [ ] Reduce Motion, Reduce Transparency, increased contrast, keyboard, focus, and VoiceOver behavior remain usable.
- [ ] `WorkbenchScrollEffectsTests.swift` covers the pure metric boundary cases and passes.
- [ ] `make agent-check`, `make test`, `make check-preview` (or documented baseline fallback), `make guidance-check`, `git diff --check`, and pre-merge `make lint && make test` pass.
- [ ] No files outside the in-scope list are modified; `plans/README.md` status row is updated by the executor.

## STOP conditions

Stop and report instead of improvising if:

- `onScrollGeometryChange` is unavailable for the repository's actual SDK/deployment target or requires a deployment policy change.
- The custom `NSViewRepresentable` cannot identify its owning `NSScrollView` without capturing an unrelated parent/child scroll owner.
- Hiding native scrollers removes keyboard, focus, or VoiceOver semantics from the underlying `ScrollView`.
- The mask hides the custom thumb, blocks hit testing, breaks `refreshable`, or changes command-palette selection scrolling.
- A route requires modifying sidebar, sheets, popovers, window chrome, or persistence to achieve the requested effect.
- The live code differs materially from the current-state excerpts or any verification command fails twice after a reasonable fix attempt.

## Maintenance notes

- New central Workbench route scrolls should opt into the shared modifiers only
  after checking whether they are a route scroll owner or an auxiliary surface.
- Keep the custom pointer bridge small and scoped to scrolling; do not add a
  general event-routing abstraction. Any future horizontal-scroll support is a
  separate decision.
- Reviewers should inspect modifier order, native-scroller suppression,
  `hitTest` pass-through, `NSClipView` offset clamping, and reduced-motion/a11y
  behavior before approving visual polish.
- The sidebar, sheets, and popovers are deliberately deferred so this contract
  does not become a global scroll-style mutation without a new design decision.
