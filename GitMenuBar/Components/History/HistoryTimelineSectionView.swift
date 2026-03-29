import AppKit
import SwiftUI

private enum HistoryTimelineMetrics {
    static let gutterWidth: CGFloat = 18
    static let circleSize: CGFloat = 8
    static let rowContentVerticalPadding: CGFloat = 6
}

struct HistoryTimelineSectionView: View {
    let sections: [HistoryTimelineSectionModel]
    let selectedItemID: MainMenuSelectableItem?
    let isLoading: Bool
    let onSelectRow: (HistoryRowAdapter) -> Void
    let onActivateCommit: (HistoryRowAdapter) -> Void
    let onRestoreCommit: (HistoryRowAdapter) -> Void
    let onEditCommitMessage: (HistoryRowAdapter) -> Void
    let onGenerateCommitMessage: (HistoryRowAdapter) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if sections.isEmpty {
                placeholderView
            } else {
                timelineList
            }
        }
    }

    private var placeholderView: some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Text(isLoading ? "Loading history…" : "No commits yet")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var timelineList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    VStack(spacing: 0) {
                        ForEach(section.rows) { timelineRow in
                            HistoryTimelineRowView(
                                commit: timelineRow.row.commit,
                                commitURL: timelineRow.row.actionSet.commitURL,
                                isCurrentCommit: timelineRow.row.actionSet.isCurrentCommit,
                                isFutureCommit: timelineRow.row.actionSet.isFutureCommit,
                                isSelected: selectedItemID == timelineRow.row.id,
                                showsTopConnector: timelineRow.showsTopConnector,
                                showsBottomConnector: timelineRow.showsBottomConnector,
                                onSelect: {
                                    onSelectRow(timelineRow.row)
                                },
                                onActivate: { onActivateCommit(timelineRow.row) },
                                onRestoreCommit: {
                                    onRestoreCommit(timelineRow.row)
                                },
                                onEditCommitMessage: {
                                    onEditCommitMessage(timelineRow.row)
                                },
                                onGenerateCommitMessage: {
                                    onGenerateCommitMessage(timelineRow.row)
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct HistoryTimelineRowView: View {
    let commit: Commit
    let commitURL: URL?
    let isCurrentCommit: Bool
    let isFutureCommit: Bool
    let isSelected: Bool
    let showsTopConnector: Bool
    let showsBottomConnector: Bool
    let onSelect: () -> Void
    let onActivate: () -> Void
    let onRestoreCommit: () -> Void
    let onEditCommitMessage: () -> Void
    let onGenerateCommitMessage: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            timelineGutter

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(commit.subject)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(titleColor)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if isFutureCommit {
                        Text("Future")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, HistoryTimelineMetrics.rowContentVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: borderLineWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            onSelect()
        }
        .onTapGesture(count: 2) {
            onActivate()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(commit.subject)
        .accessibilityHint("Press Return to open commit details.")
        .contextMenu {
            Button("Open on GitHub") {
                if let commitURL {
                    NSWorkspace.shared.open(commitURL)
                }
            }
            .disabled(commitURL == nil)

            Button("Copy Commit ID") {
                copyToPasteboard(commit.id)
            }

            Button("Copy Commit Message") {
                copyToPasteboard(commit.subject)
            }

            Divider()

            Button("Generate Message with AI") {
                onGenerateCommitMessage()
            }
            .disabled(commit.isMergeCommit)

            Button("Edit Message Manually") {
                onEditCommitMessage()
            }
            .disabled(commit.isMergeCommit)

            if commit.isMergeCommit {
                Button("Editing merge commits is not supported yet.") {}
                    .disabled(true)

                Divider()
            }

            Button("Reset to Here") {
                onRestoreCommit()
            }
            .disabled(isCurrentCommit)
        }
        .onHover { hovered in
            isHovered = hovered

            if hovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private var timelineGutter: some View {
        VStack(spacing: 0) {
            connectorSegment(isVisible: showsTopConnector)

            Circle()
                .fill(circleFillColor)
                .frame(width: HistoryTimelineMetrics.circleSize, height: HistoryTimelineMetrics.circleSize)
                .overlay(
                    Circle()
                        .stroke(circleStrokeColor, lineWidth: isCurrentCommit ? 2 : 1)
                )

            connectorSegment(isVisible: showsBottomConnector)
        }
        .frame(width: HistoryTimelineMetrics.gutterWidth)
    }

    private func connectorSegment(isVisible: Bool) -> some View {
        Rectangle()
            .fill(connectorColor)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .opacity(isVisible ? 1 : 0)
    }

    private var titleColor: Color {
        if isFutureCommit {
            return .blue
        }

        return .primary
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.14)
        }

        if isCurrentCommit {
            return Color.accentColor.opacity(0.08)
        }

        if isHovered {
            return Color.primary.opacity(0.05)
        }

        return Color.clear
    }

    private var borderColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.35)
        }

        if isCurrentCommit {
            return Color.accentColor.opacity(0.35)
        }

        if isHovered {
            return Color.primary.opacity(0.08)
        }

        return .clear
    }

    private var borderLineWidth: CGFloat {
        if isCurrentCommit || isHovered {
            return 1
        }

        return 0
    }

    private var connectorColor: Color {
        isFutureCommit ? Color.blue.opacity(0.65) : Color.secondary.opacity(0.35)
    }

    private var circleFillColor: Color {
        if isCurrentCommit {
            return .accentColor
        }

        if isFutureCommit {
            return .blue
        }

        return Color(nsColor: .windowBackgroundColor)
    }

    private var circleStrokeColor: Color {
        if isCurrentCommit {
            return .accentColor
        }

        if isFutureCommit {
            return .blue
        }

        return Color.secondary.opacity(0.6)
    }
}

#Preview("History Timeline Section") {
    let previewRows = [
        HistoryRowAdapter(
            commit: Commit(
                id: "1234567890abcdef",
                shortHash: "1234567",
                subject: "feat(git): improve status bar and menu item logic",
                body: "",
                authorName: "Renato",
                authorEmail: "renato@example.com",
                committedAt: .now.addingTimeInterval(-3600),
                stats: CommitStats(filesChanged: 5, insertions: 114, deletions: 19),
                changedFiles: [
                    CommitFileChange(
                        path: "GitMenuBar/App/StatusBarController.swift",
                        lineDiff: LineDiffStats(added: 72, removed: 12)
                    )
                ]
            ),
            currentHash: "abcdef1234567890",
            remoteUrl: "https://github.com/example/repo",
            isCommitInFuture: false
        ),
        HistoryRowAdapter(
            commit: Commit(
                id: "abcdef1234567890",
                shortHash: "abcdef1",
                subject: "fix(history): group commits by day",
                body: "",
                authorName: "Renato",
                authorEmail: "renato@example.com",
                committedAt: .now.addingTimeInterval(-86400),
                stats: CommitStats(filesChanged: 2, insertions: 8, deletions: 3),
                changedFiles: []
            ),
            currentHash: "abcdef1234567890",
            remoteUrl: "https://github.com/example/repo",
            isCommitInFuture: false
        )
    ]

    HistoryTimelineSectionView(
        sections: HistoryTimelineSectionModel.build(from: previewRows),
        selectedItemID: .historyCommit(id: "abcdef1234567890"),
        isLoading: false,
        onSelectRow: { _ in },
        onActivateCommit: { _ in },
        onRestoreCommit: { _ in },
        onEditCommitMessage: { _ in },
        onGenerateCommitMessage: { _ in }
    )
    .padding()
    .frame(width: 380)
}
