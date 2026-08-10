import AppKit
import SwiftUI

enum WorkbenchScrollViewStyle {
    static func configureScrollViews(in rootView: NSView) {
        for scrollView in rootView.descendantScrollViews() {
            configure(scrollView)
        }
    }

    private static func configure(_ scrollView: NSScrollView) {
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        if scrollView.hasVerticalScroller {
            scrollView.verticalScroller?.controlSize = .small
        }
        if scrollView.hasHorizontalScroller {
            scrollView.horizontalScroller?.controlSize = .small
        }
    }
}

private struct WorkbenchScrollViewStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(WorkbenchScrollViewStyleProbe().allowsHitTesting(false))
    }
}

extension View {
    func workbenchScrollbarStyle() -> some View {
        modifier(WorkbenchScrollViewStyleModifier())
    }
}

private struct WorkbenchScrollViewStyleProbe: NSViewRepresentable {
    func makeNSView(context _: Context) -> WorkbenchScrollViewStyleProbeView {
        WorkbenchScrollViewStyleProbeView()
    }

    func updateNSView(_ nsView: WorkbenchScrollViewStyleProbeView, context _: Context) {
        nsView.scheduleConfiguration()
    }
}

private final class WorkbenchScrollViewStyleProbeView: NSView {
    private var isConfigurationScheduled = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleConfiguration()
    }

    override func layout() {
        super.layout()
        scheduleConfiguration()
    }

    func scheduleConfiguration() {
        guard !isConfigurationScheduled else { return }

        isConfigurationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            isConfigurationScheduled = false
            if let contentView = window?.contentView {
                WorkbenchScrollViewStyle.configureScrollViews(in: contentView)
            } else {
                WorkbenchScrollViewStyle.configureScrollViews(in: self)
            }
        }
    }
}

private extension NSView {
    func descendantScrollViews() -> [NSScrollView] {
        var scrollViews: [NSScrollView] = []

        if let scrollView = self as? NSScrollView {
            scrollViews.append(scrollView)
        }

        for subview in subviews {
            scrollViews.append(contentsOf: subview.descendantScrollViews())
        }

        return scrollViews
    }
}
