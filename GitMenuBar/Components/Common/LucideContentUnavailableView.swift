import SwiftUI

/// Centered empty-state layout rendered through the Lucide catalog.
/// Apple's content-unavailable view only accepts SF Symbol names,
/// so every empty state in the app uses this view instead.
struct LucideContentUnavailableView<Content: View>: View {
    private let title: String
    private let icon: LucideIconName
    private let content: Content

    init(
        _ title: String,
        icon: LucideIconName,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(spacing: WorkbenchMetrics.compactSpacing) {
            LucideIconView(name: icon, size: 32)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            content
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

extension LucideContentUnavailableView where Content == EmptyView {
    init(_ title: String, icon: LucideIconName) {
        self.init(title, icon: icon) { EmptyView() }
    }
}

#Preview("Lucide Empty State") {
    LucideContentUnavailableView("No Open Issues", icon: .circleCheck) {
        Text("This repository has no open issues.")
        Button("Refresh") {}
            .buttonStyle(.borderless)
    }
    .padding()
    .frame(width: 320, height: 240)
}
