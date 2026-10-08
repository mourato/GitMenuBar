import Observation

@MainActor
@Observable
final class MainMenuSnapshotModel {
    private(set) var recentProjectReferences: [ProjectReference]
    private(set) var renderSnapshot = MainMenuRenderSnapshot.empty
    @ObservationIgnored let recentProjectsStore: RecentProjectsStore

    init(recentProjectsStore: RecentProjectsStore = RecentProjectsStore()) {
        self.recentProjectsStore = recentProjectsStore
        recentProjectReferences = recentProjectsStore.recentProjects()
    }

    func reloadRecentProjects() {
        recentProjectReferences = recentProjectsStore.recentProjects()
    }

    func rebuild(
        gitManager: GitManager,
        projectMonitor: ProjectMonitorStore,
        currentRepositoryPath: String,
        isStagedSectionCollapsed: Bool,
        isUnstagedSectionCollapsed: Bool,
        isLoading: Bool
    ) {
        let normalizedPath = currentRepositoryPath.isEmpty
            ? ""
            : RecentProjectsStore.normalize(currentRepositoryPath)
        let monitorSnapshot = normalizedPath.isEmpty
            ? nil
            : projectMonitor.snapshots[normalizedPath]
        let overview = currentRepositoryPath.isEmpty
            ? RepositoryOverviewSnapshot.empty
            : RepositoryOverviewSnapshot.build(
                stagedFiles: gitManager.stagedFiles,
                changedFiles: gitManager.changedFiles,
                commitCount: gitManager.commitCount,
                aheadOfRemote: gitManager.isAheadOfRemote,
                behindRemote: gitManager.isRemoteAhead,
                gitBehindCount: gitManager.behindCount,
                commitHistory: gitManager.commitHistory,
                currentBranch: gitManager.currentBranch,
                isDetachedHead: gitManager.isDetachedHead,
                monitorSnapshot: monitorSnapshot,
                isLoading: isLoading
            )

        renderSnapshot = MainMenuRenderSnapshot.build(
            stagedFiles: gitManager.stagedFiles,
            changedFiles: gitManager.changedFiles,
            commitHistory: gitManager.commitHistory,
            currentHash: gitManager.currentHash,
            remoteUrl: gitManager.remoteUrl,
            availableBranches: gitManager.availableBranches,
            currentBranch: gitManager.currentBranch,
            isStagedSectionCollapsed: isStagedSectionCollapsed,
            isUnstagedSectionCollapsed: isUnstagedSectionCollapsed,
            recentProjects: recentProjectReferences,
            currentRepoPath: currentRepositoryPath,
            isCommitInFuture: { commit in
                guard let currentIndex = gitManager.commitHistory.firstIndex(where: { $0.id == gitManager.currentHash }),
                      let commitIndex = gitManager.commitHistory.firstIndex(where: { $0.id == commit.id })
                else { return false }
                return commitIndex < currentIndex
            },
            overview: overview
        )
    }
}
