import AppKit
import SwiftUI

struct WorkbenchEdgeDissolveMetrics: Equatable {
    let contentOffset: CGFloat
    let contentHeight: CGFloat
    let containerHeight: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat

    var isScrollable: Bool {
        contentHeight > max(0, containerHeight - topInset - bottomInset) + 1
    }

    var topDistance: CGFloat {
        max(0, contentOffset + topInset)
    }

    var bottomDistance: CGFloat {
        max(0, contentHeight - (contentOffset + containerHeight - bottomInset))
    }
}

struct WorkbenchScrollbarMetrics: Equatable {
    let contentOffset: CGFloat
    let contentHeight: CGFloat
    let containerHeight: CGFloat
    let topInset: CGFloat

    var isScrollable: Bool {
        contentHeight > containerHeight + 1
    }

    func thumbHeight(in trackHeight: CGFloat) -> CGFloat {
        guard contentHeight > 0 else { return WorkbenchMetrics.scrollbarMinimumThumbHeight }
        return min(trackHeight, max(
            WorkbenchMetrics.scrollbarMinimumThumbHeight,
            trackHeight * containerHeight / contentHeight
        ))
    }

    func thumbOffset(in trackHeight: CGFloat) -> CGFloat {
        let thumbHeight = thumbHeight(in: trackHeight)
        let maximumOffset = max(0, contentHeight - containerHeight)
        guard maximumOffset > 0 else { return WorkbenchMetrics.scrollbarInset }
        let fraction = min(1, max(0, (contentOffset + topInset) / maximumOffset))
        return WorkbenchMetrics.scrollbarInset + fraction * max(0, trackHeight - thumbHeight)
    }
}

private struct WorkbenchEdgeDissolveModifier: ViewModifier {
    @State private var metrics = WorkbenchEdgeDissolveMetrics(
        contentOffset: 0,
        contentHeight: 0,
        containerHeight: 0,
        topInset: 0,
        bottomInset: 0
    )

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: WorkbenchEdgeDissolveMetrics.self) { geometry in
                WorkbenchEdgeDissolveMetrics(
                    contentOffset: geometry.contentOffset.y,
                    contentHeight: geometry.contentSize.height,
                    containerHeight: geometry.containerSize.height,
                    topInset: geometry.contentInsets.top,
                    bottomInset: geometry.contentInsets.bottom
                )
            } action: { _, newMetrics in
                metrics = newMetrics
            }
            .mask {
                if metrics.isScrollable {
                    WorkbenchEdgeDissolveMask(metrics: metrics)
                        .ignoresSafeArea()
                } else {
                    Color.white
                }
            }
    }
}

private struct WorkbenchEdgeDissolveMask: View {
    let metrics: WorkbenchEdgeDissolveMetrics

    var body: some View {
        GeometryReader { proxy in
            let topBand = min(metrics.topInset + WorkbenchMetrics.scrollEdgeTopBand, proxy.size.height / 2)
            let bottomBand = min(metrics.bottomInset + WorkbenchMetrics.scrollEdgeBottomBand, proxy.size.height / 2)
            let topOpacity = edgeOpacity(distance: metrics.topDistance, band: topBand, floor: 0.15)
            let bottomOpacity = edgeOpacity(distance: metrics.bottomDistance, band: bottomBand, floor: 0.25)

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0),
                    .init(color: .black.opacity(topOpacity), location: topBand / 2 / proxy.size.height),
                    .init(color: .black, location: topBand / proxy.size.height),
                    .init(color: .black, location: 1 - bottomBand / proxy.size.height),
                    .init(color: .black.opacity(bottomOpacity), location: 1 - bottomBand / 2 / proxy.size.height),
                    .init(color: .black.opacity(0), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func edgeOpacity(distance: CGFloat, band: CGFloat, floor: CGFloat) -> Double {
        guard band > 0 else { return 1 }
        let progress = min(max(distance / band, 0), 1)
        return Double(1 - (1 - floor) * progress)
    }
}

private struct WorkbenchThinScrollbarModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isScrolling = false
    @State private var isHoveringTrack = false
    @State private var isDragging = false
    @State private var metrics = WorkbenchScrollbarMetrics(contentOffset: 0, contentHeight: 0, containerHeight: 0, topInset: 0)
    @State private var scrollStop: Task<Void, Never>?

    private var isVisible: Bool {
        isScrolling || isHoveringTrack || isDragging
    }

    private var isExpanded: Bool {
        isHoveringTrack || isDragging
    }

    private var fadeAnimation: Animation? {
        reduceMotion ? nil : WorkbenchMotion.scrollbarFade
    }

    private var morphAnimation: Animation? {
        reduceMotion ? nil : WorkbenchMotion.scrollbarMorph
    }

    func body(content: Content) -> some View {
        content
            .scrollIndicators(.hidden)
            .background(WorkbenchNativeScrollerHider().allowsHitTesting(false))
            .onScrollGeometryChange(for: WorkbenchScrollbarMetrics.self) { geometry in
                WorkbenchScrollbarMetrics(
                    contentOffset: geometry.contentOffset.y,
                    contentHeight: geometry.contentSize.height,
                    containerHeight: geometry.containerSize.height,
                    topInset: geometry.contentInsets.top
                )
            } action: { _, newMetrics in
                metrics = newMetrics
            }
            .onScrollPhaseChange { _, phase in
                guard !isDragging else { return }
                if phase == .idle {
                    scheduleScrollStop()
                } else {
                    beginScrolling()
                }
            }
            .overlay(alignment: .topTrailing) { scrollbar }
            .overlay {
                WorkbenchScrollbarInteraction(
                    edgeWidth: WorkbenchMetrics.scrollbarHoverZone,
                    inset: WorkbenchMetrics.scrollbarInset,
                    thumbY: thumbOffset,
                    thumbHeight: thumbHeight,
                    thumbGrabbable: metrics.isScrollable && isVisible,
                    railActive: metrics.isScrollable && isExpanded,
                    onZoneChange: updateHover,
                    onDragChange: updateDragging
                )
            }
    }

    @ViewBuilder
    private var scrollbar: some View {
        if metrics.isScrollable {
            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: WorkbenchMetrics.scrollbarExpandedWidth, height: trackHeight)
                    .offset(y: WorkbenchMetrics.scrollbarInset)
                    .opacity(isExpanded ? 1 : 0)
                Capsule()
                    .fill(Color.primary.opacity(isDragging ? 0.5 : (isExpanded ? 0.42 : 0.30)))
                    .frame(width: isExpanded ? WorkbenchMetrics.scrollbarExpandedWidth : WorkbenchMetrics.scrollbarWidth, height: thumbHeight)
                    .frame(width: WorkbenchMetrics.scrollbarExpandedWidth)
                    .offset(y: thumbOffset)
                    .opacity(isVisible ? 1 : 0)
            }
            .frame(width: WorkbenchMetrics.scrollbarExpandedWidth)
            .padding(.trailing, WorkbenchMetrics.scrollbarInset)
            .allowsHitTesting(false)
        }
    }

    private var trackHeight: CGFloat {
        max(0, metrics.containerHeight - WorkbenchMetrics.scrollbarInset * 2)
    }

    private var thumbHeight: CGFloat {
        metrics.thumbHeight(in: trackHeight)
    }

    private var thumbOffset: CGFloat {
        metrics.thumbOffset(in: trackHeight)
    }

    private func beginScrolling() {
        scrollStop?.cancel()
        withAnimation(fadeAnimation) { isScrolling = true }
    }

    private func scheduleScrollStop() {
        scrollStop?.cancel()
        scrollStop = Task { @MainActor in
            try? await Task.sleep(for: WorkbenchMotion.scrollbarFadeDelay)
            guard !Task.isCancelled else { return }
            withAnimation(fadeAnimation) { isScrolling = false }
        }
    }

    private func updateHover(_ isHovering: Bool) {
        guard isHovering != isHoveringTrack else { return }
        withAnimation(morphAnimation) { isHoveringTrack = isHovering }
    }

    private func updateDragging(_ isDragging: Bool) {
        withAnimation(morphAnimation) { self.isDragging = isDragging }
        if isDragging {
            scrollStop?.cancel()
        } else {
            beginScrolling(); scheduleScrollStop()
        }
    }
}

private struct WorkbenchNativeScrollerHider: NSViewRepresentable {
    func makeNSView(context _: Context) -> HiderView {
        HiderView()
    }

    func updateNSView(_ nsView: HiderView, context _: Context) {
        nsView.apply()
    }

    final class HiderView: NSView {
        private var retriesLeft = 10

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            retriesLeft = 10
            apply()
        }

        func apply() {
            guard let scrollView = enclosingScrollView else {
                guard retriesLeft > 0 else { return }
                retriesLeft -= 1
                DispatchQueue.main.async { [weak self] in self?.apply() }
                return
            }
            scrollView.scrollerStyle = .overlay
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.tile()
        }
    }
}

private struct WorkbenchScrollbarInteraction: NSViewRepresentable {
    let edgeWidth: CGFloat
    let inset: CGFloat
    let thumbY: CGFloat
    let thumbHeight: CGFloat
    let thumbGrabbable: Bool
    let railActive: Bool
    let onZoneChange: @MainActor (Bool) -> Void
    let onDragChange: @MainActor (Bool) -> Void

    func makeNSView(context _: Context) -> InteractionView {
        InteractionView(onZoneChange: onZoneChange, onDragChange: onDragChange)
    }

    func updateNSView(_ nsView: InteractionView, context _: Context) {
        nsView.edgeWidth = edgeWidth
        nsView.inset = inset
        nsView.thumbY = thumbY
        nsView.thumbHeight = thumbHeight
        nsView.thumbGrabbable = thumbGrabbable
        nsView.railActive = railActive
        nsView.onZoneChange = onZoneChange
        nsView.onDragChange = onDragChange
    }

    final class InteractionView: NSView {
        var edgeWidth: CGFloat = 0
        var inset: CGFloat = 0
        var thumbY: CGFloat = 0
        var thumbHeight: CGFloat = 0
        var thumbGrabbable = false
        var railActive = false
        var onZoneChange: @MainActor (Bool) -> Void
        var onDragChange: @MainActor (Bool) -> Void
        private var lastInZone = false
        private var dragStart: (pointerY: CGFloat, offset: CGFloat)?
        private weak var scrollView: NSScrollView?

        init(onZoneChange: @escaping @MainActor (Bool) -> Void, onDragChange: @escaping @MainActor (Bool) -> Void) {
            self.onZoneChange = onZoneChange
            self.onDragChange = onDragChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        override var isFlipped: Bool {
            true
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let superview else { return nil }
            let localPoint = convert(point, from: superview)
            return grabRect.contains(localPoint) || railActive && localPoint.x >= bounds.width - edgeWidth ? self : nil
        }

        override func scrollWheel(with event: NSEvent) {
            targetScrollView()?.scrollWheel(with: event) ?? super.scrollWheel(with: event)
        }

        override func mouseDown(with event: NSEvent) {
            guard let scrollView = targetScrollView() else { return }
            let point = convert(event.locationInWindow, from: nil)
            if !grabRect.contains(point) {
                jumpThumb(to: point.y, in: scrollView)
            }
            dragStart = (point.y, scrollView.contentView.bounds.origin.y)
            onDragChange(true)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let dragStart, let scrollView = targetScrollView() else { return }
            let (minimumOffset, maximumOffset) = offsetRange(of: scrollView.contentView)
            let travel = trackTravel
            guard maximumOffset > minimumOffset, travel > 0 else { return }
            let point = convert(event.locationInWindow, from: nil)
            let offset = dragStart.offset + (point.y - dragStart.pointerY) / travel * (maximumOffset - minimumOffset)
            scroll(scrollView, to: min(maximumOffset, max(minimumOffset, offset)))
        }

        override func mouseUp(with _: NSEvent) {
            guard dragStart != nil else { return }
            dragStart = nil
            onDragChange(false)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }

        override func mouseMoved(with event: NSEvent) {
            report(event)
        }

        override func mouseEntered(with event: NSEvent) {
            report(event)
        }

        override func mouseExited(with _: NSEvent) {
            updateHover(false)
        }

        private var grabRect: CGRect {
            guard thumbGrabbable else { return .null }
            return CGRect(x: bounds.width - edgeWidth, y: thumbY, width: edgeWidth, height: thumbHeight)
        }

        private var trackTravel: CGFloat {
            bounds.height - inset * 2 - thumbHeight
        }

        private func report(_ event: NSEvent) {
            updateHover(convert(event.locationInWindow, from: nil).x >= bounds.width - edgeWidth)
        }

        private func updateHover(_ isHovering: Bool) {
            guard isHovering != lastInZone else { return }
            lastInZone = isHovering
            onZoneChange(isHovering)
        }

        private func jumpThumb(to pointerY: CGFloat, in scrollView: NSScrollView) {
            let (minimumOffset, maximumOffset) = offsetRange(of: scrollView.contentView)
            guard maximumOffset > minimumOffset, trackTravel > 0 else { return }
            let thumbTop = min(inset + trackTravel, max(inset, pointerY - thumbHeight / 2))
            scroll(scrollView, to: minimumOffset + (thumbTop - inset) / trackTravel * (maximumOffset - minimumOffset))
        }

        private func offsetRange(of clipView: NSClipView) -> (minimum: CGFloat, maximum: CGFloat) {
            var probe = clipView.bounds
            probe.origin.y = -1_000_000_000
            let minimum = clipView.constrainBoundsRect(probe).origin.y
            probe.origin.y = 1_000_000_000
            let maximum = clipView.constrainBoundsRect(probe).origin.y
            return (minimum, maximum)
        }

        private func scroll(_ scrollView: NSScrollView, to offsetY: CGFloat) {
            let clipView = scrollView.contentView
            var origin = clipView.bounds.origin
            origin.y = offsetY
            clipView.scroll(to: origin)
            scrollView.reflectScrolledClipView(clipView)
        }

        private func targetScrollView() -> NSScrollView? {
            if let scrollView, scrollView.window === window {
                return scrollView
            }
            var branch: NSView = self
            var ancestor = superview
            while let current = ancestor {
                if let found = Self.firstScrollView(under: current, excluding: branch) {
                    scrollView = found
                    return found
                }
                branch = current
                ancestor = current.superview
            }
            return nil
        }

        private static func firstScrollView(under view: NSView, excluding: NSView?) -> NSScrollView? {
            for subview in view.subviews where subview !== excluding {
                if let scrollView = subview as? NSScrollView {
                    return scrollView
                }
                if let scrollView = firstScrollView(under: subview, excluding: nil) {
                    return scrollView
                }
            }
            return nil
        }
    }
}

extension View {
    func workbenchEdgeDissolve() -> some View {
        modifier(WorkbenchEdgeDissolveModifier())
    }

    func workbenchThinScrollbar() -> some View {
        modifier(WorkbenchThinScrollbarModifier())
    }
}

#Preview("Workbench scroll effects") {
    VStack(spacing: WorkbenchMetrics.groupSpacing) {
        ScrollView {
            Text("Short content")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .workbenchEdgeDissolve()
        .workbenchThinScrollbar()
        .frame(height: 70)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                ForEach(0 ..< 30, id: \.self) { index in
                    Text("Scrollable item \(index)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .workbenchEdgeDissolve()
        .workbenchThinScrollbar()
        .frame(height: 220)
    }
    .padding()
    .frame(width: 320)
}
