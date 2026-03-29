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
            return message
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
        VStack(spacing: 12) {
            // Folder info section
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Folder")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }

                HStack {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(URL(fileURLWithPath: folderPath).lastPathComponent)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(4)
            }

            // Repository name section
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Repository Name")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }

                TextField("my-awesome-project", text: $repoName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            // Visibility section
            RepositoryVisibilityToggle(isPrivate: $isPrivate)

            // Error message
            if showError {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.1))
                .cornerRadius(4)
            }

            Spacer()
                .frame(height: 4)

            // Create button - full width, prominent
            Button(action: createRepository) {
                HStack {
                    if isCreating {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                        Text("Creating...")
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("Create & Publish to GitHub")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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

            await MainActor.run {
                gitManager.refresh(includeReflogHistory: false)
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
