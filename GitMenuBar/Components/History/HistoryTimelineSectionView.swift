import AppKit
import SwiftUI

struct HistoryTimelineSectionView: View {
    let sections: [HistoryTimelineSectionModel]
    let selectedItemID: MainMenuSelectableItem?
    let isLoading: Bool
    let animationNamespace: Namespace.ID
    let onSelectRow: (HistoryRowAdapter) -> Void
    let onActivateCommit: (HistoryRowAdapter) -> Void
    let onRestoreCommit: (HistoryRowAdapter) -> Void
    let onEditCommitMessage: (HistoryRowAdapter) -> Void
    let onGenerateCommitMessage: (HistoryRowAdapter) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
            if sections.isEmpty {
                placeholderView
            } else {
                timelineList
            }
        }
    }

    @ViewBuilder
    private var placeholderView: some View {
        if isLoading {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                ForEach(0 ..< 3, id: \.self) { _ in
                    HStack(spacing: WorkbenchMetrics.compactSpacing) {
                        Circle()
                            .fill(.tertiary)
                            .frame(width: WorkbenchMetrics.chipSpacing, height: WorkbenchMetrics.chipSpacing)
                            .accessibilityHidden(true)
                        RoundedRectangle(cornerRadius: WorkbenchMetrics.microCornerRadius)
                            .fill(.tertiary)
                            .frame(height: WorkbenchMetrics.compactSpacing)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, WorkbenchMetrics.chipSpacing)
                    .redacted(reason: .placeholder)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading history")
            .accessibilityAddTraits(.updatesFrequently)
        } else {
            Text("No commits yet")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var timelineList: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: WorkbenchMetrics.chipSpacing) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(section.title)
                        Spacer(minLength: WorkbenchMetrics.compactSpacing)
                        Text(section.rows.count == 1 ? "1 commit" : "\(section.rows.count) commits")
                            .monospacedDigit()
                    }
                    .font(WorkbenchTypography.captionStrong)
                    .foregroundStyle(.secondary)
                    .padding(.top, WorkbenchMetrics.sectionSpacing)
                    .padding(.trailing, WorkbenchMetrics.compactSpacing)
                    .accessibilityElement(children: .combine)

                    VStack(spacing: WorkbenchMetrics.microSpacing) {
                        ForEach(section.rows) { timelineRow in
                            HistoryTimelineRowView(
                                commit: timelineRow.row.commit,
                                commitURL: timelineRow.row.actionSet.commitURL,
                                isCurrentCommit: timelineRow.row.actionSet.isCurrentCommit,
                                isFutureCommit: timelineRow.row.actionSet.isFutureCommit,
                                isSelected: selectedItemID == timelineRow.row.id,
                                animationNamespace: animationNamespace,
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
    let animationNamespace: Namespace.ID
    let onSelect: () -> Void
    let onActivate: () -> Void
    let onRestoreCommit: () -> Void
    let onEditCommitMessage: () -> Void
    let onGenerateCommitMessage: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private let parsedSubject: ConventionalCommitSubject
    private let relativeTimestamp: String

    init(
        commit: Commit,
        commitURL: URL?,
        isCurrentCommit: Bool,
        isFutureCommit: Bool,
        isSelected: Bool,
        animationNamespace: Namespace.ID,
        onSelect: @escaping () -> Void,
        onActivate: @escaping () -> Void,
        onRestoreCommit: @escaping () -> Void,
        onEditCommitMessage: @escaping () -> Void,
        onGenerateCommitMessage: @escaping () -> Void
    ) {
        self.commit = commit
        self.commitURL = commitURL
        self.isCurrentCommit = isCurrentCommit
        self.isFutureCommit = isFutureCommit
        self.isSelected = isSelected
        self.animationNamespace = animationNamespace
        self.onSelect = onSelect
        self.onActivate = onActivate
        self.onRestoreCommit = onRestoreCommit
        self.onEditCommitMessage = onEditCommitMessage
        self.onGenerateCommitMessage = onGenerateCommitMessage
        parsedSubject = ConventionalCommitSubjectParser.parse(commit.subject)
        relativeTimestamp = HistoryTimelineDateFormatter.relativeTimestamp(for: commit.committedAt)
    }

    var body: some View {
        HStack(alignment: .center, spacing: WorkbenchMetrics.compactSpacing) {
            stateDot

            HStack(alignment: .firstTextBaseline, spacing: WorkbenchMetrics.sectionSpacing) {
                subjectLine
                metadataLine
            }
            .padding(.vertical, commit.isMergeCommit ? WorkbenchMetrics.microSpacing : WorkbenchMetrics.chipSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, WorkbenchMetrics.compactSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
        .animation(
            WorkbenchMotion.adaptive(WorkbenchMotion.micro, usesReducedMotion: reduceMotion),
            value: isHovered
        )
        .onHover { isHovered = $0 }
        .onTapGesture {
            onSelect()
        }
        .onTapGesture(count: 2) {
            onActivate()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let commitURL {
                Button {
                    NSWorkspace.shared.open(commitURL)
                } label: {
                    Label("Open on GitHub", systemImage: "arrow.up.forward.app")
                }
                .tint(.accentColor)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                onEditCommitMessage()
            } label: {
                Label("Edit Message", systemImage: "pencil")
            }
            .tint(.accentColor)
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private var subjectLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: WorkbenchMetrics.chipSpacing) {
            if let type = knownType {
                Text(parsedSubject.isBreaking ? "\(type)!" : type)
                    .font(WorkbenchTypography.captionStrong)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, WorkbenchMetrics.chipSpacing)
                    .padding(.vertical, WorkbenchMetrics.headerVerticalPadding)
                    .background(WorkbenchPalette.hoverFill())
                    .clipShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.microCornerRadius, style: .continuous))

                if let scope = parsedSubject.scope {
                    Text("(\(scope))")
                        .font(WorkbenchTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Text(displaySubject)
                .font(subjectFont)
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .matchedGeometryEffect(id: "commit-\(commit.id)", in: animationNamespace)

            if isFutureCommit {
                Text("Future")
                    .font(WorkbenchTypography.captionStrong)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, WorkbenchMetrics.chipSpacing)
                    .padding(.vertical, WorkbenchMetrics.microSpacing)
                    .background(WorkbenchPalette.accentFill(contrast: colorSchemeContrast))
                    .clipShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.microCornerRadius, style: .continuous))
            }

            if isCurrentCommit {
                Text("Current")
                    .font(WorkbenchTypography.captionStrong)
                    .foregroundStyle(metadataStyle)
                    .padding(.horizontal, WorkbenchMetrics.chipSpacing)
                    .padding(.vertical, WorkbenchMetrics.microSpacing)
                    .background(WorkbenchPalette.hoverFill())
                    .clipShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.microCornerRadius, style: .continuous))
            }
        }
    }

    private var metadataLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: WorkbenchMetrics.chipSpacing) {
            Text(commit.shortHash)
                .font(WorkbenchTypography.caption.monospaced())
                .foregroundStyle(metadataStyle)

            Text(commit.authorName)
                .font(WorkbenchTypography.caption)
                .foregroundStyle(metadataStyle)
                .lineLimit(1)

            Text(relativeTimestamp)
                .font(WorkbenchTypography.caption)
                .foregroundStyle(metadataStyle)
                .lineLimit(1)
        }
        .fixedSize()
    }

    private var stateDot: some View {
        Circle()
            .fill(isSelected ? Color.accentColor : Color.clear)
            .overlay {
                Circle()
                    .strokeBorder(dotStrokeStyle)
            }
            .frame(
                width: commit.isMergeCommit ? WorkbenchMetrics.chipSpacing : WorkbenchMetrics.compactSpacing,
                height: commit.isMergeCommit ? WorkbenchMetrics.chipSpacing : WorkbenchMetrics.compactSpacing
            )
            .accessibilityHidden(true)
    }

    private var knownType: String? {
        guard let type = parsedSubject.type,
              !parsedSubject.subject.isEmpty,
              ConventionalCommitSubjectParser.isKnownType(type)
        else {
            return nil
        }

        return type
    }

    private var displaySubject: String {
        knownType == nil ? commit.subject : parsedSubject.subject
    }

    private var subjectFont: Font {
        commit.isMergeCommit ? WorkbenchTypography.detail : WorkbenchTypography.body
    }

    private var accessibilityLabel: String {
        var values = [commit.subject, commit.authorName, relativeTimestamp]
        if isCurrentCommit {
            values.append("current commit")
        }
        if commit.isMergeCommit {
            values.append("merge commit")
        }
        return values.joined(separator: ", ")
    }

    private var titleColor: Color {
        if commit.isMergeCommit {
            return .secondary
        }

        if isFutureCommit {
            return .accentColor
        }

        return .primary
    }

    private var metadataStyle: AnyShapeStyle {
        commit.isMergeCommit ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary)
    }

    private var backgroundColor: Color {
        if isSelected {
            return WorkbenchPalette.selectedFill()
        }

        return isHovered ? WorkbenchPalette.hoverFill() : .clear
    }

    private var dotStrokeStyle: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.accentColor)
        }

        return commit.isMergeCommit ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary)
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
        animationNamespace: Namespace().wrappedValue,
        onSelectRow: { _ in },
        onActivateCommit: { _ in },
        onRestoreCommit: { _ in },
        onEditCommitMessage: { _ in },
        onGenerateCommitMessage: { _ in }
    )
    .padding()
    .frame(width: WorkbenchMetrics.sidePanelWidth)
}
