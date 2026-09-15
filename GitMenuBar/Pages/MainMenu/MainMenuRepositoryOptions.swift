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
            pendingRepositoryOptionsPresentation = true
            return
        }

        pendingRepositoryOptionsPresentation = false
        showRepositoryOptionsPopover = true
    }

    func presentPendingRepositoryOptionsIfPossible() {
        guard pendingRepositoryOptionsPresentation,
              presentationModel.route == .main,
              canPresentRepositoryOptions,
              !showProjectSelector,
              !showBranchSelector,
              !palette.isPresented
        else {
            return
        }

        pendingRepositoryOptionsPresentation = false
        showRepositoryOptionsPopover = true
    }

    func confirmRepositoryVisibilityAction() {
        dismissTransientPresentations()
        showVisibilityConfirmation = true
    }

    func confirmRepositoryDeleteAction() {
        dismissTransientPresentations()
        showDeleteConfirmation = true
    }
}
