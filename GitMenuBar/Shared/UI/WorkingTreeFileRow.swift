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
        HStack(alignment: .firstTextBaseline, spacing: 4) {
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

            Text(file.status.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(nsColor: file.status.foregroundColor))
                .frame(width: WorkingTreeLayoutMetrics.statusColumnWidth, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        .cornerRadius(4)
        .padding(.horizontal, -4) // Offset the internal padding so the row maintains its original width while letting the background expand
        .contentShape(Rectangle())
        .onHover { inside in
            isHovered = inside
        }
    }

    private var fileLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(file.fileName)
                .font(.system(size: 13, weight: .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
                .strikethrough(file.status.isDeleted, color: .secondary)

            if !file.directoryPath.isEmpty {
                Text(file.directoryPath)
                    .font(.system(size: 11, weight: .light))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(0)
            }

            ZStack(alignment: .trailing) {
                WorkingTreeLineDiffView(
                    addedCount: file.lineDiff.added,
                    removedCount: file.lineDiff.removed
                )
                .opacity(isHovered ? 0 : 1)

                Button(action: onAction) {
                    Image(systemName: actionIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.primary)
                        .frame(width: WorkingTreeLayoutMetrics.actionWidth, height: 16)
                        .contentShape(Rectangle()) // makes the whole frame clickable
                }
                .buttonStyle(.plain)
                .help(actionHelp)
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
            }
            .layoutPriority(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 10)
        .clipped()
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
