import SwiftUI

struct MainMenuTransientOverlay: View {
    let isPresented: Bool
    let showsRepositoryOptions: Bool
    let visibilityStatusDescription: String
    let visibilityActionTitle: String
    let quotaSnapshot: UsageQuotaSnapshot?
    let onToggleVisibility: () -> Void
    let onDeleteRepository: () -> Void
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
        if showsRepositoryOptions {
            topCenteredOverlay(repositoryOptionsOverlay)
        } else if let snapshot = quotaSnapshot {
            quotaInfoOverlay(snapshot)
        }
    }

    private func topCenteredOverlay(_ overlay: some View) -> some View {
        HStack {
            Spacer(minLength: 0)
            overlay
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, WorkbenchMetrics.sectionSpacing)
        .padding(.horizontal, WorkbenchMetrics.windowPadding)
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

    private var repositoryOptionsOverlay: some View {
        RepositoryOptionsPopoverView(
            visibilityStatusDescription: visibilityStatusDescription,
            visibilityActionTitle: visibilityActionTitle,
            onToggleVisibility: onToggleVisibility,
            onDeleteRepository: onDeleteRepository
        )
        .modifier(TransientPanelChrome(origin: .topCenter, reduceMotion: reduceMotion))
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
