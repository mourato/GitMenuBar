# GitMenuBar Motion Reference

Use this reference for any GitMenuBar SwiftUI/AppKit change that adds or alters
motion, hover feedback, state transitions, gestures, panel presentation, or
haptic confirmation. Treat the values below as the project default, not as
decoration to be chosen independently in each view.

## Motion tokens

| Token | Default | Use for |
| --- | --- | --- |
| `micro` | `.easeOut(duration: 0.13)` | Hover, press release, small affordances |
| `arrive` | `.snappy(duration: 0.30, extraBounce: 0.02)` | A new item entering a collection |
| `settle` | `.smooth(duration: 0.34)` | Content settling after a state change |
| `swap` | `.easeInOut(duration: 0.20)` | Replacing content in a fixed slot |
| `press` | `.spring(response: 0.15, dampingFraction: 1.0)` | Immediate press feedback |
| `route` | `.spring(response: 0.35, dampingFraction: 1.0)` | Main route changes |

Prefer a critically damped spring (`dampingFraction: 1.0`) for ordinary UI.
Use bounce only when momentum or a deliberate arrival justifies it. Do not use
the route spring for microinteractions or collection-item insertion.

## Context rules

| Context | Default treatment |
| --- | --- |
| Press | Respond on touch-down with scale `0.97...0.98`; keep layout bounds stable. |
| Hover | Animate a small scale up to `1.012`, brightness up to `0.04`, or a subtle fill change. Use only the properties that clarify the target. |
| Raised chip/card | Lift by `3pt`; if needed, use shadow opacity `0.18`, radius `6`, y-offset `2`. |
| New collection item | Combine opacity with scale; use insertion scale around `0.4` and removal scale around `0.6`. Keep bounce minimal. |
| Content swap | Keep the container and layout slots fixed; cross-fade with `swap`. Pin text by baseline when font metrics can differ. |
| Numeric/icon change | Use `.contentTransition(.numericText())` for numbers and `.contentTransition(.symbolEffect(.replace))` for semantic icon replacement. |
| Active work | Use a restrained `.symbolEffect(.pulse, isActive:)` only while the operation is active. |
| Route change | Use a directional transition that reflects the destination and the reverse path. Pair it with `route`. |
| Origin/destination | Use `matchedGeometryEffect` when the user should perceive one object becoming another. Keep IDs stable and scoped. |
| Toast/status | Enter from its semantic edge with opacity; remove it symmetrically. |
| AppKit panel | Animate alpha on presentation; order the window out only after the fade completes. Use an unanimated path for capture/overlay synchronization. |
| Haptic | Fire at the same causal state change as the visual feedback. Reserve confirmation/error feedback for meaningful actions. |

Prefer compositor-friendly properties (`opacity`, `offset`, `scaleEffect`,
transforms) over changing layout dimensions on every animation frame. Do not
animate a container's size and its internal affordance simultaneously unless
the relationship is intentional and verified.

## Accessibility and interaction

- Apply `@Environment(\.accessibilityReduceMotion)` at the shared surface or
  route boundary. Replace slides, springs, bounce, and continuous pulse with a
  short opacity/color change; preserve status and completion feedback.
- Keep hover feedback supplemental. Keyboard focus, selection, contrast, and
  VoiceOver state must remain clear without motion.
- Keep interactive input available during transitions. A gesture-driven view
  must track the pointer continuously, start from the current presentation
  value, and carry release velocity into the settling animation when applicable.
- Use `predictedEndTranslation` or platform velocity APIs for momentum. Do not
  infer a fling from the final position alone.
- Keep entry and exit paths spatially consistent. Asymmetric transitions require
  an explicit product reason.

## Review anti-patterns

Reject or request justification for:

- repeated raw durations where a shared token applies;
- broad `.animation` without a specific `value` or state boundary;
- delayed feedback caused by timers or asynchronous work in the input path;
- layout jumps caused by animating `frame` when `offset` or transform is enough;
- bounce on passive appearance without user momentum;
- icon or number replacement without a semantic content transition;
- a haptic fired after a separate callback instead of at the causal event;
- animation that disappears entirely under `Reduce Motion` instead of becoming a
  useful non-vestibular equivalent;
- a panel ordered out before its fade completes, or a capture overlay that
  reveals the live desktop between transitions;
- unanchored transitions that make a popover or detail view appear unrelated to
  its trigger.

## Static review checklist

Before approving a motion change, verify:

- [ ] The state change and interaction context are named.
- [ ] The selected token and every non-default value have a reason.
- [ ] Feedback starts on press/hover or continuous gesture input, not only on completion.
- [ ] Entry, removal, and reversal paths are spatially coherent.
- [ ] Content swaps preserve layout slots and use semantic transitions where useful.
- [ ] Gestures remain interruptible and do not block input during animation.
- [ ] `Reduce Motion` has a cross-fade/static equivalent.
- [ ] Haptics, if present, fire with the causal visual change and are not excessive.
- [ ] The change does not introduce a machine-specific path, runtime state, or hidden dependency.
- [ ] A relevant preview or existing static inspection path can exercise the state.
