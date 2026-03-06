import SwiftUI

enum WorkingTreeLayoutMetrics {
    static let actionWidth: CGFloat = 18
    static let diffColumnWidth: CGFloat = 72
    static let statusColumnWidth: CGFloat = 14
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
            fileLabel

            WorkingTreeLineDiffView(
                addedCount: file.lineDiff.added,
                removedCount: file.lineDiff.removed
            )

            Text(file.status.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(nsColor: file.status.foregroundColor))
                .frame(width: WorkingTreeLayoutMetrics.statusColumnWidth, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { inside in
            isHovered = inside
        }
    }

    private var fileLabel: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 6) {
                Text(file.fileName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .strikethrough(file.status.isDeleted, color: .secondary)

                if !file.directoryPath.isEmpty {
                    Text(file.directoryPath)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer(minLength: 0)
                }
            }

            Button(action: onAction) {
                Image(systemName: actionIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: WorkingTreeLayoutMetrics.actionWidth, height: 16)
                    .background(Color(NSColor.windowBackgroundColor))
            }
            .buttonStyle(.plain)
            .help(actionHelp)
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Working Tree File Row") {
    WorkingTreeFileRowView(
        file: WorkingTreeFile(
            path: "GitMenuBar/Features/MainMenu/MainMenuContent.swift",
            lineDiff: LineDiffStats(added: 23, removed: 8),
            status: .modified
        ),
        actionIcon: "plus.circle",
        actionHelp: "Stage file",
        onAction: {}
    )
    .padding()
    .frame(width: 380)
}
