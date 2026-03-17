import SwiftUI

struct HistorySectionHeaderView: View {
    let commitCount: Int
    @Binding var isCollapsed: Bool

    @State private var isHovered = false

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

            Spacer(minLength: 8)

            Text("\(commitCount)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.gray)
                .background(.white.opacity(0.08))
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isHovered ? Color.primary.opacity(0.08) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onHover { inside in
            isHovered = inside
        }
    }
}
