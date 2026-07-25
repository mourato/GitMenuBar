import SwiftUI

enum WorkingTreeLayoutMetrics {
    /// Minimum interactive target for row/header icon actions (≥ `WorkbenchMetrics.iconHitTarget`).
    static let actionHitTarget: CGFloat = 32
    static let diffColumnWidth: CGFloat = 72
    static let statusColumnWidth: CGFloat = 14
    static let trailingContentPadding: CGFloat = 12
}

struct WorkingTreeLineDiffView: View {
    let addedCount: Int
    let removedCount: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("+\(addedCount)")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundColor(addedCount > 0 ? .green : .secondary)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(
                    WorkbenchMotion.adaptive(WorkbenchMotion.swap, usesReducedMotion: reduceMotion),
                    value: addedCount
                )
            Text("-\(removedCount)")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundColor(removedCount > 0 ? .red : .secondary)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(
                    WorkbenchMotion.adaptive(WorkbenchMotion.swap, usesReducedMotion: reduceMotion),
                    value: removedCount
                )
        }
        .font(WorkbenchTypography.captionStrong)
        .monospacedDigit()
        .fixedSize(horizontal: true, vertical: false)
    }
}

private func workingTreeRowIconButton(
    systemName: String,
    help: String,
    accessibilityLabel: String,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        Image(systemName: systemName)
            .font(WorkbenchTypography.captionStrong)
            .foregroundColor(.primary)
            .frame(
                width: WorkingTreeLayoutMetrics.actionHitTarget,
                height: WorkingTreeLayoutMetrics.actionHitTarget
            )
            .contentShape(Rectangle())
    }
    .workbenchIcon()
    .help(help)
    .accessibilityLabel(accessibilityLabel)
}

struct WorkingTreeFileRowView: View {
    let file: WorkingTreeFile
    let actionIcon: String
    let actionHelp: String
    var isSelected = false
    var onSelect: (() -> Void)?
    let onAction: () -> Void
    var onOpen: (() -> Void)?
    var onDiscard: (() -> Void)?
    var onReveal: (() -> Void)?

    @State private var isHovered = false
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            fileLabel

            Text(file.status.symbol)
                .font(WorkbenchTypography.body.weight(.semibold))
                .foregroundColor(Color(nsColor: file.status.foregroundColor))
                .frame(width: WorkingTreeLayoutMetrics.statusColumnWidth, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(backgroundColor)
        .cornerRadius(4)
        .padding(.horizontal, -4) // Offset the internal padding so the row maintains its original width while letting the background expand
        .contentShape(Rectangle())
        .animation(
            WorkbenchMotion.adaptive(WorkbenchMotion.micro, usesReducedMotion: reduceMotion),
            value: isHovered
        )
        .onTapGesture {
            onSelect?()
        }
        .onTapGesture(count: 2) {
            onOpen?()
        }
        .onHover { inside in
            isHovered = inside
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Press Return to open, or Delete to discard when available.")
        .contextMenu {
            Button("Open File") {
                onOpen?()
            }
            Button("Discard Changes") {
                onDiscard?()
            }
            Button(actionHelp) {
                onAction()
            }
            Divider()
            Button("Reveal in Finder") {
                onReveal?()
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(action: onAction) {
                Label(actionHelp, systemImage: actionIcon)
            }
            .tint(.accentColor)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if let onDiscard {
                Button(role: .destructive, action: onDiscard) {
                    Label("Discard", systemImage: "arrow.uturn.backward")
                }
            }
        }
        .pressable()
    }

    private var fileLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(file.fileName)
                .font(WorkbenchTypography.body)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
                .strikethrough(file.status.isDeleted, color: .secondary)

            if !file.directoryPath.isEmpty {
                Text(file.directoryPath)
                    .font(WorkbenchTypography.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(0)
            }

            Spacer(minLength: 4)

            ZStack(alignment: .trailing) {
                WorkingTreeLineDiffView(
                    addedCount: file.lineDiff.added,
                    removedCount: file.lineDiff.removed
                )
                .opacity(isHovered ? 0 : 1)

                HStack(spacing: 0) {
                    if let onOpen = onOpen {
                        workingTreeRowIconButton(
                            systemName: "doc",
                            help: "Open File",
                            accessibilityLabel: "Open \(file.fileName)",
                            action: onOpen
                        )
                    }

                    if let onDiscard = onDiscard {
                        workingTreeRowIconButton(
                            systemName: "arrow.uturn.backward",
                            help: "Discard Changes",
                            accessibilityLabel: "Discard changes in \(file.fileName)",
                            action: onDiscard
                        )
                    }

                    workingTreeRowIconButton(
                        systemName: actionIcon,
                        help: actionHelp,
                        accessibilityLabel: "\(actionHelp) for \(file.fileName)",
                        action: onAction
                    )
                }
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
            }
            .layoutPriority(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 10)
        .clipped()
    }

    private var accessibilityLabel: String {
        var value = file.fileName
        if !file.directoryPath.isEmpty {
            value += ", \(file.directoryPath)"
        }
        value += ", status \(file.status.symbol)"
        return value
    }

    private var backgroundColor: Color {
        if isSelected {
            return WorkbenchPalette.selectedFill()
        }

        if isHovered {
            return WorkbenchPalette.hoverFill()
        }

        return Color.clear
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
        isSelected: true,
        onSelect: {},
        onAction: {},
        onOpen: {},
        onDiscard: {},
        onReveal: {}
    )
    .padding()
    .frame(width: 380)
}
