import Foundation

@MainActor
final class SidePanelActionCoordinator {
    private weak var host: MainMenuActionCoordinator?
    private let gitManager: GitManager

    init(host: MainMenuActionCoordinator) {
        self.host = host
        gitManager = host.gitManager
    }

    func prepareSidePanelSelection(_ selection: MainMenuSidePanelSelection?) async {
        switch selection {
        case .stashes, .stash:
            await gitManager.loadSelectedStashesAsync()
        case .branches, .branch:
            await gitManager.loadSelectedUnmergedLocalBranchesAsync()
            await reloadSidePanelBranchData()
        case .unpushedCommits:
            await gitManager.fetchSelectedBranchesAsync()
        default:
            break
        }
    }

    /// Refreshes the branch list and worktree snapshot backing the inspector's
    /// Branch Health section. Runs sessionless so it always publishes.
    func reloadSidePanelBranchData() async {
        _ = await gitManager.branchService.resolveBranchInfoAsync()
        _ = await gitManager.branchService.resolveWorktreeSnapshotAsync()
    }

    func pushSidePanelBranch(_ branchName: String) async -> MainMenuSidePanelActionResult {
        guard let host else { return .skipped }
        return await host.executeContextualMutation(allowsRepositorySwitch: true) { context in
            let result = await gitManager.pushNamedLocalBranchAsync(branchName: branchName, context: context)
            await finishSidePanelMutation(result, context: context, failureTitle: "Push Failed")
            if gitManager.isCurrent(context) {
                await reloadSidePanelBranchData()
            }
            return result.inspectorActionResult
        }
    }

    func publishSidePanelBranch(_ branchName: String) async -> MainMenuSidePanelActionResult {
        guard let host else { return .skipped }
        return await host.executeContextualMutation(allowsRepositorySwitch: true) { context in
            let result = await gitManager.publishBranchAsync(branchName: branchName, context: context)
            await finishSidePanelMutation(result, context: context, failureTitle: "Publish Failed")
            if gitManager.isCurrent(context) {
                await reloadSidePanelBranchData()
            }
            return result.inspectorActionResult
        }
    }

    func pullSidePanelBranch(rebase: Bool) async -> MainMenuSidePanelActionResult {
        guard let host else { return .skipped }
        return await host.executeContextualMutation(allowsRepositorySwitch: true) { context in
            let result = await gitManager.pullFromRemoteAsync(rebase: rebase, context: context)
            await finishSidePanelMutation(result, context: context, failureTitle: "Pull Failed")
            return result.inspectorActionResult
        }
    }

    func applySidePanelStash(hash: String) async -> MainMenuSidePanelActionResult {
        guard let host else { return .skipped }
        return await host.executeContextualMutation(allowsRepositorySwitch: true) { context in
            let result = await gitManager.applyStashAsync(hash: hash, context: context)
            await finishSidePanelMutation(result, context: context, failureTitle: "Apply Stash Failed")
            if gitManager.isCurrent(context) {
                await gitManager.loadSelectedStashesAsync()
            }
            if case .success = result {
                host.publishSuccess(title: "Stash applied", message: "Review the working tree to commit the restored changes.")
            }
            return result.inspectorActionResult
        }
    }

    func dropSidePanelStash(hash: String) async -> MainMenuSidePanelActionResult {
        guard let host else { return .skipped }
        return await host.executeContextualMutation(allowsRepositorySwitch: true) { context in
            let result = await gitManager.dropStashAsync(hash: hash, context: context)
            await finishSidePanelMutation(result, context: context, failureTitle: "Drop Stash Failed")
            if gitManager.isCurrent(context) {
                await gitManager.loadSelectedStashesAsync()
            }
            return result.inspectorActionResult
        }
    }

    func saveSidePanelStash(message: String = "GitMenuBar stash") async -> MainMenuSidePanelActionResult {
        guard let host else { return .skipped }
        return await host.executeContextualMutation(allowsRepositorySwitch: true) { context in
            let result = await gitManager.saveStashAsync(message: message, context: context)
            await finishSidePanelMutation(result, context: context, failureTitle: "Stash Failed")
            if gitManager.isCurrent(context) {
                await gitManager.loadSelectedStashesAsync()
            }
            return result.inspectorActionResult
        }
    }

    func popSidePanelStash(hash: String) async -> MainMenuSidePanelActionResult {
        guard let host else { return .skipped }
        return await host.executeContextualMutation(allowsRepositorySwitch: true) { context in
            let applied = await gitManager.applyStashAsync(hash: hash, context: context)
            switch applied {
            case .success:
                break
            case let .failure(error):
                await finishSidePanelMutation(.failure(error), context: context, failureTitle: "Apply Stash Failed")
                if gitManager.isCurrent(context) {
                    await gitManager.loadSelectedStashesAsync()
                }
                return .failed
            }
            let dropped = await gitManager.dropStashAsync(hash: hash, context: context)
            await finishSidePanelMutation(dropped, context: context, failureTitle: "Drop Stash Failed")
            if gitManager.isCurrent(context) {
                await gitManager.loadSelectedStashesAsync()
            }
            if case .success = dropped {
                host.publishSuccess(title: "Stash popped", message: "Applied and dropped. Review the working tree to commit.")
            }
            return dropped.inspectorActionResult
        }
    }

    func switchSidePanelBranch(_ branchName: String) async -> MainMenuSidePanelActionResult {
        let result = await executeSidePanelMutation(failureTitle: "Branch Switch Failed") { context in
            await gitManager.branchService.switchBranchAsync(branchName: branchName, repositoryPath: context.repositoryPath)
        }
        await reloadSidePanelBranchData()
        return result
    }

    func checkoutRemoteSidePanelBranch(_ branchName: String, remoteName: String = "origin") async -> MainMenuSidePanelActionResult {
        let result = await executeSidePanelMutation(failureTitle: "Checkout Failed") { context in
            await gitManager.branchService.switchBranchAsync(branchName: "\(remoteName)/\(branchName)", repositoryPath: context.repositoryPath)
        }
        await reloadSidePanelBranchData()
        return result
    }

    func mergeSidePanelBranch(_ branchName: String) async -> MainMenuSidePanelActionResult {
        let result = await executeSidePanelMutation(failureTitle: "Merge Failed") { context in
            await gitManager.branchService.mergeBranchAsync(fromBranch: branchName, repositoryPath: context.repositoryPath)
        }
        await reloadSidePanelBranchData()
        return result
    }

    func deleteSidePanelBranch(_ branchName: String, force: Bool = false) async -> MainMenuSidePanelActionResult {
        let trimmed = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .skipped
        }
        let result = await executeSidePanelMutation(failureTitle: "Delete Failed") { context in
            await gitManager.branchService.deleteBranchAsync(branchName: trimmed, force: force, repositoryPath: context.repositoryPath)
        }
        await reloadSidePanelBranchData()
        return result
    }

    func deleteRemoteSidePanelBranch(_ branchName: String, remoteName: String = "origin") async -> MainMenuSidePanelActionResult {
        guard let host else { return .skipped }
        let trimmed = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .skipped
        }
        return await host.executeContextualMutation(allowsRepositorySwitch: false) { context in
            let result = await gitManager.deleteRemoteBranchAsync(branchName: trimmed, remoteName: remoteName)
            await finishSidePanelMutation(result, context: context, failureTitle: "Delete Remote Failed")
            if gitManager.isCurrent(context) {
                await reloadSidePanelBranchData()
            }
            return result.inspectorActionResult
        }
    }

    func performSidePanelCleanup(units: [GitCleanupUnit], snapshot: GitWorktreeSnapshot) async -> MainMenuSidePanelActionResult {
        guard let host else { return .skipped }
        guard !units.isEmpty else {
            return .skipped
        }
        return await host.executeContextualMutation(allowsRepositorySwitch: false) { context in
            let result = await gitManager.branchService.performCleanupAsync(
                units: units,
                snapshot: snapshot,
                repositoryPath: context.repositoryPath
            )
            switch result {
            case let .success(batch):
                await finishSidePanelMutation(.success(()), context: context, failureTitle: "Cleanup Failed")
                host.publishSuccess(title: "Cleanup complete", message: batchSummary(batch))
            case let .failure(error):
                await finishSidePanelMutation(.failure(error), context: context, failureTitle: "Cleanup Failed")
            }
            if gitManager.isCurrent(context) {
                await reloadSidePanelBranchData()
            }
            switch result {
            case .success:
                return .succeeded
            case .failure:
                return .failed
            }
        }
    }

    private func batchSummary(_ batch: GitCleanupBatchResult) -> String {
        batch.items.map { item in
            let status = switch item.status {
            case .succeeded:
                "completed"
            case let .partiallySucceeded(reason):
                "partially completed — \(reason)"
            case let .skipped(reason):
                "skipped — \(reason)"
            case let .failed(reason):
                "failed — \(reason)"
            }
            return "\(item.unit?.title ?? item.target.title): \(status)"
        }.joined(separator: "\n")
    }

    func stageSidePanelFile(path: String) async -> MainMenuSidePanelActionResult {
        guard let host else { return .skipped }
        return await host.executeContextualMutation(allowsRepositorySwitch: false) { context in
            let result = await gitManager.stageFileAsync(path: path, context: context)
            await finishSidePanelMutation(result, context: context, failureTitle: "Stage Failed")
            return result.inspectorActionResult
        }
    }

    func unstageSidePanelFile(path: String) async -> MainMenuSidePanelActionResult {
        guard let host else { return .skipped }
        return await host.executeContextualMutation(allowsRepositorySwitch: false) { context in
            let result = await gitManager.unstageFileAsync(path: path, context: context)
            await finishSidePanelMutation(result, context: context, failureTitle: "Unstage Failed")
            return result.inspectorActionResult
        }
    }

    func stageAllSidePanelFiles() async -> MainMenuSidePanelActionResult {
        guard let host else { return .skipped }
        return await host.executeContextualMutation(allowsRepositorySwitch: false) { context in
            let result = await gitManager.stageAllChangesAsync(context: context)
            await finishSidePanelMutation(result, context: context, failureTitle: "Stage Failed")
            return result.inspectorActionResult
        }
    }

    func unstageAllSidePanelFiles() async -> MainMenuSidePanelActionResult {
        guard let host else { return .skipped }
        return await host.executeContextualMutation(allowsRepositorySwitch: false) { context in
            let result = await gitManager.unstageAllChangesAsync(context: context)
            await finishSidePanelMutation(result, context: context, failureTitle: "Unstage Failed")
            return result.inspectorActionResult
        }
    }

    func discardSidePanelFile(
        path: String,
        status: WorkingTreeFileStatus
    ) async -> MainMenuSidePanelActionResult {
        guard let host else { return .skipped }
        return await host.executeContextualMutation(allowsRepositorySwitch: false) { context in
            let result = await gitManager.discardFileChangesAsync(
                path: path,
                status: status,
                context: context
            )
            await finishSidePanelMutation(result, context: context, failureTitle: "Discard Failed")
            return result.inspectorActionResult
        }
    }

    /// Hard-resets the captured repository to `hash`. Blocks project switching for
    /// the full operation because the underlying reset path is not yet a fully
    /// selected-refresh-generation-bound UI transaction.
    func resetSidePanelCommit(hash: String) async -> MainMenuSidePanelActionResult {
        guard let host else { return .skipped }
        return await host.executeContextualMutation(allowsRepositorySwitch: false) { context in
            let result = await gitManager.resetToCommitAsync(hash: hash, context: context)
            await finishSidePanelMutation(result, context: context, failureTitle: "Reset Failed")
            return result.inspectorActionResult
        }
    }

    private func executeSidePanelMutation(
        failureTitle: String,
        operation: (RepositoryOperationContext) async -> Result<Void, Error>
    ) async -> MainMenuSidePanelActionResult {
        guard let host else { return .skipped }
        return await host.executeContextualMutation(allowsRepositorySwitch: false) { context in
            let result = await operation(context)
            await finishSidePanelMutation(result, context: context, failureTitle: failureTitle)
            return result.inspectorActionResult
        }
    }

    private func finishSidePanelMutation(
        _ result: Result<Void, Error>,
        context: RepositoryOperationContext,
        failureTitle: String
    ) async {
        guard let host else { return }
        await gitManager.refreshAsync(includeReflogHistory: false, context: context)
        host.onCommitCompleted?(context.repositoryPath)
        switch result {
        case .success:
            break
        case let .failure(error):
            host.publishAlert(title: failureTitle, message: error.localizedDescription)
        }
    }
}
