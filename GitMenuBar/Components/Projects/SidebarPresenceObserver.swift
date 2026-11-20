import AppKit
import Combine
import SwiftUI

struct SidebarPresenceObserver: NSViewRepresentable {
    let onVisibilityChange: (Bool) -> Void

    func makeNSView(context _: Context) -> PresenceView {
        PresenceView()
    }

    func updateNSView(_ view: PresenceView, context _: Context) {
        view.onVisibilityChange = onVisibilityChange
        view.reportPresence()
    }

    static func dismantleNSView(_ view: PresenceView, coordinator _: ()) {
        view.observation = nil
        view.onVisibilityChange(false)
        view.onVisibilityChange = { _ in }
    }

    final class PresenceView: NSView {
        var onVisibilityChange: (Bool) -> Void = { _ in }
        var observation: AnyCancellable?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observation = nil
            if let window {
                observation = NotificationCenter.default.publisher(
                    for: NSWindow.didChangeOcclusionStateNotification, object: window
                ).sink { [weak self] _ in self?.reportPresence() }
            }
            reportPresence()
        }

        func reportPresence() {
            Task { @MainActor [weak self] in
                guard let self else { return }
                onVisibilityChange(window?.occlusionState.contains(.visible) == true)
            }
        }
    }
}

#Preview("Sidebar Presence Observer") {
    SidebarPresenceObserver(onVisibilityChange: { _ in })
        .frame(width: 1, height: 1)
}
