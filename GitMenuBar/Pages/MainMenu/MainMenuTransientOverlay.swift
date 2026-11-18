import SwiftUI

struct MainMenuTransientOverlay: View {
    let isPresented: Bool
    let quotaSnapshot: UsageQuotaSnapshot?
    let onDismiss: () -> Void
    let onRetryQuota: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if isPresented {
            ZStack {
                transientPresentationScrim
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                    .onTapGesture {
                        onDismiss()
                    }

                transientPanelContent
            }
            .animation(
                WorkbenchMotion.adaptive(WorkbenchMotion.swap, usesReducedMotion: reduceMotion),
                value: isPresented
            )
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var transientPanelContent: some View {
        if let snapshot = quotaSnapshot {
            quotaInfoOverlay(snapshot)
        }
    }

    private func quotaInfoOverlay(_ snapshot: UsageQuotaSnapshot) -> some View {
        HStack {
            QuotaStaleInfoPanel(
                snapshot: snapshot,
                onRetry: onRetryQuota
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.leading, WorkbenchMetrics.windowPadding)
        .padding(.trailing, WorkbenchMetrics.windowPadding)
        .padding(.bottom, WorkbenchMetrics.windowPadding * 2)
        .modifier(TransientPanelChrome(origin: .bottomLeading, reduceMotion: reduceMotion))
    }

    @ViewBuilder
    private var transientPresentationScrim: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            Color.black.opacity(0.05)
        }
    }

    private struct TransientPanelChrome: ViewModifier {
        let origin: WorkbenchMotion.TransientPanelOrigin
        let reduceMotion: Bool

        func body(content: Content) -> some View {
            content
                .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 8)
                .accessibilityAddTraits(.isModal)
                .transition(WorkbenchMotion.transientPanelTransition(from: origin, usesReducedMotion: reduceMotion))
        }
    }
}

#Preview("Transient Quota Overlay") {
    MainMenuTransientOverlay(
        isPresented: true,
        quotaSnapshot: UsageQuotaSnapshot(
            providerID: .openrouter,
            displayName: "OpenRouter",
            sessionWindow: UsageWindow(remainingPercent: 42, resetAt: nil, label: "Credits"),
            weeklyWindow: nil,
            creditValueText: "$12.50 left",
            isAvailable: true,
            isStale: true,
            statusNote: "openrouter credits api",
            fetchedAt: Date().addingTimeInterval(-7200)
        ),
        onDismiss: {},
        onRetryQuota: {}
    )
    .frame(width: 420, height: 200)
}
