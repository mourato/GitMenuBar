import Foundation

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
}
