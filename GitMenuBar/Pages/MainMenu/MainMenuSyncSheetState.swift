import Foundation

@Observable
@MainActor
final class MainMenuSyncSheetState {
    var selectedPushBranch = ""
    var showPullToNewBranch = false
    var pullToNewBranchName = ""
    var useRebase = false

    func syncWithRemote(using actionCoordinator: MainMenuActionCoordinator) {
        Task {
            await actionCoordinator.syncWithRemote(rebase: useRebase).playHapticFeedback()
        }
    }

    func pullToNewBranch(using actionCoordinator: MainMenuActionCoordinator, errorCenter: MainMenuErrorCenter) {
        let name = pullToNewBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        Task {
            switch await actionCoordinator.pullToNewBranch(named: name) {
            case .succeeded:
                showPullToNewBranch = false
                pullToNewBranchName = ""
            case let .failed(message):
                errorCenter.sync = message
            }
        }
    }
}

extension MainMenuSyncExecutionResult {
    @MainActor
    func playHapticFeedback() {
        if self == .synced {
            HapticFeedback.actionSucceeded()
        } else if self == .failed {
            HapticFeedback.actionFailed()
        }
    }
}
