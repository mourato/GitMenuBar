import SwiftUI

struct HistorySectionHeaderView: View {
    let commitCount: Int
    @Binding var isCollapsed: Bool

    @State private var isHovered = false
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isCollapsed.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)

                    Text("History")
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("History section")
            .accessibilityHint(isCollapsed ? "Expands commit history." : "Collapses commit history.")

            Spacer(minLength: 8)

            Text("\(commitCount)")
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
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
