import SwiftUI

private struct RepositoryOverviewPreviewMatrix: View {
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.groupSpacing) {
            ForEach(RepositoryOverviewPreviewState.allCases) { state in
                VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                    Text(state.title)
                        .font(WorkbenchTypography.captionStrong)
                        .foregroundStyle(.secondary)

                    RepositoryOverviewView(
                        overview: state.overview,
                        onSelectSection: { _ in },
                        onOpenGitHubPage: { _ in },
                        canOpenGitHubPage: true
                    )
                    .frame(width: width)
                }
            }
        }
        .padding()
        .frame(width: width + WorkbenchMetrics.panelPadding * 2)
    }
}

private enum RepositoryOverviewPreviewState: String, CaseIterable, Identifiable {
    case knownCounts
    case zero
    case loading
    case gitHubCLIMissing
    case notGitHubRemote
    case commandFailed
    case noReason

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .knownCounts:
            "Known counts"
        case .zero:
            "Known zero"
        case .loading:
            "Loading"
        case .gitHubCLIMissing:
            "GitHub CLI missing"
        case .notGitHubRemote:
            "Not on GitHub"
        case .commandFailed:
            "GitHub command failed"
        case .noReason:
            "Unavailable without reason"
        }
    }

    var overview: RepositoryOverviewSnapshot {
        let lastCheckedAt = Date(timeIntervalSince1970: 1_735_689_600)
        let common = RepositoryOverviewSnapshot(
            stagedCount: 3,
            unstagedCount: 5,
            untrackedCount: 1,
            addedLineCount: 40,
            removedLineCount: 12,
            aheadCount: .known(1),
            behindCount: .known(0),
            branchesWithoutUpstream: .known(0),
            unpushedBranches: .known(2),
            unmergedBranches: .known(1),
            stashCount: .known(3),
            historyCount: 24,
            currentBranch: "feat/status-strip",
            isDetachedHead: false,
            isLoading: false,
            lastCheckedAt: lastCheckedAt
        )

        switch self {
        case .knownCounts:
            return RepositoryOverviewSnapshot(
                stagedCount: common.stagedCount,
                unstagedCount: common.unstagedCount,
                untrackedCount: common.untrackedCount,
                addedLineCount: common.addedLineCount,
                removedLineCount: common.removedLineCount,
                aheadCount: common.aheadCount,
                behindCount: common.behindCount,
                branchesWithoutUpstream: common.branchesWithoutUpstream,
                unpushedBranches: common.unpushedBranches,
                unmergedBranches: common.unmergedBranches,
                stashCount: common.stashCount,
                openPullRequests: .known(123),
                openIssues: .known(7),
                gitHubUnavailableReason: nil,
                historyCount: common.historyCount,
                currentBranch: common.currentBranch,
                isDetachedHead: common.isDetachedHead,
                isLoading: common.isLoading,
                lastCheckedAt: common.lastCheckedAt
            )
        case .zero:
            return RepositoryOverviewSnapshot(
                stagedCount: 0,
                unstagedCount: 0,
                untrackedCount: 0,
                addedLineCount: 0,
                removedLineCount: 0,
                aheadCount: .known(0),
                behindCount: .known(0),
                branchesWithoutUpstream: .known(0),
                unpushedBranches: .known(0),
                unmergedBranches: .known(0),
                stashCount: .known(0),
                openPullRequests: .known(0),
                openIssues: .known(0),
                gitHubUnavailableReason: nil,
                historyCount: 12,
                currentBranch: "main",
                isDetachedHead: false,
                isLoading: false,
                lastCheckedAt: lastCheckedAt
            )
        case .loading:
            return RepositoryOverviewSnapshot(
                stagedCount: 0,
                unstagedCount: 0,
                untrackedCount: 0,
                addedLineCount: 0,
                removedLineCount: 0,
                aheadCount: .loading,
                behindCount: .loading,
                branchesWithoutUpstream: .loading,
                unpushedBranches: .loading,
                unmergedBranches: .loading,
                stashCount: .loading,
                openPullRequests: .loading,
                openIssues: .loading,
                gitHubUnavailableReason: nil,
                historyCount: 0,
                currentBranch: "main",
                isDetachedHead: false,
                isLoading: true,
                lastCheckedAt: nil
            )
        case .gitHubCLIMissing:
            return unavailableOverview(reason: .gitHubCLIMissing, lastCheckedAt: lastCheckedAt)
        case .notGitHubRemote:
            return unavailableOverview(reason: .notGitHubRemote, lastCheckedAt: lastCheckedAt)
        case .commandFailed:
            return unavailableOverview(reason: .commandFailed, lastCheckedAt: lastCheckedAt)
        case .noReason:
            return unavailableOverview(reason: nil, lastCheckedAt: lastCheckedAt)
        }
    }

    private func unavailableOverview(
        reason: GitHubStatusUnavailableReason?,
        lastCheckedAt: Date
    ) -> RepositoryOverviewSnapshot {
        RepositoryOverviewSnapshot(
            stagedCount: 3,
            unstagedCount: 5,
            untrackedCount: 1,
            addedLineCount: 40,
            removedLineCount: 12,
            aheadCount: .known(1),
            behindCount: .known(0),
            branchesWithoutUpstream: .known(0),
            unpushedBranches: .known(2),
            unmergedBranches: .known(1),
            stashCount: .known(3),
            openPullRequests: .unavailable,
            openIssues: .unavailable,
            gitHubUnavailableReason: reason,
            historyCount: 24,
            currentBranch: "feat/status-strip",
            isDetachedHead: false,
            isLoading: false,
            lastCheckedAt: lastCheckedAt
        )
    }
}

#Preview("Tier A · State matrix") {
    RepositoryOverviewPreviewMatrix(width: 1040)
}

#Preview("Tier B · State matrix") {
    RepositoryOverviewPreviewMatrix(width: 520)
}

#Preview("Tier C · State matrix") {
    RepositoryOverviewPreviewMatrix(width: 280)
}
