# Plan 058: Collapsible AI Usage Quota Summary

Status: DONE
Date: 2026-08-06
Category: feature / UI density
Priority: P2
Effort: M
Risk: Medium
Depends on: Plans 033, 047, and 055 (completed quota UI/provider work)
Planned at SHA: 0b795c2
Integrated commits: d68ca46, 9c84c22, 401581a

## Goal

Transform the existing AI usage quota card area into a persisted collapsible
section. It must start collapsed, retain that choice across launches, and show
a compact summary while collapsed: at most three enabled providers, each
represented visually only by its local logo and remaining percentage.

The expanded state must preserve the existing provider cards and their current
quota details. The change is limited to the quota section; it must not add
quota indicators to the status item, change provider fetching, change shared
credentials, or require a license/provenance verification step.

## Confirmed decisions

- Persist the collapsed/expanded state using the existing UserDefaults/AppStorage
  pattern.
- Default the section to collapsed.
- Include only enabled providers with an available snapshot and a primary
  percentage.
- Reuse WorkbenchSectionHeaderChrome for the section header.
- Use the title AI Usage Quotas.
- Show the compact summary only while collapsed; it is informational and not a
  second toggle.
- Import only Codex, Cursor, and OpenRouter logos from the CodexBar provider
  icon set.
- Keep the compact logos local, preserve their original colors, render them at
  about 18 by 18 points, and use a neutral SF Symbol fallback if a local
  asset cannot be decoded.
- Derive the percentage from UsageQuotaSnapshot.primaryDisplayWindow.
- Keep the stable provider order already used by UsageQuotaStore:
  Codex, Cursor, OpenRouter.
- Cap the compact summary at three providers with prefix(3), so a future
  provider cannot make the collapsed header grow without bound.
- Keep stale cached snapshots visible but dimmed. A zero percentage remains
  red. Do not add a stale badge or extra text to the compact summary.
- If no eligible snapshot exists, keep the current behavior: the quota section
  is not rendered.
- Update the domain glossary with Quota Summary.
- Do not create an ADR for this reversible presentation change.
- Do not add license verification or a license gate.

## Why this change

The quota section currently renders every available provider card in the
sidebar footer. That makes the footer tall even when the user only needs a
quick remaining-percentage scan. The existing store already centralizes
provider enablement, availability filtering, and stable ordering, so the
smallest safe change is to add presentation state around the existing strip
and reuse its snapshot data.

CodexBar documents the same compact pattern: provider branding icons with a
percentage label, an overview limited to three provider rows, and 18 by 18
provider icon rendering. The reference assets are the three provider SVGs
named ProviderIcon-codex.svg, ProviderIcon-cursor.svg, and
ProviderIcon-openrouter.svg in CodexBar's Resources directory.

References:

- CodexBar UI guidance:
  https://github.com/steipete/CodexBar/blob/main/docs/ui.md
- CodexBar provider assets:
  https://github.com/steipete/CodexBar/tree/main/Sources/CodexBar/Resources
- Project UI system:
  .interface-design/system.md

## Current implementation facts

The following facts were verified at the planned-at SHA:

- Git status is clean: main tracks origin/main.
- UsageQuotaStripView is rendered only by
  GitMenuBar/Components/Projects/ProjectsSidebarView.swift in the expanded
  sidebar footer.
- UsageQuotaStore.visibleSnapshots already returns only enabled, available
  snapshots and sorts them by UsageProviderID.rawValue. It currently covers
  Codex, Cursor, and OpenRouter.
- UsageQuotaStripView currently renders the provider cards, their separators,
  group border, refresh task, and existing previews.
- UsageQuotaProviderCard already owns the expanded detail presentation,
  traffic-light percentage, stale opacity, reset metadata, and OpenRouter
  credit information.
- WorkbenchSectionHeaderChrome already owns the project section collapse
  affordance, hover treatment, accessible hints, and reduced-motion-aware
  animation.
- AppPreferences.Keys already contains the other persisted sidebar and quota
  preferences, but no quota-section collapse key.
- GitMenuBar/Resources/FileTypeIcons/FileTypeIcon.swift contains the existing
  local SVG-to-NSImage rendering and caching pattern.
- The Xcode project uses a file-system-synchronized GitMenuBar root group, so
  the provider resource files should not need a hand-maintained project-file
  entry. Verify bundling before closing the work.

## Domain language

The executor must add this entry to CONTEXT.md under the existing quota
glossary:

Quota Summary: the compact view of AI usage quotas that identifies each
available Usage Provider by its logo and remaining percentage.

Keep the definition product-facing and implementation-neutral. Do not add
provider-specific terminology or describe the SwiftUI structure in the
glossary. No ADR is needed because this does not establish a difficult-to-
reverse architectural decision or a new external contract.

## Execution profile

**Recommended profile**: implementer
**Risk/lane**: Medium / full
**Parallelizable**: none; the UI, persistence key, local assets, and previews
  form one small shared surface and should be changed by one writer.
**Reviewer required**: yes, read-only review focused on persistence default, accessibility,
  asset bundling, and preservation of expanded-card behavior.
**Rationale**: the code diff should be narrow, but it crosses SwiftUI state,
  persisted UI preference, resource loading, and a user-visible accessibility
  surface.
**Escalate when**: provider fetching or credentials must change; a new provider
  model is required; the status item must change; manual project-file resource
  wiring is required; or preserving the existing expanded cards requires a
  broader refactor.

## Scope

### In scope

- GitMenuBar/Components/UsageQuota/UsageQuotaStripView.swift
- GitMenuBar/Services/Persistence/AppPreferences.swift
- GitMenuBar/Resources/ProviderIcons/ProviderIcon-codex.svg
- GitMenuBar/Resources/ProviderIcons/ProviderIcon-cursor.svg
- GitMenuBar/Resources/ProviderIcons/ProviderIcon-openrouter.svg
- GitMenuBarTests/UsageQuotaStoreTests.swift, only if a focused ordering
  regression test is useful
- CONTEXT.md, for the Quota Summary glossary entry
- plans/README.md, to track this plan

### Out of scope

- UsageQuotaStore.swift provider discovery, fetching, timeout, or credential
  behavior
- UsageQuotaModels.swift, unless implementation reveals a genuinely reusable
  pure selector that cannot stay local to the view
- UsageQuotaSettingsSection.swift and its provider toggles
- ProjectsSidebarView.swift, because the existing footer placement and
  expanded-sidebar gate already satisfy the intended location
- status-item quota glyphs or menu-bar display
- AI Commit Generation
- network-loaded logos or any new dependency
- a generic provider-logo framework
- license checks, provenance gates, or license UI
- manual edits to GitMenuBar.xcodeproj/project.pbxproj

## Implementation steps

### 1. Reconfirm scope and add the persisted preference

Before editing, verify the worktree and planned SHA:

    git status -sb
    git diff --stat 0b795c2..HEAD -- \
      GitMenuBar/Components/UsageQuota \
      GitMenuBar/Services/Persistence/AppPreferences.swift \
      GitMenuBarTests/UsageQuotaStoreTests.swift \
      CONTEXT.md

Add AppPreferences.Keys.isUsageQuotaSectionCollapsed next to the existing
section-collapse keys. In UsageQuotaStripView, bind the state through
AppStorage with a default of true. Prefer the existing AppStorage/UserDefaults
pattern and add only the initializer injection needed to give previews an
isolated defaults suite.

The value must be read reactively, written when the existing header toggles,
and survive relaunch. Do not add a new preferences service or migration for a
single Boolean.

### 2. Add the three local provider logos

Import only these three SVG assets from CodexBar's Resources directory:

    ProviderIcon-codex.svg
    ProviderIcon-cursor.svg
    ProviderIcon-openrouter.svg

Place them under GitMenuBar/Resources/ProviderIcons. Preserve their original
colors and do not add unrelated provider art.

Reuse the existing local SVG rendering approach from FileTypeIcon.swift:
decode the bundled SVG with NSImage(data:), cache the decoded image with the
existing standard-library/AppKit cache pattern, and render it as an 18 by 18
point scaled image. Keep the loader private to the quota UI file unless an
existing shared helper is found during implementation. Do not build an SVG
parser, fetch remote art, or add a dependency.

Map UsageProviderID to the three resource names with a small local switch.
If loading fails, show one neutral SF Symbol fallback such as sparkles, while
the adjacent percentage and its accessibility label remain present. The
fallback must never trigger network access.

Verify that the SVGs are in the built app bundle. If the synchronized project
root does not include them automatically and manual project-file wiring is
required, stop and report the mismatch instead of expanding scope.

### 3. Refactor the strip into a collapsible section

Keep UsageQuotaStripView's existing visibility gate:

    showAIUsageQuotas && !visibleSnapshots.isEmpty

Keep its existing refresh task and hover behavior. Wrap the existing cards in a
section headed by WorkbenchSectionHeaderChrome with:

- title: AI Usage Quotas
- the persisted collapse binding
- accessible expanded and collapsed hints
- a collapsed-only trailing compact summary

When expanded, render the current UsageQuotaProviderCard content unchanged.
The existing progress bars, reset metadata, stale treatment, and OpenRouter
credit rows must remain available after expansion.

When collapsed, render a noninteractive summary containing only, visually:

    local provider logo + remaining percentage

Use the already filtered, already ordered visibleSnapshots. Before rendering,
skip any snapshot whose primaryDisplayWindow is nil, then apply prefix(3).
Do not add provider names, interval chips, progress bars, reset times, stale
badges, or the existing traffic-light dot to this compact visual. Color the
percentage with the existing traffic-light mapping. Dim the complete summary
item for stale snapshots using the same existing stale opacity.

Keep the summary in the header trailing area rather than creating a second
button. It must not toggle the section or intercept the header button. Give
each compact item an accessibility label containing the provider display name,
percentage, and stale status when applicable; the visible compact treatment
may remain logo plus percentage only.

Use existing WorkbenchMetrics, WorkbenchTypography, WorkbenchPalette, and
WorkbenchMotion tokens. Do not add a section shadow or raw spacing/colors.
Respect Reduce Motion through WorkbenchMotion.adaptive for any content
transition. Do not change ProjectsSidebarView or add a status-item surface.

### 4. Update previews and add only focused regression coverage

Keep the existing UsageQuotaStripView previews and make the states explicit:

- collapsed multi-provider preview with Codex, Cursor, and OpenRouter
- expanded multi-provider preview showing the current cards
- stale collapsed preview
- no-eligible-snapshot preview, confirming the section is absent

Use isolated UserDefaults for previews so a developer's real preference cannot
change preview results. Set the collapsed preview state explicitly rather than
depending on a previous preview run.

Do not add a new fake provider solely to test the cap. The current three
providers exercise the full visible limit. If the executor keeps selection
inline as planned, no new model test is needed for prefix(3). If a pure local
selector is extracted for clarity, add one focused test for filtering an
ineligible snapshot and limiting the result to three; do not create a general
provider-summary abstraction.

Optionally add one focused UsageQuotaStoreTests regression asserting that the
three successful providers remain in Codex, Cursor, OpenRouter order. Keep all
existing provider toggle, stale, unavailable, timeout, and privacy tests.

### 5. Validate and sanitize

Run the smallest checks after the implementation, then the full closeout:

    ./scripts/check-preview.sh \
      GitMenuBar/Components/UsageQuota/UsageQuotaStripView.swift
    make agent-check
    xcodebuild -project GitMenuBar.xcodeproj \
      -scheme GitMenuBar \
      -destination 'platform=macOS' \
      -only-testing:GitMenuBarTests/UsageQuotaStoreTests test
    make guidance-check
    make lint && make test
    git diff --check
    git status --short

The explicit preview command is intentional: the current clean-tree
make check-preview path has a known Bash 3.2 empty-candidate issue documented
by the earlier quota work. Do not modify the preview script as part of this
feature. If the explicit candidate check passes, the known clean-tree script
issue is not a feature regression.

For manual acceptance, launch the app and verify:

1. With the quota feature and at least one provider enabled, the section starts
   collapsed after a fresh install/default reset.
2. The collapsed header shows only each eligible logo and percentage, with no
   more than three providers and no visible provider name.
3. Expanding preserves the current full cards and all quota metadata.
4. Collapsing, relaunching, and reopening preserves the last state.
5. Changing provider enablement or refreshing data updates the summary without
   auto-expanding it.
6. Stale data remains dimmed, zero is red, and missing logo data uses the
   neutral fallback without hiding the percentage.
7. With no eligible snapshots, the whole quota section remains absent.
8. The status item and AI Commit Generation UI are unchanged.
9. VoiceOver/keyboard focus can identify each compact provider summary and the
   header remains the only toggle.

## Stop conditions

Stop and report before broadening the patch if any of the following occurs:

- the worktree differs from the planned baseline with unrelated edits;
- visibleSnapshots cannot provide the required percentage without changing
  provider fetching, snapshot semantics, or credential code;
- the existing expanded cards need behavior changes beyond the header wrapper;
- the provider SVGs cannot be bundled without editing the project file;
- a new provider, generic icon framework, network request, dependency, or
  license/provenance check becomes necessary;
- the preview gate exposes an unrelated baseline failure that is not isolated
  to this changed UI candidate.

## Definition of done

- The persisted key exists and defaults to collapsed.
- The quota section uses the existing Workbench section-header pattern.
- Collapsed content is limited to local logo plus percentage, up to three
  eligible providers, in stable provider order.
- Expanded cards retain their existing data and visual behavior.
- Stale, zero, fallback, no-data, reduced-motion, accessibility, and relaunch
  behavior are covered by previews/manual acceptance.
- Only the three intended provider SVGs are added, and all three are bundled.
- CONTEXT.md contains the Quota Summary term.
- No status-item, provider-fetching, credential, license, or dependency changes
  were introduced.
- Targeted checks and the final lint/test gates pass.

## Handoff notes

The executor should use the narrowest implementation that satisfies the above:
one persisted Boolean, one local compact header view, the three bundled SVGs,
and reuse of the current snapshot/card/Workbench helpers. Do not turn the
provider logo fallback or the three-item cap into a reusable framework before
there is a second consumer.

Suggested branch: feat/058-collapsible-usage-quota-summary
Suggested commit: feat(ui): collapse usage quota section
