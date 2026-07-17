import SwiftUI

struct HistorySectionHeaderView: View {
    let commitCount: Int
    @Binding var isCollapsed: Bool

    @State private var isHovered = false
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(
                    MacChromeMotion.adaptive(MacChromeMotion.settle, usesReducedMotion: reduceMotion)
                ) {
                    isCollapsed.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(MacChromeTypography.captionStrong)
                        .foregroundColor(.secondary)
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))

                    Text("History")
                        .font(MacChromeTypography.body)
                }
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("History section")
            .accessibilityHint(isCollapsed ? "Expands commit history." : "Collapses commit history.")

            Spacer(minLength: 8)

            Text("\(commitCount)")
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(
                    MacChromeMotion.adaptive(MacChromeMotion.swap, usesReducedMotion: reduceMotion),
                    value: commitCount
                )
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isHovered ? Color.primary.opacity(0.08) : Color.clear)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.secondary.opacity(colorSchemeContrast == .increased ? 0.45 : 0), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .animation(
            MacChromeMotion.adaptive(MacChromeMotion.micro, usesReducedMotion: reduceMotion),
            value: isHovered
        )
        .onHover { inside in
            isHovered = inside
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
