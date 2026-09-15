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
}
