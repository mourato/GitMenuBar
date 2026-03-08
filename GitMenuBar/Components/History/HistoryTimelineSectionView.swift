import AppKit
import SwiftUI

private enum HistoryTimelineMetrics {
    static let gutterWidth: CGFloat = 18
    static let circleSize: CGFloat = 8
    static let cardWidth: CGFloat = 308
    static let cardEstimatedHeight: CGFloat = 220
    static let cardTrailingInset: CGFloat = 6
}

private struct HistoryTimelineRowBoundsKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct HistoryTimelineSectionView: View {
    let commits: [Commit]
    let currentHash: String
    let remoteUrl: String
    let isLoading: Bool
    let showsHeader: Bool
    let isCommitInFuture: (Commit) -> Bool
    let onRestoreCommit: (Commit) -> Void

    @State private var expandedCommitIDs: Set<Commit.ID> = []
    @State private var hoveredCommitID: Commit.ID?
    @State private var activeCommitID: Commit.ID?
    @State private var isCardHovered = false
    @State private var showCardTask: Task<Void, Never>?
    @State private var closeCardTask: Task<Void, Never>?

    private var activeCommit: Commit? {
        guard let activeCommitID else {
            return nil
        }

        return commits.first(where: { $0.id == activeCommitID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsHeader {
                header
            }

            if commits.isEmpty {
                placeholderView
            } else {
                timelineList
            }
        }
        .onDisappear {
            showCardTask?.cancel()
            closeCardTask?.cancel()
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.blue)

            Text("History")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            Text("\(commits.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
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
        VStack(spacing: 6) {
            ForEach(Array(commits.enumerated()), id: \.element.id) { index, commit in
                HistoryTimelineRowView(
                    commit: commit,
                    commitURL: commitURL(for: commit),
                    isCurrentCommit: commit.id == currentHash,
                    isFutureCommit: isCommitInFuture(commit),
                    isExpanded: expandedCommitIDs.contains(commit.id),
                    showsTopConnector: index > 0,
                    showsBottomConnector: index < commits.count - 1,
                    onTap: {
                        toggleExpansion(for: commit.id)
                    },
                    onRestoreCommit: {
                        onRestoreCommit(commit)
                    },
                    onHoverChanged: { isHovered in
                        handleRowHover(commitID: commit.id, isHovered: isHovered)
                    }
                )
                .anchorPreference(key: HistoryTimelineRowBoundsKey.self, value: .bounds) {
                    [commit.id: $0]
                }
            }
        }
        .overlayPreferenceValue(HistoryTimelineRowBoundsKey.self) { preferences in
            GeometryReader { geometryProxy in
                if let activeCommit, let anchor = preferences[activeCommit.id] {
                    let rect = geometryProxy[anchor]

                    CommitHoverCardView(
                        commit: activeCommit,
                        remoteUrl: remoteUrl
                    )
                    .frame(width: HistoryTimelineMetrics.cardWidth)
                    .position(
                        x: cardCenterX(in: geometryProxy.size.width),
                        y: cardCenterY(for: rect, containerHeight: geometryProxy.size.height)
                    )
                    .zIndex(1)
                    .shadow(color: Color.black.opacity(0.22), radius: 16, x: 0, y: 10)
                    .onHover { isHovered in
                        isCardHovered = isHovered

                        if isHovered {
                            closeCardTask?.cancel()
                        } else if hoveredCommitID == nil {
                            scheduleCloseCard()
                        }
                    }
                    .allowsHitTesting(true)
                }
            }
        }
    }

    private func toggleExpansion(for commitID: Commit.ID) {
        if expandedCommitIDs.contains(commitID) {
            expandedCommitIDs.remove(commitID)
        } else {
            expandedCommitIDs.insert(commitID)
        }
    }

    private func commitURL(for commit: Commit) -> URL? {
        guard let reference = GitHubRemoteURLParser.parse(remoteUrl) else {
            return nil
        }

        return URL(string: "https://github.com/\(reference.owner)/\(reference.repository)/commit/\(commit.id)")
    }

    private func handleRowHover(commitID: Commit.ID, isHovered: Bool) {
        if isHovered {
            hoveredCommitID = commitID
            closeCardTask?.cancel()
            scheduleShowCard(for: commitID)
            return
        }

        if hoveredCommitID == commitID {
            hoveredCommitID = nil
        }

        if activeCommitID != commitID {
            showCardTask?.cancel()
        }

        if hoveredCommitID == nil, !isCardHovered {
            scheduleCloseCard()
        }
    }

    private func scheduleShowCard(for commitID: Commit.ID) {
        showCardTask?.cancel()
        showCardTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard hoveredCommitID == commitID else {
                    return
                }

                activeCommitID = commitID
            }
        }
    }

    private func scheduleCloseCard() {
        closeCardTask?.cancel()
        closeCardTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard hoveredCommitID == nil, !isCardHovered else {
                    return
                }

                activeCommitID = nil
            }
        }
    }

    private func cardCenterX(in containerWidth: CGFloat) -> CGFloat {
        max(
            HistoryTimelineMetrics.cardWidth / 2,
            containerWidth - (HistoryTimelineMetrics.cardWidth / 2) - HistoryTimelineMetrics.cardTrailingInset
        )
    }

    private func cardCenterY(for rect: CGRect, containerHeight: CGFloat) -> CGFloat {
        let minY = HistoryTimelineMetrics.cardEstimatedHeight / 2
        let maxY = max(minY, containerHeight - (HistoryTimelineMetrics.cardEstimatedHeight / 2))
        return min(max(rect.midY, minY), maxY)
    }
}

private struct HistoryTimelineRowView: View {
    let commit: Commit
    let commitURL: URL?
    let isCurrentCommit: Bool
    let isFutureCommit: Bool
    let isExpanded: Bool
    let showsTopConnector: Bool
    let showsBottomConnector: Bool
    let onTap: () -> Void
    let onRestoreCommit: () -> Void
    let onHoverChanged: (Bool) -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onTap) {
                HStack(alignment: .center, spacing: 10) {
                    timelineGutter

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(commit.subject)
                                .font(.system(size: 12, weight: .medium))
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

                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 4) {
                            Text(commit.authorName)
                            Text("•")
                            Text(HistoryTimelineDateFormatter.rowTimestamp(for: commit.committedAt))
                            Text("•")
                            Text("\(commit.stats.filesChanged) file\(commit.stats.filesChanged == 1 ? "" : "s")")
                        }
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .focusable(false)

            if isExpanded {
                Divider()
                    .padding(.leading, HistoryTimelineMetrics.gutterWidth + 18)

                expandedFilesView
            }
        }
        .background(backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: borderLineWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
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

            Button("Reset to Here") {
                onRestoreCommit()
            }
            .disabled(isCurrentCommit)
        }
        .onHover { isHovered in
            self.isHovered = isHovered
            onHoverChanged(isHovered)

            if isHovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private var expandedFilesView: some View {
        HStack(alignment: .top, spacing: 10) {
            Spacer()
                .frame(width: HistoryTimelineMetrics.gutterWidth)

            VStack(alignment: .leading, spacing: 8) {
                if commit.changedFiles.isEmpty {
                    Text("No file list available for this commit.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(commit.changedFiles) { file in
                        CommitChangedFileRowView(file: file)
                    }
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 10)
            .padding(.trailing, 8)
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
        if isCurrentCommit {
            return Color.accentColor.opacity(0.08)
        }

        if isExpanded {
            return Color.primary.opacity(0.04)
        }

        if isHovered {
            return Color.primary.opacity(0.05)
        }

        return Color.clear
    }

    private var borderColor: Color {
        if isCurrentCommit {
            return Color.accentColor.opacity(0.35)
        }

        if isExpanded {
            return Color.primary.opacity(0.12)
        }

        if isHovered {
            return Color.primary.opacity(0.08)
        }

        return .clear
    }

    private var borderLineWidth: CGFloat {
        if isCurrentCommit || isHovered || isExpanded {
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

private struct CommitChangedFileRowView: View {
    let file: CommitFileChange

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 14, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if !file.directoryPath.isEmpty {
                    Text(file.directoryPath)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                if file.lineDiff.added > 0 {
                    Text("+\(file.lineDiff.added)")
                        .foregroundColor(.green)
                }

                if file.lineDiff.removed > 0 {
                    Text("-\(file.lineDiff.removed)")
                        .foregroundColor(.red)
                }
            }
            .font(.system(size: 10, weight: .medium))
        }
    }
}

#Preview("History Timeline Row") {
    HistoryTimelineRowView(
        commit: Commit(
            id: "1234567890abcdef",
            shortHash: "1234567",
            subject: "fix(history): highlight current commit and preserve hover card",
            body: "",
            authorName: "Renato",
            authorEmail: "renato@example.com",
            committedAt: .now.addingTimeInterval(-5400),
            stats: CommitStats(filesChanged: 2, insertions: 8, deletions: 3),
            changedFiles: [
                CommitFileChange(path: "GitMenuBar/Components/History/HistoryTimelineSectionView.swift", lineDiff: LineDiffStats(added: 7, removed: 2)),
                CommitFileChange(path: "GitMenuBar/Pages/History/HistoryPage.swift", lineDiff: LineDiffStats(added: 1, removed: 1))
            ]
        ),
        commitURL: URL(string: "https://github.com/example/repo/commit/1234567890abcdef"),
        isCurrentCommit: false,
        isFutureCommit: true,
        isExpanded: true,
        showsTopConnector: true,
        showsBottomConnector: true,
        onTap: {},
        onRestoreCommit: {},
        onHoverChanged: { _ in }
    )
    .padding()
    .frame(width: 380)
}

#Preview("History Timeline Section") {
    HistoryTimelineSectionView(
        commits: [
            Commit(
                id: "1234567890abcdef",
                shortHash: "1234567",
                subject: "feat(git): improve status bar and menu item logic",
                body: """
                - Introduce StatusBarContextMenuActionState for context menu actions.
                - Refactor StatusBarController to use the new state struct.
                """,
                authorName: "Renato",
                authorEmail: "renato@example.com",
                committedAt: .now.addingTimeInterval(-3600),
                stats: CommitStats(filesChanged: 5, insertions: 114, deletions: 19),
                changedFiles: [
                    CommitFileChange(path: "GitMenuBar/App/StatusBarController.swift", lineDiff: LineDiffStats(added: 72, removed: 12)),
                    CommitFileChange(path: "GitMenuBar/Services/Git/GitManager.swift", lineDiff: LineDiffStats(added: 24, removed: 4))
                ]
            ),
            Commit(
                id: "abcdef1234567890",
                shortHash: "abcdef1",
                subject: "fix(history): highlight current commit",
                body: "",
                authorName: "Renato",
                authorEmail: "renato@example.com",
                committedAt: .now.addingTimeInterval(-86400),
                stats: CommitStats(filesChanged: 2, insertions: 8, deletions: 3),
                changedFiles: [
                    CommitFileChange(path: "GitMenuBar/Components/History/HistoryTimelineSectionView.swift", lineDiff: LineDiffStats(added: 6, removed: 2))
                ]
            )
        ],
        currentHash: "abcdef1234567890",
        remoteUrl: "https://github.com/example/repo",
        isLoading: false,
        showsHeader: true,
        isCommitInFuture: { $0.id == "1234567890abcdef" },
        onRestoreCommit: { _ in }
    )
    .padding()
    .frame(width: 380)
}
