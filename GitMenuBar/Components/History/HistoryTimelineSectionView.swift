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
    let isCommitInFuture: (Commit) -> Bool
    let onSelectCommit: (Commit) -> Void

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
            header

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
        VStack(spacing: 0) {
            ForEach(Array(commits.enumerated()), id: \.element.id) { index, commit in
                HistoryTimelineRowView(
                    commit: commit,
                    isCurrentCommit: commit.id == currentHash,
                    isFutureCommit: isCommitInFuture(commit),
                    showsTopConnector: index > 0,
                    showsBottomConnector: index < commits.count - 1,
                    onTap: {
                        onSelectCommit(commit)
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
    let isCurrentCommit: Bool
    let isFutureCommit: Bool
    let showsTopConnector: Bool
    let showsBottomConnector: Bool
    let onTap: () -> Void
    let onHoverChanged: (Bool) -> Void

    @State private var isHovered = false

    var body: some View {
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
                    }

                    HStack(spacing: 4) {
                        Text(commit.authorName)
                        Text("•")
                        Text(HistoryTimelineDateFormatter.rowTimestamp(for: commit.committedAt))
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
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: borderLineWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .focusable(false)
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

        if isHovered {
            return Color.primary.opacity(0.05)
        }

        return Color.clear
    }

    private var borderColor: Color {
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
            stats: CommitStats(filesChanged: 2, insertions: 8, deletions: 3)
        ),
        isCurrentCommit: false,
        isFutureCommit: true,
        showsTopConnector: true,
        showsBottomConnector: true,
        onTap: {},
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
                stats: CommitStats(filesChanged: 5, insertions: 114, deletions: 19)
            ),
            Commit(
                id: "abcdef1234567890",
                shortHash: "abcdef1",
                subject: "fix(history): highlight current commit",
                body: "",
                authorName: "Renato",
                authorEmail: "renato@example.com",
                committedAt: .now.addingTimeInterval(-86400),
                stats: CommitStats(filesChanged: 2, insertions: 8, deletions: 3)
            )
        ],
        currentHash: "abcdef1234567890",
        remoteUrl: "https://github.com/example/repo",
        isLoading: false,
        isCommitInFuture: { $0.id == "1234567890abcdef" },
        onSelectCommit: { _ in }
    )
    .padding()
    .frame(width: 380)
}
