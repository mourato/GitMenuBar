import SwiftUI

extension MainMenuView {
    func requestRepositoryOptionsPopoverPresentation() {
        guard presentationModel.route == .main, canPresentRepositoryOptions else {
            return
        }

        let hadTransientPresentation = showProjectSelector || showBranchSelector || isCommandPalettePresented

        if isCommandPalettePresented {
            closeCommandPalette()
        }

        showProjectSelector = false
        showBranchSelector = false
        showRepositoryOptionsPopover = false

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
        showRepositoryOptionsPopover = false
        pendingRepositoryOptionsPresentation = false
        showVisibilityConfirmation = true
    }

    func confirmRepositoryDeleteAction() {
        showRepositoryOptionsPopover = false
        pendingRepositoryOptionsPresentation = false
        showDeleteConfirmation = true
    }
}
