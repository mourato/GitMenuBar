import SwiftUI

enum WorkingTreeLayoutMetrics {
    static let actionWidth: CGFloat = 16
    static let diffColumnWidth: CGFloat = 72
    static let trailingContentPadding: CGFloat = 12
}

struct WorkingTreeLineDiffView: View {
    let addedCount: Int
    let removedCount: Int

    var body: some View {
        HStack(spacing: 4) {
            Text("+\(addedCount)")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundColor(addedCount > 0 ? .green : .secondary)
            Text("-\(removedCount)")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundColor(removedCount > 0 ? .red : .secondary)
        }
        .font(.system(size: 12, weight: .medium))
        .monospacedDigit()
        .fixedSize(horizontal: true, vertical: false)
        .frame(minWidth: WorkingTreeLayoutMetrics.diffColumnWidth, alignment: .trailing)
    }
}

struct WorkingTreeFileRowView: View {
    let file: WorkingTreeFile
    let actionIcon: String
    let actionHelp: String
    let onAction: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(file.path)
                .font(.system(size: 12, weight: .regular))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            WorkingTreeLineDiffView(
                addedCount: file.lineDiff.added,
                removedCount: file.lineDiff.removed
            )

            Button(action: onAction) {
                Image(systemName: actionIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(actionHelp)
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
            .frame(width: WorkingTreeLayoutMetrics.actionWidth)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { inside in
            isHovered = inside
        }
    }
}

#Preview("Working Tree File Row") {
    WorkingTreeFileRowView(
        file: WorkingTreeFile(
            path: "GitMenuBar/Features/MainMenu/MainMenuContent.swift",
            lineDiff: LineDiffStats(added: 23, removed: 8)
        ),
        actionIcon: "plus.circle",
        actionHelp: "Stage file",
        onAction: {}
    )
    .padding()
    .frame(width: 380)
}
