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

    /// Pending errors in banner priority order, with their banner titles.
    private var entries: [(source: MainMenuInlineBannerSource, banner: (title: String, message: String?))] {
        [
            (.deleteRepository, ("Delete Failed", deleteRepository)),
            (.toggleVisibility, ("Visibility Update Failed", toggleVisibility)),
            (.discard, ("Discard Failed", discard)),
            (.sync, ("Sync Failed", sync)),
            (.branchSwitch, ("Branch Switch Failed", branchSwitch)),
            (.merge, ("Merge Failed", merge)),
            (.deleteBranch, ("Delete Failed", deleteBranch)),
            (.renameBranch, ("Rename Failed", renameBranch)),
            (.restart, ("Restart Failed", restart)),
            (.push, ("Push Failed", push))
        ]
    }

    /// First pending error in banner priority order.
    var activeSource: MainMenuInlineBannerSource? {
        entries.first { $0.banner.message != nil }?.source
    }

    func banner(for source: MainMenuInlineBannerSource) -> InlineStatusBanner? {
        guard let entry = entries.first(where: { $0.source == source }), let message = entry.banner.message else {
            return nil
        }
        return InlineStatusBanner(title: entry.banner.title, message: message, style: .error)
    }
}
