import SwiftUI

struct WorkingTreeSectionHeaderView: View {
    let title: String
    let summary: WorkingTreeSectionSummary
    @Binding var isCollapsed: Bool
    let actionIcon: String
    let actionHelp: String
    let showsAction: Bool
    let onAction: () -> Void
    var onDiscardAll: (() -> Void)?

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

                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            ZStack(alignment: .trailing) {
                WorkingTreeLineDiffView(
                    addedCount: summary.addedLineCount,
                    removedCount: summary.removedLineCount
                )
                .opacity(isHovered && showsAction ? 0 : 1)

                HStack(spacing: 4) {
                    if let onDiscardAll {
                        Button(action: onDiscardAll) {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                                .frame(width: WorkingTreeLayoutMetrics.actionWidth, height: 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Discard All")
                    }

                    Button(action: onAction) {
                        Image(systemName: actionIcon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: WorkingTreeLayoutMetrics.actionWidth, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(actionHelp)
                }
                .opacity(isHovered && showsAction ? 1 : 0)
                .allowsHitTesting(isHovered && showsAction)
            }

            Text(summary.fileCountText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.gray)
                .frame(width: 16, height: 16, alignment: .center)
                .background(.white.opacity(0.08))
                .clipShape(Circle())
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
