import SwiftUI

/// Shared history list: one `HistorySectionView` wiring, one collapse state,
/// one reset target. Used by both the history inspector and the commit
/// workspace so the two surfaces cannot drift apart.
struct InspectorHistoryBrowserView: View {
    let history: InspectorHistoryModel
    @Binding var pendingReset: Commit?

    @State private var isCollapsed = false

    var body: some View {
        HistorySectionView(
            sections: history.sections,
            selectedItemID: history.selectedItemID,
            isLoading: history.isLoading,
            canLoadMore: history.canLoadMore,
            animationNamespace: history.animationNamespace,
            onSelectRow: history.onSelectRow,
            onActivateCommit: { history.onOpenCommit($0.commit.id) },
            onRestoreCommit: { row in
                guard row.actions.canRestore else { return }
                pendingReset = row.commit
            },
            onEditCommitMessage: { history.onEditCommitMessage($0.commit) },
            onGenerateCommitMessage: { history.onGenerateCommitMessage($0.commit) },
            onLoadMore: history.onLoadMore,
            isCollapsed: $isCollapsed
        )
    }
}

extension View {
    /// Shared hard-reset confirmation used by every history surface.
    func inspectorResetAlert(
        commit: Binding<Commit?>,
        onConfirm: @escaping (Commit) -> Void
    ) -> some View {
        alert(
            "Reset to this commit?",
            isPresented: Binding(
                get: { commit.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented {
                        commit.wrappedValue = nil
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                commit.wrappedValue = nil
            }
            Button("Reset", role: .destructive) {
                guard let target = commit.wrappedValue else { return }
                commit.wrappedValue = nil
                onConfirm(target)
            }
        } message: {
            if let target = commit.wrappedValue {
                Text(
                    "This hard-resets the current branch to \(target.shortHash) (\(target.subject)). Uncommitted work may be lost."
                )
            }
        }
    }
}

#Preview("History Browser") {
    MainMenuPreviewHarness {
        InspectorHistoryBrowserPreviewHost()
    }
    .frame(width: WorkbenchMetrics.inspectorMinimumWidth, height: 420)
}

private struct InspectorHistoryBrowserPreviewHost: View {
    @State private var pendingReset: Commit?

    var body: some View {
        InspectorHistoryBrowserView(
            history: .preview(sections: InspectorHistoryModel.sampleSections, canLoadMore: true),
            pendingReset: $pendingReset
        )
        .padding()
    }
}
