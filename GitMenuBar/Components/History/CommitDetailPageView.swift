import AppKit
import SwiftUI

struct CommitDetailPageView: View {
    @EnvironmentObject var githubAuthManager: GitHubAuthManager
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let commit: Commit?
    let currentHash: String
    let remoteUrl: String
    let isCommitInFuture: (Commit) -> Bool
    let animationNamespace: Namespace.ID
    let onBack: () -> Void
    let onRestoreCommit: (Commit) -> Void
    let onEditCommitMessage: (Commit) -> Void
    let onGenerateCommitMessage: (Commit) -> Void
    var onOpenLocalFile: ((String) -> Void)?
    @State private var authorAvatarURL: URL?
    @State private var loadedAvatarLookupKey: String?

    private var actionSet: HistoryActionSet? {
        guard let commit else {
            return nil
        }

        return HistoryActionSet(
            commit: commit,
            currentHash: currentHash,
            remoteUrl: remoteUrl,
            isCommitInFuture: isCommitInFuture(commit)
        )
    }

    var body: some View {
        VStack(spacing: WorkbenchMetrics.panelPadding) {
            if let commit {
                ScrollView {
                    VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
                        metadataSection(commit: commit)
                        titleSection(commit: commit)
                        statsSection(commit: commit)

                        Divider()

                        changedFilesSection(commit: commit)
                    }
                }
                .frame(maxHeight: 520)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                missingCommitSection
            }
        }
        // Horizontal inset from MainMenuView; top matches main under the shared titlebar toolbar.
        .padding(.top, WorkbenchMetrics.sectionSpacing)
        .task(id: avatarTaskID) {
            await loadAuthorAvatarIfNeeded(for: commit)
        }
    }

    private func metadataSection(commit: Commit) -> some View {
        HStack(alignment: .top, spacing: WorkbenchMetrics.compactSpacing) {
            authorIdentityBadge(for: commit)

            VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                HStack(spacing: WorkbenchMetrics.microSpacing) {
                    Text(commit.authorName)
                        .font(WorkbenchTypography.detail.weight(.semibold))
                    Text(commit.authorEmail)
                        .font(WorkbenchTypography.caption)
                        .foregroundStyle(.secondary)
                }

                Text(timestampLine(for: commit))
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if actionSet?.isFutureCommit == true {
                Text("Future")
                    .font(WorkbenchTypography.captionStrong)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, WorkbenchMetrics.chipSpacing)
                    .padding(.vertical, WorkbenchMetrics.microSpacing)
                    .background(WorkbenchPalette.accentFill(contrast: colorSchemeContrast))
                    .clipShape(Capsule())
                    .accessibilityLabel("Future commit")
            }
        }
    }

    private func titleSection(commit: Commit) -> some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
            Text(commit.subject)
                .font(WorkbenchTypography.windowTitle)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .matchedGeometryEffect(id: "commit-\(commit.id)", in: animationNamespace)

            if !commit.body.isEmpty {
                Text(commit.body)
                    .font(WorkbenchTypography.detail)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statsSection(commit: Commit) -> some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                HStack(spacing: WorkbenchMetrics.sectionSpacing) {
                    Button("Open on GitHub") {
                        if let commitURL = actionSet?.commitURL {
                            NSWorkspace.shared.open(commitURL)
                        }
                    }
                    .workbenchGhost()
                    .disabled(!(actionSet?.canOpenOnGitHub ?? false))

                    Button("Copy Hash") {
                        copyToPasteboard(commit.id)
                    }
                    .workbenchGhost()

                    Button("Copy Message") {
                        copyToPasteboard(commit.subject)
                    }
                    .workbenchGhost()
                }

                HStack(spacing: WorkbenchMetrics.sectionSpacing) {
                    Button("Generate Message with AI") {
                        onGenerateCommitMessage(commit)
                    }
                    .workbenchGhost()
                    .disabled(!(actionSet?.canGenerateMessage ?? false))

                    Button("Edit Message Manually") {
                        onEditCommitMessage(commit)
                    }
                    .workbenchGhost()
                    .disabled(!(actionSet?.canEditMessage ?? false))
                }

                Button("Reset to Here", role: .destructive) {
                    onRestoreCommit(commit)
                }
                .disabled(!(actionSet?.canRestore ?? false))
            }

            if commit.isMergeCommit {
                Text("Editing merge commits is not supported yet.")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func changedFilesSection(commit: Commit) -> some View {
        ChangedFilesSummaryView(
            changedFiles: commit.changedFiles,
            commitSHA: commit.id,
            remoteURL: remoteUrl,
            onOpenLocalFile: onOpenLocalFile
        )
    }

    private var missingCommitSection: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
            Text("Commit not available in current history view.")
                .font(WorkbenchTypography.detail)
                .foregroundStyle(.secondary)

            Button("Back to History") {
                onBack()
            }
            .workbenchGhost()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private var avatarTaskID: String {
        guard let commit else {
            return "none"
        }
        return avatarLookupKey(for: commit)
    }

    @ViewBuilder
    private func authorIdentityBadge(for commit: Commit) -> some View {
        if let authorAvatarURL {
            AsyncImage(url: authorAvatarURL) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    initialsBadge(for: commit)
                }
            }
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.microCornerRadius, style: .continuous))
        } else {
            initialsBadge(for: commit)
        }
    }

    private func initialsBadge(for commit: Commit) -> some View {
        Text(authorInitials(for: commit))
            .font(WorkbenchTypography.detail.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.microCornerRadius, style: .continuous))
    }

    @MainActor
    private func loadAuthorAvatarIfNeeded(for commit: Commit?) async {
        guard let commit else {
            loadedAvatarLookupKey = nil
            authorAvatarURL = nil
            return
        }

        let lookupKey = avatarLookupKey(for: commit)
        guard loadedAvatarLookupKey != lookupKey else {
            return
        }

        loadedAvatarLookupKey = lookupKey
        authorAvatarURL = nil

        guard let reference = GitHubRemoteURLParser.parse(remoteUrl) else {
            return
        }

        let client = GitHubAPIClient(authManager: githubAuthManager)
        authorAvatarURL = await client.fetchCommitAuthorAvatarURL(
            owner: reference.owner,
            repo: reference.repository,
            commitHash: commit.id,
            authorEmail: commit.authorEmail
        )
    }

    private func avatarLookupKey(for commit: Commit) -> String {
        "\(remoteUrl)|\(commit.id)"
    }

    private func authorInitials(for commit: Commit) -> String {
        let characters = commit.authorName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)

        let initials = String(characters)
        return initials.isEmpty ? "?" : initials.uppercased()
    }

    private func timestampLine(for commit: Commit) -> String {
        let relative = HistoryTimelineDateFormatter.relativeTimestamp(for: commit.committedAt)
        let absolute = HistoryTimelineDateFormatter.absoluteTimestamp(for: commit.committedAt)
        return "\(relative) (\(absolute))"
    }
}
