---
name: apple-design
description: Apple's approach to interface design, fluid movement and physics — translated to Swift, SwiftUI and UIKit. Use when building or reviewing GitMenuBar or Apple-platform UI involving gesture-oriented UI, spring animations, drag/swipe/sheet interactions, motion tokens, momentum and interruptible transitions, translucent materials and depth, typography (Dynamic Type, tracking, leading), reduce motion, or the design fundamentals (feedback, spatial consistency, containment) behind interfaces in Apple style.
---

# Apple Design (Swift / SwiftUI / UIKit)

How Apple builds interfaces that stop looking like a computer and start looking like an extension of you. This knowledge comes from WWDC design talks — mainly _Designing Fluid Interfaces_ (WWDC 2018) — distilled and translated into Apple's native platform (SwiftUI, UIKit, Core Animation, `CADisplayLink`, `UIViewPropertyAnimator`).

The common thread: **an interface feels alive when motion starts from the current value on screen, inherits the velocity of the user, projects momentum ahead, and can be grabbed and reversed at any instant.** Springs are the tool that makes this natural, because they are interruptible and velocity-sensitive by nature — and, fortunately, they are first-class citizens in both SwiftUI and UIKit/Core Animation.

## The central idea

> "When we align the interface to how we think and move, something magical happens — it stops looking like a computer and starts looking like a continuous extension of ourselves."

An interface is fluid when it behaves like the physical world: responds instantly, moves continuously, carries momentum, resists at boundaries, and can be redirected mid-motion. Everything below is a way to get closer to that.

Apple frames design as serving four human needs: **safety/predictability, understanding, accomplishment, and delight.** Each rule here serves one of them.

## GitMenuBar motion profile

When working in GitMenuBar, read [the project motion reference](references/gitmenubar-motion.md) before designing, implementing, or reviewing animation. Apply its tokens and context rules as the project default; document any deliberate exception in the change and keep accessibility behavior intact.

## 1. Response — eliminate latency

The instant latency appears, the sense of direct manipulation "plummets." Response is the foundation on which everything else is built.

- **Respond at the start of the touch, not at release.** Highlight a button the instant it's pressed. Waiting for `.onEnded`/`touchUpInside` to show feedback feels dead.
- **Watch out for all latency.** Audit debounces, artificial timers, unnecessary `DispatchQueue.asyncAfter` in the input path, and anything that delays visual feedback.
- **Feedback should be continuous _during_ the interaction, not just at the end.** For a drag, slider, or drawer, update the UI 1:1 with the finger all the time — never animate only when the gesture ends.

```swift
// SwiftUI — feedback on press, instantaneous
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.15, dampingFraction: 1.0), value: configuration.isPressed)
    }
}
```

```swift
// UIKit — highlight on touchDown, not touchUpInside
button.addTarget(self, action: #selector(highlight), for: .touchDown)
```

## 2. Direct manipulation — 1:1 tracking

> "Touch and content must move together."

When the user drags something, the element needs to stay glued to the finger — respecting the offset of _where they grabbed it_. Snapping to the center of the element on grab breaks the illusion immediately.

- In **SwiftUI**, use `DragGesture(minimumDistance: 0)` with `.updating` to a `@GestureState`, and calculate the offset from the gesture start point (`value.startLocation`), not the center of the view.
- In **UIKit**, use `UIPanGestureRecognizer` and capture `translation(in:)` each `.changed`; store the offset between the initial touch point and the view's origin.
- Keep a **short history of position/time** — in SwiftUI, `DragGesture.Value` already provides `predictedEndTranslation`; in UIKit, use the recognizer's own `velocity(in:)`.

```swift
// SwiftUI
@GestureState private var dragOffset: CGSize = .zero

var body: some View {
    card
        .offset(dragOffset)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($dragOffset) { value, state, _ in
                    state = value.translation // respects the offset from where the finger touched
                }
                .onEnded(handleRelease)
        )
}
```

```swift
// UIKit
@objc func handlePan(_ gesture: UIPanGestureRecognizer) {
    let translation = gesture.translation(in: view.superview)
    switch gesture.state {
    case .began, .changed:
        view.transform = CGAffineTransform(translationX: translation.x, y: translation.y)
    case .ended, .cancelled:
        let velocity = gesture.velocity(in: view.superview) // necessary for velocity handoff (§5)
        release(with: velocity)
    default: break
    }
}
```

## 3. Interruptibility — the most important principle

> "Thought and gesture happen in parallel."

Every animation must be interruptible and redirectable at any moment. The user needs to be able to grab an element mid-flight and reverse it without waiting for the animation to finish. A modal closing that the user grabs again should follow the finger — not finish closing and then reopen.

- **Never block input during a transition.**
- **Always animate from the value of _presentation_ (current), never from the target value.** In UIKit/Core Animation, read `layer.presentation()?.value(forKeyPath:)` when interrupting, not the `modelLayer` (final logical value) — animating from the logical value causes a visible jump.
- **SwiftUI:** implicit animations via `.animation(_:value:)` already recycle the current state automatically when the `value` changes again mid-flight — it's the desired native behavior, as long as you use `.spring(...)` and don't force a `withAnimation(.linear)` that doesn't interpolate well from the middle.
- **UIKit:** prefer `UIViewPropertyAnimator` to `UIView.animate(withDuration:)` for anything gesture-oriented — it's `isInterruptible` by default and allows reading/adjusting `fractionComplete` in real time, plus it continues from where it stopped when you call `.startAnimation()` again after a `.pauseAnimation()`.
- **When a gesture reverses, blend the velocity — don't cut dry.** Replacing one animation with another on reversal creates a velocity discontinuity, a "brick wall." `UISpringTimingParameters(dampingRatio:initialVelocity:)` and SwiftUI's `Animation.spring` already do this re-target from current velocity when the target value changes.
- **Decompose 2D motion into independent springs for X and Y.** A single spring over a 2D distance desynchronizes when X and Y have different velocities — animate `offset.width` and `offset.height` (or `CGPoint.x`/`.y`) as separate animatable values.

```swift
// UIKit — interruptible animator
var animator: UIViewPropertyAnimator?

func animateSheet(to y: CGFloat, velocity: CGVector) {
    animator?.stopAnimation(true) // captures current state implicitly via presentation layer
    let timing = UISpringTimingParameters(dampingRatio: 1.0, initialVelocity: velocity)
    animator = UIViewPropertyAnimator(duration: 0.4, timingParameters: timing)
    animator?.addAnimations { sheet.frame.origin.y = y }
    animator?.startAnimation()
}

// To interrupt mid-flight, always start from the presentation value:
func interrupt() {
    animator?.pauseAnimation()
    let currentY = sheet.layer.presentation()?.frame.origin.y ?? sheet.frame.origin.y
    animator?.stopAnimation(true)
    // new animation starts at currentY, not the old target
}
```

## 4. Behavior instead of animation — use springs

> "Think of animation as a conversation between you and the object, not something prescribed by the interface."

A pre-scripted animation with fixed duration doesn't respond to new input. A spring does — new input just changes the target, and motion continues smoothly. Resort to springs for anything the user might touch.

Apple deliberately replaces the physics trio (mass/stiffness/damping) with two designer-friendly parameters, available directly in SwiftUI (and, from iOS 17, in the `Spring` type):

- **`dampingFraction`** — controls overshoot. `1.0` = critically damped, no bounce, settles smoothly. `< 1.0` = overshoots and oscillates. Lower = more elastic.
- **`response`** — how fast the value reaches the target, in seconds. Lower = snappier. **This is not "duration"** — a spring has no fixed duration; the settling time emerges from the parameters.

**Patterns:**

- Start most of the UI with **`dampingFraction: 1.0`** (critically damped) — elegant and not distracting.
- Add bounce (**`dampingFraction` ~`0.8`**) **only when the gesture itself carried momentum** (a flick, a throw, the release of a drag). Overshoot on a menu that just appeared with fade looks wrong; overshoot on a card you threw looks right.

**Concrete values Apple uses:**

| Interaction                   | Damping | Response |
| ----------------------------- | ------- | -------- |
| Move / reposition (e.g., PiP) | `1.0`   | `0.4`    |
| Rotation                      | `0.8`   | `0.4`    |
| Drawer / sheet                | `0.8`   | `0.3`    |

```swift
// SwiftUI — critically damped spring as default
withAnimation(.spring(response: 0.4, dampingFraction: 1.0)) {
    offset = .zero
}

// Interaction with momentum — a little bounce, just because a flick preceded
withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
    offset = target
}

// iOS 17+: dedicated Spring API, more explicit about Apple's "mental model"
let spring = Spring(response: 0.4, dampingRatio: 1.0)
withAnimation(spring) { offset = .zero }
```

```swift
// UIKit — the same parameters via UISpringTimingParameters
let timing = UISpringTimingParameters(dampingRatio: 0.8) // bounce, for something with momentum
let animator = UIViewPropertyAnimator(duration: 0.4, timingParameters: timing)
```

## 5. Velocity handoff — the seam between drag and animation

When a gesture ends, the animation needs to **continue at exactly the velocity of the finger**, so there's no visible seam between dragging and animating. This is the detail that most separates "fluid" from "polished."

Pass the gesture's release velocity as the spring's initial velocity:

- **SwiftUI:** `DragGesture.Value` doesn't expose velocity directly, but `predictedEndTranslation` already embeds Apple's momentum projection (see §6) — you can derive approximate velocity from the difference between `translation` and `predictedEndTranslation`, or track timestamps manually with `@GestureState`.
- **UIKit:** `UIPanGestureRecognizer.velocity(in:)` returns velocity in points/second directly — pass it to `UISpringTimingParameters(dampingRatio:initialVelocity:)`.

Some spring APIs want velocity **relative**, normalized by the distance remaining to the target:

```
relativeVelocity = gestureVelocity / (targetValue − currentValue)
```

Example: element at `y=50`, target `y=150` (100pt remaining), finger at 50pt/s → spring's initial velocity = `50 / 100 = 0.5`.

```swift
let velocity = panGesture.velocity(in: view.superview)
let distanceRemaining = CGVector(dx: target.x - current.x, dy: target.y - current.y)
let relativeVelocity = CGVector(
    dx: distanceRemaining.dx != 0 ? velocity.x / distanceRemaining.dx : 0,
    dy: distanceRemaining.dy != 0 ? velocity.y / distanceRemaining.dy : 0
)
let timing = UISpringTimingParameters(dampingRatio: 0.8, initialVelocity: relativeVelocity)
```

## 6. Momentum projection — animate to where the gesture is _going_

> "Take a small input and produce a large output."

Don't snap to the nearest boundary from the _point of release_. Use the velocity to **project the resting position** — exactly like scroll deceleration — then snap to the target closest to that projected point. That's what makes a flick look like it throws the element.

The good news: in SwiftUI, `DragGesture.Value.predictedEndTranslation` already does this projection internally (uses the same deceleration curve as `UIScrollView`). In UIKit, you can replicate Apple's exact function (from the _Designing Fluid Interfaces_ sample code):

```swift
// decelerationRate ≈ 0.998 for normal scroll feel (same value as
// UIScrollView.DecelerationRate.normal); 0.99 for something snappier
func project(initialVelocity: CGFloat, decelerationRate: CGFloat = 0.998) -> CGFloat {
    (initialVelocity / 1000) * decelerationRate / (1 - decelerationRate)
}

let projectedEndpoint = currentPosition + project(initialVelocity: releaseVelocity)
let target = nearestSnapPoint(projectedEndpoint) // pick the target from the projection
animateSpring(to: target, velocity: releaseVelocity) // then do the velocity handoff (§5)
```

```swift
// SwiftUI — using the gesture's native projection
.onEnded { value in
    let projected = value.predictedEndTranslation
    let target = nearestSnapPoint(projected)
    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
        offset = target
    }
}
```

Note: the textbook formula `v²/(2·deceleration)` is **not** what Apple uses — prefer the exponential decay form above, or simply trust SwiftUI's `predictedEndTranslation`, which already implements it.

## 7. Spatial consistency — symmetric paths, anchored origins

> "If something disappears one way, we expect it to reappear where it came from."

- **Enter and exit the same way.** A panel that slides from the right should close to the right. In SwiftUI, use `.transition(.asymmetric(insertion:removal:))` carefully — asymmetry should be intentional, not accidental; by default, prefer symmetric `.move(edge:)`.
- **Anchor interactions to their origin.** A menu, popover, or sheet should originate from the element that triggered it. Use `matchedGeometryEffect(id:in:)` to visually tie the origin to the destination, or set the `anchorPoint` of the `CALayer` (UIKit) at the element that triggered it, so `transform.scale` grows from that point, not the center of the view.
- **Mirror the easing on reversible transitions** so the exit path matches the return path (inverse cubic Bézier curves for both directions, or the same `Spring` both ways).

```swift
// SwiftUI — origin anchored to trigger with matchedGeometryEffect
@Namespace private var animation

// on trigger:
Button("Open") { isExpanded = true }
    .matchedGeometryEffect(id: "card", in: animation)

// at destination:
if isExpanded {
    ExpandedCard()
        .matchedGeometryEffect(id: "card", in: animation)
}
```

## 8. Signalize the direction of the gesture

Humans predict an end state from a trajectory. Intermediate motion should indicate where things are going — Control Center modules "grow upward and outward, toward the finger." Make the in-between frames point toward the outcome, not just interpolate blindly toward it. In SwiftUI, this usually means animating a secondary property (subtle rotation, asymmetric scale) in the same direction as the gesture, not just position.

## 9. Rubber-banding — soft limits

At a limit, resist progressively instead of stopping dry. A dry stop sounds "stuck"; continuous resistance sounds "responsive, but there's nothing more here." Apply damping that increases the more the user drags beyond the limit — it's exactly what `UIScrollView` already does natively (`bounces = true`), and what you need to replicate manually in any custom `DragGesture` with boundaries.

```swift
// The more beyond the limit, the less the element follows — real things slow before stopping
func rubberBand(overshoot: CGFloat, dimension: CGFloat, constant: CGFloat = 0.55) -> CGFloat {
    (overshoot * dimension * constant) / (dimension + constant * abs(overshoot))
}
```

## 10. Gesture design details (checklist of "feel")

- **Tap:** highlight on touch-_down_ (instantaneous), confirm on touch-_up_. In SwiftUI, use `DragGesture(minimumDistance: 0)` instead of pure `TapGesture` when you need feedback in `onChanged`. Add ~10pt of hysteresis/touch padding around the target, and allow canceling by dragging out and back.
- **Drag/swipe:** require a small movement threshold (hysteresis, ~10pt) before committing to a direction — `DragGesture(minimumDistance: 10)` covers this natively.
- **Detect all plausible gestures in parallel from first movement**, then confidently cancel the losers as soon as intent becomes clear. Use `simultaneousGesture`/`highPriorityGesture`/`UIGestureRecognizerDelegate.gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)` to orchestrate this, instead of recognizers that only report a _final_ state.
- **Minimize disambiguation delay.** Double-tap detection (`UITapGestureRecognizer` with `numberOfTapsRequired = 2` + `require(toFail:)`) inevitably delays single-tap; only pay this cost where double-tap actually exists.

## 11. Smoothness at frame level

Smoothness is about _what's in the frames_, not just frame rate.

- Keep the positional change per frame below the perception threshold to avoid "strobing."
- For very fast motion, subtle **motion blur/stretch** encodes velocity and reads better than a sharp, dry stroke.
- `CADisplayLink` is the native clock synchronized to the display (equivalent to using `requestAnimationFrame` on the web); in SwiftUI, `TimelineView(.animation)` serves the same purpose for frame-oriented animations.
- Animate only compositor-friendly properties — `transform`/`offset`/`scaleEffect`/`opacity` — and avoid recalculating layout (`.frame` changing size) each frame of a gesture; prefer `.offset`/`.scaleEffect` over `frame` changes. In UIKit, `layer.shouldRasterize` and `drawsAsynchronously` help only when content is static; don't use on views that are animating.

## 12. Materials and depth — translucency conveys hierarchy

Apple uses translucent materials as a functional floating layer that brings structure without stealing focus. In SwiftUI, this is native via `Material`; in UIKit, via `UIVisualEffectView`.

- **Build navigation bars/toolbars/sheets as translucent layers** (`.background(.ultraThinMaterial)`, `.regularMaterial`, `.thickMaterial`, `.thinMaterial`, `.bar`) with content scrolling underneath — not opaque bars that consume a fixed band.
- **Material weight encodes hierarchy:** darker/heavier materials (`.thickMaterial`) separate structural regions (sidebars); lighter materials (`.ultraThinMaterial`) call attention to interactive elements. **Never stack a light translucent surface over another** — legibility collapses.
- **Larger surfaces should look thicker:** more blur + deeper shadow than small chips. Consider context-aware shadow — heavier over dense/textual content, lighter over simple backgrounds.
- **Darken to focus, separate to keep flow.** A modal task combines the surface with a darkening scrim (`.background(Color.black.opacity(0.3))`) and pushes the background back/down. A parallel, non-blocking panel uses translucency and offset _without_ scrim, to not break the flow. For stacked sheets, progressively darken and push each parent layer.
- **Vibrancy keeps text readable over variable backgrounds.** Over blurred/translucent surfaces, avoid flat gray text — use `.foregroundStyle(.primary)`/`.secondary` (which already apply vibrancy automatically over `Material`) instead of fixed colors.
- **Scroll edge effects, not hard dividers.** Instead of a 1pt border under a fixed header, use a subtle blur/gradient mask where content meets the floating chrome — only where the floating UI actually overlaps content.
- **Materialize, don't just fade away.** For glass/blur surfaces, animate blur radius and scale together on enter/exit, so the surface looks like a real material arriving, not just an opacity fade.

```swift
// SwiftUI
struct Toolbar: View {
    var body: some View {
        HStack { /* content */ }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
```

```swift
// UIKit
let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
let blurView = UIVisualEffectView(effect: blurEffect)
blurView.frame = toolbar.bounds
toolbar.insertSubview(blurView, at: 0)
```

## 13. Multimodal feedback — motion + sound + haptics

Three rules for combining senses (from _Designing Audio-Haptic Experiences_):

1. **Causality** — it must be obvious what caused the feedback. Fire it at the actual causal event (the toggle flipping, the item snapping into place), and match its character to the physicality of the action.
2. **Harmony** — the visual, sound, and haptic must fire in the **same frame**. Latency between them destroys the illusion. Fire the `UIFeedbackGenerator` in the same callback that starts the animation, not in a separate `.onEnded` with a delay.
3. **Utility** — add feedback only where it justifies itself. Reserve haptics/sound for significant moments (success, error, confirmation, snap). Excessive feedback trains the user to ignore everything.

```swift
// Combine visual + haptic in the same instant
let generator = UIImpactFeedbackGenerator(style: .medium)
generator.prepare() // reduces latency of the first fire

func snapToPlace() {
    generator.impactOccurred() // fires along with animation, same frame
    withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
        isSnapped = true
    }
}

// For success/error/warning:
UINotificationFeedbackGenerator().notificationOccurred(.success)
```

## 14. Reduce Motion and accessibility

Reduce Motion doesn't mean _no_ feedback — it means a softer, non-vestibular equivalent. Respond to three independent system signals and bake them into your components:

- **`UIAccessibility.isReduceMotionEnabled`** (or `@Environment(\.accessibilityReduceMotion)` in SwiftUI) — substitute slides/springs/parallax with **short cross-fades of opacity** or static transitions. Remove overshoot/elasticity. Keep opacity/color changes that aid comprehension.
- **`UIAccessibility.isReduceTransparencyEnabled`** (`@Environment(\.accessibilityReduceTransparency)`) — make translucent surfaces more "frosted"/solid: increase background opacity, reduce blur (swap `Material` for a near-opaque color).
- **`UIAccessibility.isDarkerSystemColorsEnabled`** / high contrast — near-solid backgrounds with a defined, contrasting border.

Beyond that: avoid continuous-motion backgrounds filling the entire viewport, slow oscillations in loop (near 0.2 Hz / one cycle every 5s), and abrupt brightness jumps (smooth light↔dark theme transitions). Make large objects in motion semi-transparent while traveling, and fade large surfaces during a wide reposition, returning to normal once they settle.

```swift
struct AdaptiveTransitionView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isPresented = false

    var body: some View {
        content
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            .background(reduceTransparency ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.ultraThinMaterial))
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.85), value: isPresented)
    }
}
```

## 15. Typography — Dynamic Type, tracking, leading

Apple designs type to change form with size; the same discipline applies in Swift. (From _The Details of UI Typography_, WWDC 2020.)

- **Prefer `Font.system(.body, design:)` / `UIFont.preferredFont(forTextStyle:)` to fixed sizes.** The system's text styles (`.largeTitle`, `.title`, `.headline`, `.body`, `.footnote`...) already embed the correct optical sizing of San Francisco for each size — the typeface changes shape, not just scale, as size grows.
- **Tracking (letter-spacing) is size-specific — never a single value for all.** Display text wants _negative_ tracking (letters get too spaced-out as text grows); small text wants slightly _positive_ tracking for legibility. In SwiftUI, use `.tracking(_:)` per size context, not a global fixed value.
- **Leading (line-height/`lineSpacing`) scales inversely with size.** Tight on large titles, looser on body text. Adjust `.lineSpacing(_:)` accordingly.
- **Build hierarchy from weight + size + leading as a set**, not just size. Emphasize with `.fontWeight(_:)` — adds presence without taking up more space.
- **Respect the user's text size setting (Dynamic Type).** Use the system's text styles and `@ScaledMetric` for spacing/icon sizes tied to text, so layout scales _with_ text instead of breaking. Test with `.dynamicTypeSize(...xxxLarge)` in the preview.
- **Prefer the system font (San Francisco) to a custom font** by default; it already comes with optical sizing, tracking tables, and legibility adjustment. Only substitute with clear reason — and if you do, enable `.fontDesign(.rounded)`/`.serif` instead of importing a fully custom font when possible, to retain some of the system's adaptive behavior.

```swift
Text("Emphasis headline")
    .font(.system(.largeTitle, design: .default, weight: .bold))
    .tracking(-0.5) // negative tracking on large text
    .lineSpacing(-2) // tighter leading on large titles

Text("Continuous body text, longer, where legibility matters more than visual impact.")
    .font(.system(.body))
    .tracking(0.1) // slightly positive tracking on small text
    .lineSpacing(4) // looser leading in body
    .dynamicTypeSize(...DynamicTypeSize.accessibility3) // respects user's Dynamic Type
```

## 16. Design fundamentals — the eight principles

The motion and finish above serve Apple's eight design principles (_Principles of Great Design_, WWDC 2026). Use them as the names with which you reason — they are platform-independent, but cited in the original vocabulary for consistency:

1. **Purpose.** Build with intent; decide what _not_ to build. Every feature costs time, attention, and user trust — spend that budget only where it's worth it.
2. **Agency.** Keep people in control: offer choices, not a single path. Reinforce this with forgiveness — easy undo for slips, a confirmation dialog only for genuinely destructive and irreversible actions (use sparingly — excess trains people to click without reading).
3. **Responsibility.** Act in the user's interest. Privacy: ask at the right time, only what's necessary, transparently (use `NSPrivacyUsageDescription` clearly in `Info.plist`). Security: anticipate misuse and harm — especially with AI (a recipe app aware of allergies shouldn't suggest a dangerous ingredient). Add previews, confirmations, warnings; cut a feature whose risk exceeds its value.
4. **Familiarity.** Build on what people already know. Use metaphors that aren't too literal and aren't too abstract (a trash can means delete), and honor their physics. Be consistent: things that look the same should behave the same and live in the same place (close is always top-left on macOS) so people predict what happens next. Break a familiar pattern only if you can prove it's better — then test, don't assume.
5. **Flexibility.** Design for different contexts, devices, and the full range of abilities. Adapt to the platform (iPhone = quick touch; Mac = deep workflows with precise pointer/trackpad control) and the situation. Design inclusively (age, language, expertise, accessibility). When no single layout serves everyone, allow personalization — rearrange controls, hide what's unused.
6. **Simplicity — not minimalism.** Remove the unnecessary so the core purpose shines; burying everything in one place looks minimal, but isn't simple. Be concise (clear language, no jargon, fewer steps) and clear (use hierarchy — order, spacing, contrast — so the most important is most obvious). Every element earns its place; sometimes _adding_ context simplifies (a video scrubber showing time remaining). Show the common path first, advanced options one level below.
7. **Craft.** Relentless attention to detail builds trust. Beautiful typography, colors that adapt to light/dark (`Color(.systemBackground)`, `.primary`, color assets with variants), clear iconography (`SF Symbols` with consistent weights and variants), and responsive animations that give immediate, natural feedback. Nothing is random — every spacing, timing, and alignment value is a deliberate choice you can justify. Twitchy scroll, misaligned icons, and layouts that break on rotation feel careless. Craft requires iteration and longevity — keep evolving the design as features and hardware change.
8. **Delight.** The result of getting the other seven right, not confetti sprinkled on top. Decide what emotion you want people to feel (calm, confident, excited) and reinforce it in every decision.

Tactical rules serving these principles:

- **Feedback comes in four types:** status, completion, warning, error. Confirm significant actions, expose continuous status, warn before problems, validate inline (not just on submit).
- **Spatial orientation.** Every screen should answer: Where am I? Where can I go? What's here? How do I leave? Never trap the user — always offer a clear path back (back button, native system swipe-back gesture shouldn't be blocked without reason).
- **Grouping and mapping.** Proximity implies relation; place a control near what it affects and organize controls mirroring what they change. If you need a label to explain a control, the mapping is weak.
- **Direct and specific labels beat generic and "safe" ones.** Name navigation items by content ("Progress," "Library"), not generic umbrellas ("Home"). Specificity creates predictability.

## 17. Process

- **Prototype interactively — an interactive prototype is worth "a million static designs."** Xcode Playgrounds and SwiftUI Previews let you discover the interface by building and playing with it; a working prototype also sets a concrete bar that prevents a mediocre final implementation.
- **Design interaction and visuals together.** "You shouldn't be able to say where one ends and the other begins." Motion is not a layer added after pixels — think about springs and transitions from the first view sketch, not as a "polish" step at the end.
- **Test with real people in real context**, and review motion with fresh eyes — reproduce in slow motion (reduce simulation speed in Xcode, or use `layer.speed = 0.1` temporarily) to capture what's invisible at normal speed.

## Quick reference

| Need                           | Technique                            | Concrete value / API                                                      |
| ------------------------------ | ------------------------------------ | ------------------------------------------------------------------------- |
| Default UI spring              | Critically damped, no overshoot      | `.spring(response: 0.3–0.4, dampingFraction: 1.0)`                        |
| Momentum/flick spring          | Underdamped, light bounce            | `.spring(response: 0.3–0.4, dampingFraction: ~0.8)`                       |
| Gesture → spring velocity      | Handoff release velocity             | `UISpringTimingParameters(dampingRatio:initialVelocity:)`                 |
| Flick landing point            | Project the momentum                 | `DragGesture.predictedEndTranslation`, or `(v/1000)·d/(1−d)`, `d ≈ 0.998` |
| Clean interrupt                | Start from presentation value (live) | `layer.presentation()`, `UIViewPropertyAnimator.pauseAnimation()`         |
| Avoid "brick wall" on reversal | Carry velocity on re-target          | `UISpringTimingParameters(initialVelocity:)`                              |
| Reversible transition          | Mirror easing curve                  | same `Spring`/inverse Bézier both ways                                    |
| Decide reverse vs. confirm     | Use velocity **sign**, not position  | on release (`velocity(in:)`)                                              |
| 1:1 drag                       | Gesture + offset capture             | `DragGesture`/`UIPanGestureRecognizer`, respecting touch point            |
| Feedback                       | On touch-down, continuous            | never only at end                                                         |
| Limit                          | Rubber-band, not dry stop            | progressive resistance, like `UIScrollView.bounces`                       |
| Translucent chrome             | `Material`/`UIVisualEffectView`      | content scrolls underneath                                                |
| Type tracking                  | Size-specific, never fixed           | tighten large text (`-0.02em`), body near `0`                             |
| Reduce Motion                  | Cross-fade, not slide/spring         | `@Environment(\.accessibilityReduceMotion)`                               |
