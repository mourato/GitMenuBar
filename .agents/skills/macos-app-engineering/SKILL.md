---
name: macos-app-engineering
description: macOS SwiftUI/AppKit implementation and native design guidance for GitMenuBar UI, lifecycle, settings, previews, and platform behavior.
---

# macOS App Engineering

## When to Use

Use this skill when implementing ordinary SwiftUI or AppKit behavior, working with platform lifecycle, or applying macOS design rules.

## Responsibilities

- App lifecycle and activation policy (menu-bar style, no Dock presence)
- Window, popover, and controller ownership
- SwiftUI to AppKit bridge boundaries
- Persistence of desktop-specific state
- Main-actor coordination for UI state

## Platform Rules

- Keep platform state ownership explicit; one controller should own each window, popover, or status item lifecycle.
- Use AppKit only where SwiftUI is insufficient or less reliable.
- Cross the SwiftUI/AppKit boundary in a small adapter layer instead of leaking AppKit concerns across feature code.
- Persist desktop state only when it improves continuity and stays predictable across relaunches.

## Design Rules

- Prefer native macOS controls and platform behaviors over custom chrome unless the custom UI is required by the menu-bar workflow.
- Keep command names, labels, and shortcuts stable.
- Use disabled states and contextual titles when actions are unavailable or state-dependent.
- Respect keyboard access, focus order, reduced motion, and VoiceOver routing.
- Keep windows/popovers resizable or size-constrained only when the content genuinely requires it.

## Preview and Accessibility Expectations

- Every new Swift file that renders interface must include at least one `#Preview`.
- Previews can live in the same file or a dedicated `*Preview.swift` companion file.
- All interactive elements must have meaningful accessibility labels.
- Support Full Keyboard Access, VoiceOver, and system accessibility settings (Reduce Motion, Reduce Transparency, Bold Text, Increase Contrast).

## Validation

- `make build`
- For lifecycle-sensitive changes: launch, open the menu or window, dismiss it, and relaunch.
- Confirm activation behavior stays intentional: no stray Dock presence, rogue windows, or orphaned popovers.
- Verify the UI renders correctly in both Light and Dark appearances.

## Boundaries

- `menubar` remains the owner for `NSStatusItem`, status-item click behavior, popover/menu dismissal, and menu-bar app invariants.
- `accessibility-audit` remains the owner for deep VoiceOver, keyboard, contrast, focus, and reduced-motion reviews.
- `swift-conventions` remains the owner for Swift naming, type safety, lint shape, and required previews.
- `swiftui-performance-audit` remains the owner for SwiftUI invalidation, layout thrash, and profiling evidence.
- `delivery-workflow` remains the owner for build/test/lint routing and merge gates.
