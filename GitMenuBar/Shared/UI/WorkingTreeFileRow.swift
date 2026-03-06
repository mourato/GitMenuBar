import SwiftUI

struct WorkingTreeFileRowView: View {
    let file: WorkingTreeFile
    let actionIcon: String
    let actionHelp: String
    let onAction: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(file.path)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 4) {
                Text("+\(file.lineDiff.added)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(file.lineDiff.added > 0 ? .green : .secondary)
                Text("-\(file.lineDiff.removed)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(file.lineDiff.removed > 0 ? .red : .secondary)
            }

            Button(action: onAction) {
                Image(systemName: actionIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(actionHelp)
            .opacity(isHovered ? 1 : 0)
            .frame(width: 16)
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
