import SwiftUI

extension MainMenuView {
    func requestRepositoryOptionsPopoverPresentation() {
        guard presentationModel.route == .main, canPresentRepositoryOptions else {
            return
        }

        let hadTransientPresentation = hasTransientPresentation || palette.isPresented

        if palette.isPresented {
            closeCommandPalette()
        }

        dismissTransientPresentations()

        if hadTransientPresentation {
            repoOptions.pendingPresentation = true
            return
        }

        repoOptions.pendingPresentation = false
        repoOptions.showRepositoryOptionsPopover = true
    }

    func presentPendingRepositoryOptionsIfPossible() {
        guard repoOptions.pendingPresentation,
              presentationModel.route == .main,
              canPresentRepositoryOptions,
              !repoOptions.showProjectSelector,
              !branchDialogs.showBranchSelector,
              !palette.isPresented
        else {
            return
        }

        repoOptions.pendingPresentation = false
        repoOptions.showRepositoryOptionsPopover = true
    }

    func confirmRepositoryVisibilityAction() {
        dismissTransientPresentations()
        repoConfirm.showVisibilityConfirmation = true
    }

    func confirmRepositoryDeleteAction() {
        dismissTransientPresentations()
        repoConfirm.showDeleteConfirmation = true
    }
}
