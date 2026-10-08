import Foundation

@Observable
@MainActor
final class MainMenuRepositoryConfirmations {
    var showDeleteConfirmation = false
    var isDeleting = false
    var showVisibilityConfirmation = false
    var isTogglingVisibility = false
    var showRestartConfirmation = false

    func deleteRepository(using gitManager: GitManager, authManager: GitHubAuthManager, errorCenter: MainMenuErrorCenter, onDeleted: @escaping @MainActor () -> Void) {
        isDeleting = true

        Task {
            do {
                let repositoryService = GitHubRepositoryService(authManager: authManager)
                try await repositoryService.deleteRepository(remoteURL: gitManager.remoteUrl)
                isDeleting = false
                // Clear the remote URL since repo is deleted
                gitManager.remoteUrl = ""
                onDeleted()
            } catch {
                isDeleting = false
                errorCenter.deleteRepository = error.localizedDescription
            }
        }
    }

    func toggleRepoVisibility(using gitManager: GitManager, authManager: GitHubAuthManager, errorCenter: MainMenuErrorCenter) {
        isTogglingVisibility = true
        let newStatus = !gitManager.isPrivate

        Task {
            do {
                let repositoryService = GitHubRepositoryService(authManager: authManager)
                _ = try await repositoryService.updateVisibility(
                    remoteURL: gitManager.remoteUrl,
                    isPrivate: newStatus
                )
                isTogglingVisibility = false
                await gitManager.checkRepoVisibilityAsync()
            } catch {
                isTogglingVisibility = false
                errorCenter.toggleVisibility = error.localizedDescription
            }
        }
    }
}
