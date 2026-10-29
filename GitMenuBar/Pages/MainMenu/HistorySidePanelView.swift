import SwiftUI

struct HistorySidePanelView: View {
    let projectName: String
    let selection: MainMenuSidePanelSelection?
    let history: SidePanelHistoryModel
    let onClose: () -> Void

    @Environment(GitManager.self) private var gitManager
    @Environment(MainMenuActionCoordinator.self) private var actionCoordinator
    @State private var pendingReset: Commit?

    var body: some View {
        Group {
            if case let .commit(hash) = selection {
                commitDetail(for: hash)
            } else {
                VStack(alignment: .leading, spacing: WorkbenchMetrics.groupSpacing) {
                    SidePanelHeaderView(
                        projectName: projectName,
                        title: selection?.title ?? "History",
                        onClose: onClose
                    )
                    ScrollView(.vertical) {
                        SidePanelHistoryBrowserView(history: history, pendingReset: $pendingReset)
                            .padding(.bottom, WorkbenchMetrics.compactSpacing)
                    }
                }
            }
        }
        .sidePanelResetAlert(commit: $pendingReset) { commit in
            Task {
                _ = await actionCoordinator.sidePanel.resetSidePanelCommit(hash: commit.id)
            }
        }
    }

    @ViewBuilder
    private func commitDetail(for hash: String) -> some View {
        let adapter = history.sections.flatMap(\.rows).map(\.row).first { $0.commit.id == hash }
        CommitDetailPageView(
            commit: adapter?.commit,
            currentHash: gitManager.currentHash,
            remoteUrl: gitManager.remoteUrl,
            isCommitInFuture: history.isCommitInFuture,
            onClose: onClose,
            onRestoreCommit: { commit in
                guard let adapter, adapter.actions.canRestore else { return }
                pendingReset = commit
            },
            onEditCommitMessage: history.onEditCommitMessage,
            onGenerateCommitMessage: history.onGenerateCommitMessage,
            onOpenLocalFile: history.onOpenLocalFile
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview("History List") {
    MainMenuPreviewHarness {
        HistorySidePanelView(
            projectName: "GitMenuBar",
            selection: .history,
            history: .preview(sections: SidePanelHistoryModel.sampleSections, canLoadMore: true),
            onClose: {}
        )
    }
    .frame(width: WorkbenchMetrics.sidePanelWidth, height: 480)
}

#Preview("Commit Detail") {
    MainMenuPreviewHarness {
        HistorySidePanelView(
            projectName: "GitMenuBar",
            selection: .commit(id: "abc123"),
            history: .preview(sections: SidePanelHistoryModel.sampleSections),
            onClose: {}
        )
    }
    .frame(width: WorkbenchMetrics.sidePanelWidth, height: 480)
}

#Preview("Empty History") {
    MainMenuPreviewHarness {
        HistorySidePanelView(
            projectName: "GitMenuBar",
            selection: .history,
            history: .preview(),
            onClose: {}
        )
    }
    .frame(width: WorkbenchMetrics.sidePanelWidth, height: 360)
}
