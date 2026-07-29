import SwiftUI

extension MainMenuView {
    func requestRepositoryOptionsPopoverPresentation() {
        guard presentationModel.route == .main, canPresentRepositoryOptions else {
            return
        }

        let hadTransientPresentation = hasTransientPresentation || isCommandPalettePresented

        if isCommandPalettePresented {
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
              !isCommandPalettePresented
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
