import SwiftUI

struct HistorySectionHeaderView: View {
    let commitCount: Int
    @Binding var isCollapsed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        WorkbenchSectionHeaderChrome(
            title: "History",
            isCollapsed: $isCollapsed,
            accessibilityLabel: "History section",
            accessibilityHintExpanded: "Expands commit history.",
            accessibilityHintCollapsed: "Collapses commit history."
        ) { _ in
            Text("\(commitCount)")
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(
                    WorkbenchMotion.adaptive(WorkbenchMotion.swap, usesReducedMotion: reduceMotion),
                    value: commitCount
                )
        }
    }
}

private struct HistorySectionHeaderPreviewContainer: View {
    @State private var isCollapsed = false

    var body: some View {
        HistorySectionHeaderView(
            commitCount: 42,
            isCollapsed: $isCollapsed
        )
        .padding()
        .frame(width: 360)
    }
}

#Preview("History Section Header") {
    HistorySectionHeaderPreviewContainer()
}
