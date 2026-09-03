import SwiftUI

enum HistoryInspectorDestination: Hashable, Identifiable {
    case commit(hash: String)

    var id: String {
        switch self {
        case let .commit(hash):
            "commit:\(hash)"
        }
    }

    var hash: String {
        switch self {
        case let .commit(hash):
            hash
        }
    }
}

enum HistoryInspectorNavigation {
    static func destination(for selection: MainMenuInspectorSelection?) -> HistoryInspectorDestination? {
        switch selection {
        case let .commit(id):
            .commit(hash: id)
        case .history, .none:
            nil
        default:
            nil
        }
    }

    static func canConfirmReset(
        commitID: String,
        currentHash: String,
        repositoryPath: String,
        capturedRepositoryPath: String
    ) -> Bool {
        guard !commitID.isEmpty,
              commitID != currentHash,
              !capturedRepositoryPath.isEmpty
        else {
            return false
        }
        return GitRepositoryContext.normalizedPath(repositoryPath)
            == GitRepositoryContext.normalizedPath(capturedRepositoryPath)
    }
}

struct HistoryInspectorView: View {
    let selection: MainMenuInspectorSelection
    let sections: [HistoryTimelineSectionModel]
    let selectedItemID: MainMenuSelectableItem?
    let isLoading: Bool
    let canLoadMore: Bool
    let animationNamespace: Namespace.ID
    let currentHash: String
    let remoteUrl: String
    let repositoryPath: String
    let isCommitInFuture: (Commit) -> Bool
    let onSelectRow: (HistoryRowAdapter) -> Void
    let onOpenCommit: (String) -> Void
    let onBackToHistory: () -> Void
    let onEditCommitMessage: (Commit) -> Void
    let onGenerateCommitMessage: (Commit) -> Void
    let onLoadMore: () -> Void
    let onOpenLocalFile: (String) -> Void

    @EnvironmentObject private var actionCoordinator: MainMenuActionCoordinator
    @State private var destination: HistoryInspectorDestination?
    @State private var pendingReset: Commit?
    @State private var isCollapsed = false

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                HistorySectionView(
                    sections: sections,
                    selectedItemID: selectedItemID,
                    isLoading: isLoading,
                    canLoadMore: canLoadMore,
                    animationNamespace: animationNamespace,
                    onSelectRow: onSelectRow,
                    onActivateCommit: { row in
                        onOpenCommit(row.commit.id)
                        destination = .commit(hash: row.commit.id)
                    },
                    onRestoreCommit: { row in
                        guard row.actions.canRestore else { return }
                        pendingReset = row.commit
                    },
                    onEditCommitMessage: { row in
                        onEditCommitMessage(row.commit)
                    },
                    onGenerateCommitMessage: { row in
                        onGenerateCommitMessage(row.commit)
                    },
                    onLoadMore: onLoadMore,
                    isCollapsed: $isCollapsed
                )
                .padding(.bottom, WorkbenchMetrics.compactSpacing)
            }
            .navigationDestination(item: $destination) { destination in
                commitDetail(for: destination.hash)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Back to History") {
                                self.destination = nil
                                onBackToHistory()
                            }
                            .accessibilityLabel("Back to History")
                        }
                    }
            }
        }
        .onAppear {
            syncDestinationFromSelection()
        }
        .onChange(of: selection) { _ in
            syncDestinationFromSelection()
        }
        .alert(
            "Reset to this commit?",
            isPresented: Binding(
                get: { pendingReset != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingReset = nil
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                pendingReset = nil
            }
            Button("Reset", role: .destructive) {
                guard let pendingReset else { return }
                let commit = pendingReset
                self.pendingReset = nil
                Task {
                    _ = await actionCoordinator.resetInspectorCommit(hash: commit.id)
                }
            }
        } message: {
            if let pendingReset {
                Text(
                    "This hard-resets the current branch to \(pendingReset.shortHash) (\(pendingReset.subject)). Uncommitted work may be lost."
                )
            }
        }
    }

    @ViewBuilder
    private func commitDetail(for hash: String) -> some View {
        let commit = sections.flatMap(\.rows).map(\.row.commit).first { $0.id == hash }
        CommitDetailPageView(
            commit: commit,
            currentHash: currentHash,
            remoteUrl: remoteUrl,
            isCommitInFuture: isCommitInFuture,
            animationNamespace: animationNamespace,
            onBack: {
                destination = nil
                onBackToHistory()
            },
            onRestoreCommit: { commit in
                guard HistoryInspectorNavigation.canConfirmReset(
                    commitID: commit.id,
                    currentHash: currentHash,
                    repositoryPath: repositoryPath,
                    capturedRepositoryPath: repositoryPath
                ) else {
                    return
                }
                pendingReset = commit
            },
            onEditCommitMessage: onEditCommitMessage,
            onGenerateCommitMessage: onGenerateCommitMessage,
            onOpenLocalFile: onOpenLocalFile
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func syncDestinationFromSelection() {
        destination = HistoryInspectorNavigation.destination(for: selection)
    }
}

#Preview("History List") {
    MainMenuPreviewHarness {
        HistoryInspectorPreviewHost(selection: .history)
    }
    .frame(width: WorkbenchMetrics.inspectorMinimumWidth, height: 480)
}

#Preview("Commit Detail") {
    MainMenuPreviewHarness {
        HistoryInspectorPreviewHost(selection: .commit(id: "abc123"))
    }
    .frame(width: WorkbenchMetrics.inspectorMinimumWidth, height: 480)
}

#Preview("Empty History") {
    MainMenuPreviewHarness {
        HistoryInspectorPreviewHost(selection: .history, sections: [])
    }
    .frame(width: WorkbenchMetrics.inspectorMinimumWidth, height: 360)
}

private struct HistoryInspectorPreviewHost: View {
    let selection: MainMenuInspectorSelection
    var sections: [HistoryTimelineSectionModel]?
    @Namespace private var animationNamespace

    var body: some View {
        HistoryInspectorView(
            selection: selection,
            sections: sections ?? Self.sampleSections,
            selectedItemID: nil,
            isLoading: false,
            canLoadMore: false,
            animationNamespace: animationNamespace,
            currentHash: "abc123",
            remoteUrl: "https://github.com/example/repo.git",
            repositoryPath: "/tmp/preview-repo",
            isCommitInFuture: { _ in false },
            onSelectRow: { _ in },
            onOpenCommit: { _ in },
            onBackToHistory: {},
            onEditCommitMessage: { _ in },
            onGenerateCommitMessage: { _ in },
            onLoadMore: {},
            onOpenLocalFile: { _ in }
        )
    }

    private static var sampleSections: [HistoryTimelineSectionModel] {
        let commits = [
            Commit(
                id: "abc123",
                shortHash: "abc123",
                subject: "Fix critical bug in payment processing",
                body: "",
                authorName: "Alice",
                authorEmail: "alice@example.com",
                committedAt: Date(),
                stats: CommitStats(filesChanged: 3, insertions: 45, deletions: 12),
                changedFiles: []
            ),
            Commit(
                id: "def456",
                shortHash: "def456",
                subject: "Add unit tests for the new feature",
                body: "",
                authorName: "Bob",
                authorEmail: "bob@example.com",
                committedAt: Date().addingTimeInterval(-3600),
                stats: CommitStats(filesChanged: 1, insertions: 10, deletions: 0),
                changedFiles: []
            )
        ]
        let rows = commits.enumerated().map { index, commit in
            HistoryRowAdapter(
                commit: commit,
                currentHash: "abc123",
                remoteUrl: "https://github.com/example/repo.git",
                isCommitInFuture: index > 0
            )
        }
        return HistoryTimelineSectionModel.build(from: rows)
    }
}
