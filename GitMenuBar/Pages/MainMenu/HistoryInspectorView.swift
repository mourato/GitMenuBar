import SwiftUI

struct HistoryInspectorView: View {
    let projectName: String
    let selection: MainMenuInspectorSelection?
    let history: InspectorHistoryModel

    @EnvironmentObject private var gitManager: GitManager
    @EnvironmentObject private var actionCoordinator: MainMenuActionCoordinator
    @State private var pendingReset: Commit?

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.groupSpacing) {
            InspectorHeaderView(projectName: projectName, title: selection?.title ?? "History")
            NavigationStack {
                ScrollView(.vertical) {
                    InspectorHistoryBrowserView(history: history, pendingReset: $pendingReset)
                        .padding(.bottom, WorkbenchMetrics.compactSpacing)
                }
                .navigationDestination(item: commitHashBinding) { hash in
                    commitDetail(for: hash)
                        .toolbar {
                            ToolbarItem(placement: .navigation) {
                                Button("Back to History") {
                                    history.onBackToHistory()
                                }
                                .accessibilityLabel("Back to History")
                            }
                        }
                }
            }
        }
        .inspectorResetAlert(commit: $pendingReset) { commit in
            Task {
                _ = await actionCoordinator.resetInspectorCommit(hash: commit.id)
            }
        }
    }

    /// The pushed commit derives from the workbench selection, so swipe-back
    /// dismissal and programmatic navigation can never diverge.
    private var commitHashBinding: Binding<String?> {
        Binding(
            get: {
                if case let .commit(id) = selection {
                    id
                } else {
                    nil
                }
            },
            set: { newValue in
                if newValue == nil {
                    history.onBackToHistory()
                }
            }
        )
    }

    @ViewBuilder
    private func commitDetail(for hash: String) -> some View {
        let adapter = history.sections.flatMap(\.rows).map(\.row).first { $0.commit.id == hash }
        CommitDetailPageView(
            commit: adapter?.commit,
            currentHash: gitManager.currentHash,
            remoteUrl: gitManager.remoteUrl,
            isCommitInFuture: history.isCommitInFuture,
            animationNamespace: history.animationNamespace,
            onBack: {
                history.onBackToHistory()
            },
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
        HistoryInspectorView(
            projectName: "GitMenuBar",
            selection: .history,
            history: .preview(sections: InspectorHistoryModel.sampleSections, canLoadMore: true)
        )
    }
    .frame(width: WorkbenchMetrics.inspectorMinimumWidth, height: 480)
}

#Preview("Commit Detail") {
    MainMenuPreviewHarness {
        HistoryInspectorView(
            projectName: "GitMenuBar",
            selection: .commit(id: "abc123"),
            history: .preview(sections: InspectorHistoryModel.sampleSections)
        )
    }
    .frame(width: WorkbenchMetrics.inspectorMinimumWidth, height: 480)
}

#Preview("Empty History") {
    MainMenuPreviewHarness {
        HistoryInspectorView(
            projectName: "GitMenuBar",
            selection: .history,
            history: .preview()
        )
    }
    .frame(width: WorkbenchMetrics.inspectorMinimumWidth, height: 360)
}
