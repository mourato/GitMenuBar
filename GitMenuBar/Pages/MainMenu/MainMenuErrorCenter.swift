import SwiftUI

@Observable
@MainActor
final class MainMenuErrorCenter {
    var deleteRepository: String?
    var toggleVisibility: String?
    var discard: String?
    var sync: String?
    var branchSwitch: String?
    var merge: String?
    var deleteBranch: String?
    var renameBranch: String?
    var restart: String?
    var push: String?

    // Ten flat cases by design: one clear site per error domain.
    // swiftlint:disable:next cyclomatic_complexity
    func clear(_ source: MainMenuInlineBannerSource) {
        switch source {
        case .deleteRepository:
            deleteRepository = nil
        case .toggleVisibility:
            toggleVisibility = nil
        case .discard:
            discard = nil
        case .sync:
            sync = nil
        case .branchSwitch:
            branchSwitch = nil
        case .merge:
            merge = nil
        case .deleteBranch:
            deleteBranch = nil
        case .renameBranch:
            renameBranch = nil
        case .restart:
            restart = nil
        case .push:
            push = nil
        case .coordinatorAlert, .coordinatorSuccess:
            break
        }
    }

    /// First pending error in banner priority order.
    var activeSource: MainMenuInlineBannerSource? {
        let sources: [(MainMenuInlineBannerSource, String?)] = [
            (.deleteRepository, deleteRepository),
            (.toggleVisibility, toggleVisibility),
            (.discard, discard),
            (.sync, sync),
            (.branchSwitch, branchSwitch),
            (.merge, merge),
            (.deleteBranch, deleteBranch),
            (.renameBranch, renameBranch),
            (.restart, restart),
            (.push, push)
        ]
        return sources.first { $0.1 != nil }?.0
    }

    func banner(for source: MainMenuInlineBannerSource) -> InlineStatusBanner? {
        let content: (title: String, message: String?)
        switch source {
        case .deleteRepository: content = ("Delete Failed", deleteRepository)
        case .toggleVisibility: content = ("Visibility Update Failed", toggleVisibility)
        case .discard: content = ("Discard Failed", discard)
        case .sync: content = ("Sync Failed", sync)
        case .branchSwitch: content = ("Branch Switch Failed", branchSwitch)
        case .merge: content = ("Merge Failed", merge)
        case .deleteBranch: content = ("Delete Failed", deleteBranch)
        case .renameBranch: content = ("Rename Failed", renameBranch)
        case .restart: content = ("Restart Failed", restart)
        case .push: content = ("Push Failed", push)
        case .coordinatorAlert, .coordinatorSuccess: return nil
        }
        guard let message = content.message else { return nil }
        return InlineStatusBanner(title: content.title, message: message, style: .error)
    }
}
