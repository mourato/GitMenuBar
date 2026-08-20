@MainActor
extension MainMenuActionCoordinator {
    func executeAtomicCommits(
        groups: [AtomicCommitGroup],
        snapshot: AtomicCommitSnapshot? = nil,
        shouldPush: Bool
    ) async -> MainMenuCommitExecutionResult {
        publishOperationStatus(.committingGroup(current: 0, total: groups.count))
        let commitResult: Result<Void, Error> = if let snapshot {
            await gitManager.performHunkCommitsAsync(groups: groups, snapshot: snapshot) { current, total in
                self.publishOperationStatus(.committingGroup(current: current, total: total))
            }
        } else {
            await gitManager.performAtomicCommitsAsync(groups: groups) { current, total in
                self.publishOperationStatus(.committingGroup(current: current, total: total))
            }
        }
        guard case .success = commitResult else {
            if case let .failure(error) = commitResult {
                publishAlert(title: "Split Commits Failed", message: error.localizedDescription)
            }
            return .failed
        }

        commitWasCreated = true

        guard shouldPush else {
            await refreshRemoteStatus()
            publishSuccess(title: "Commit complete", message: "Your changes were committed locally.")
            return .committed
        }

        await refreshRemoteStatus()
        if gitManager.isRemoteAhead {
            showSyncOptions = true
            return .committedAndNeedsSyncOptions
        }

        publishOperationStatus(.pushingCommits(count: groups.count))
        let pushResult = await pushToRemote()
        guard case .success = pushResult else {
            if case let .failure(error) = pushResult {
                publishAlert(
                    title: "Push Failed",
                    message: "\(groups.count) commit\(groups.count == 1 ? " was" : "s were") created locally, "
                        + "but the push failed. \(error.localizedDescription) Try pushing again."
                )
            }
            return .failed
        }

        await refreshRepository()
        await refreshRemoteStatus()
        publishSuccess(
            title: "Split commits & push complete",
            message: "\(groups.count) commit\(groups.count == 1 ? " is" : "s are") now on the remote."
        )
        return .committed
    }
}
