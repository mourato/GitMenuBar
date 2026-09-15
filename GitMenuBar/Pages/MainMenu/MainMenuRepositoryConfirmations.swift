import Foundation

@Observable
@MainActor
final class MainMenuRepositoryConfirmations {
    var showDeleteConfirmation = false
    var isDeleting = false
    var showVisibilityConfirmation = false
    var isTogglingVisibility = false
    var showRestartConfirmation = false
}
