import Foundation

@Observable
@MainActor
final class MainMenuRepositoryOptionsState {
    var showProjectSelector = false
    var showRepositoryOptionsPopover = false
    var pendingPresentation = false
    private(set) var lastHandledToken = 0

    /// Claims a presentation token. Returns false when the token was already handled.
    func claimPresentationRequest(_ token: Int) -> Bool {
        guard token > lastHandledToken else {
            return false
        }

        lastHandledToken = token
        return true
    }

    /// Shows the popover now, or defers it until competing presentations close.
    func requestPresentation(deferred: Bool) {
        pendingPresentation = deferred
        if !deferred {
            showRepositoryOptionsPopover = true
        }
    }

    /// Shows a deferred popover once `isUnobstructed` and the project selector is closed.
    func presentPendingIfPossible(isUnobstructed: Bool) {
        guard pendingPresentation, isUnobstructed, !showProjectSelector else {
            return
        }

        pendingPresentation = false
        showRepositoryOptionsPopover = true
    }
}
