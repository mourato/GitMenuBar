//
//  CreateRepositoryView.swift
//  GitMenuBar
//

import SwiftUI

private enum CreateRepositoryFlowError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(message):
            message
        }
    }
}

/// Content view for creating a repository - designed to be embedded inline
struct CreateRepoContentView: View {
    @EnvironmentObject var gitManager: GitManager
    @EnvironmentObject var githubAuthManager: GitHubAuthManager

    let folderPath: String
    let onDismiss: () -> Void
    let onSuccess: (String) -> Void

    @State private var repoName: String
    @State private var isPrivate: Bool = true
    @State private var isCreating: Bool = false
    @State private var errorMessage: String = ""
    @State private var showError: Bool = false

    init(folderPath: String, onDismiss: @escaping () -> Void, onSuccess: @escaping (String) -> Void) {
        self.folderPath = folderPath
        self.onDismiss = onDismiss
        self.onSuccess = onSuccess
        // Pre-fill with folder name
        let folderName = URL(fileURLWithPath: folderPath).lastPathComponent
        _repoName = State(initialValue: folderName)
    }

    var body: some View {
        VStack(spacing: WorkbenchMetrics.sectionSpacing) {
            // Folder info section
            VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                SettingsFormSectionHeader(title: "Folder", icon: "folder")

                HStack {
                    Image(systemName: "folder.fill")
                        .font(WorkbenchTypography.caption)
                        .foregroundStyle(.secondary)
                    Text(URL(fileURLWithPath: folderPath).lastPathComponent)
                        .font(WorkbenchTypography.caption)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, WorkbenchMetrics.compactSpacing)
                .padding(.vertical, WorkbenchMetrics.chipSpacing)
                .background(
                    .quaternary.opacity(0.16),
                    in: RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous)
                )
            }

            // Repository name section
            VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                SettingsFormSectionHeader(title: "Repository Name", icon: "text.cursor")

                TextField("my-awesome-project", text: $repoName)
                    .textFieldStyle(.roundedBorder)
                    .font(WorkbenchTypography.detail)
            }

            // Visibility section
            RepositoryVisibilityToggle(isPrivate: $isPrivate)

            // Error message
            if showError {
                InlineStatusBannerView(
                    banner: InlineStatusBanner(title: nil, message: errorMessage, style: .error),
                    onDismiss: {
                        showError = false
                        errorMessage = ""
                    }
                )
            }

            // Create button - full width, prominent
            Button(action: createRepository) {
                HStack {
                    if isCreating {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                        Text("Creating")
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("Create & Publish to GitHub")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .workbenchPrimary()
            .keyboardShortcut(.defaultAction)
            .disabled(repoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
        }
    }

    private func createRepository() {
        let trimmedName = repoName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        isCreating = true
        showError = false

        Task {
            await performCreateRepository(named: trimmedName)
        }
    }

    private func performCreateRepository(named repositoryName: String) async {
        do {
            let repository = try await createRemoteRepository(named: repositoryName)
            try ensureLocalRepositoryReady()
            try configureRemote(with: repository.cloneUrl)
            try pushRepository()

            await gitManager.refreshAsync(includeReflogHistory: false)
            await MainActor.run {
                onSuccess(folderPath)
            }
        } catch let error as CreateRepositoryFlowError {
            await showErrorMessage(error.localizedDescription)
        } catch let error as GitHubAPIError {
            await showGitHubError(error)
        } catch {
            await showErrorMessage("Unexpected error: \(error.localizedDescription)")
        }
    }

    private func createRemoteRepository(named repositoryName: String) async throws -> GitHubRepository {
        let repositoryService = GitHubRepositoryService(authManager: githubAuthManager)
        return try await repositoryService.createOrFetchRepository(
            name: repositoryName,
            isPrivate: isPrivate,
            description: nil
        )
    }

    private func ensureLocalRepositoryReady() throws {
        if gitManager.isGitRepository(at: folderPath) {
            try commitExistingChangesIfNeeded()
            return
        }

        guard gitManager.initializeRepository(at: folderPath) else {
            throw CreateRepositoryFlowError.message("Failed to initialize local git repository")
        }

        try createInitialCommit(message: "Failed to create initial commit")
    }

    private func commitExistingChangesIfNeeded() throws {
        guard gitManager.hasUncommittedChanges(at: folderPath) else {
            return
        }

        try createInitialCommit(message: "Failed to commit existing changes")
    }

    private func createInitialCommit(message: String) throws {
        guard gitManager.createInitialCommit(at: folderPath, message: "Initial commit") else {
            throw CreateRepositoryFlowError.message(message)
        }
    }

    private func configureRemote(with cloneURL: String) throws {
        if gitManager.hasRemoteConfigured(at: folderPath) {
            guard gitManager.updateRemoteURL(at: folderPath, newURL: cloneURL) else {
                throw CreateRepositoryFlowError.message("Failed to update remote URL")
            }
            return
        }

        guard gitManager.addRemote(at: folderPath, url: cloneURL) else {
            throw CreateRepositoryFlowError.message("Failed to add remote")
        }
    }

    private func pushRepository() throws {
        guard gitManager.pushToNewRemote(at: folderPath) else {
            throw CreateRepositoryFlowError.message("Failed to push to GitHub")
        }
    }

    @MainActor
    private func showGitHubError(_ error: GitHubAPIError) {
        switch error {
        case .unauthorized:
            showErrorMessage("GitHub authentication failed. Please reconnect.")
        case .rateLimitExceeded:
            showErrorMessage("GitHub rate limit exceeded. Please try again later.")
        case let .networkError(networkError):
            showErrorMessage("Network error: \(networkError.localizedDescription)")
        default:
            showErrorMessage("Failed to create repository: \(error)")
        }
    }

    @MainActor
    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
        isCreating = false
    }
}

#Preview {
    CreateRepoContentView(
        folderPath: "/tmp/example-project",
        onDismiss: {},
        onSuccess: { _ in }
    )
    .environmentObject(GitManager(repositoryPathOverride: "/tmp"))
    .environmentObject(GitHubAuthManager(
        tokenStore: InMemoryGitHubTokenStore(),
        preloadStoredToken: false
    ))
    .padding()
    .frame(width: 380)
}
