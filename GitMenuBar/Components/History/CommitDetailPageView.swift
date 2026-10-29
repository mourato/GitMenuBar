import AppKit
import SwiftUI

struct CommitDetailPageView: View {
    @Environment(GitHubAuthManager.self) var githubAuthManager
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let commit: Commit?
    let currentHash: String
    let remoteUrl: String
    let isCommitInFuture: (Commit) -> Bool
    let onClose: () -> Void
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
        VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
            headerRow

            if let commit {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
                        authorMetadataSection(commit: commit)

                        if !commit.body.isEmpty {
                            bodySection(commit: commit)
                        }

                        statsSection(commit: commit)

                        Divider()

                        changedFilesSection(commit: commit)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Text("Commit not available in current history view.")
                    .font(WorkbenchTypography.detail)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: avatarTaskID) {
            await loadAuthorAvatarIfNeeded(for: commit)
        }
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: WorkbenchMetrics.compactSpacing) {
            if let commit {
                Text(commit.subject)
                    .font(WorkbenchTypography.windowTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            } else {
                Text("Commit Details")
                    .font(WorkbenchTypography.windowTitle)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
            }

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: WorkbenchMetrics.iconHitTarget, height: WorkbenchMetrics.iconHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close details")
            .accessibilityLabel("Close details")
        }
    }

    private func authorMetadataSection(commit: Commit) -> some View {
        HStack(alignment: .top, spacing: WorkbenchMetrics.compactSpacing) {
            authorIdentityBadge(for: commit)

            VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                HStack(spacing: WorkbenchMetrics.compactSpacing) {
                    Text(commit.authorName)
                        .font(WorkbenchTypography.detail.weight(.semibold))
                        .help(commit.authorEmail)

                    shortHashChip(for: commit)
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

    private func shortHashChip(for commit: Commit) -> some View {
        Button {
            copyToPasteboard(commit.id)
            AccessibilityNotification.Announcement("Commit hash copied").post()
        } label: {
            Text(commit.shortHash)
                .font(WorkbenchTypography.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, WorkbenchMetrics.chipSpacing)
                .padding(.vertical, WorkbenchMetrics.microSpacing)
                .background(WorkbenchPalette.hoverFill())
                .clipShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.microCornerRadius, style: .continuous))
                .frame(minHeight: WorkbenchMetrics.iconHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(commit.id)
        .accessibilityLabel("Copy commit hash")
    }

    private func bodySection(commit: Commit) -> some View {
        Text(commit.body)
            .font(WorkbenchTypography.detail)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func statsSection(commit: Commit) -> some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            Button("Open on GitHub") {
                if let commitURL = actionSet?.commitURL {
                    NSWorkspace.shared.open(commitURL)
                }
            }
            .workbenchSecondary()
            .disabled(!(actionSet?.canOpenOnGitHub ?? false))

            Menu {
                Button("Copy Hash") {
                    copyToPasteboard(commit.id)
                }

                Button("Copy Short Hash") {
                    copyToPasteboard(commit.shortHash)
                }

                Button("Copy Message") {
                    let message = commit.body.isEmpty ? commit.subject : "\(commit.subject)\n\n\(commit.body)"
                    copyToPasteboard(message)
                }
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .workbenchGhost()

            Menu {
                if !commit.isMergeCommit {
                    Button("Generate Message with AI") {
                        onGenerateCommitMessage(commit)
                    }
                    .disabled(!(actionSet?.canGenerateMessage ?? false))

                    Button("Edit Message") {
                        onEditCommitMessage(commit)
                    }
                    .disabled(!(actionSet?.canEditMessage ?? false))

                    Divider()
                }

                Button("Reset to Here", role: .destructive) {
                    onRestoreCommit(commit)
                }
                .disabled(!(actionSet?.canRestore ?? false))
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(WorkbenchTypography.body)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .workbenchIcon()
            .accessibilityLabel("More commit actions")
            .help("More commit actions")
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

    private func avatarBadge(@ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(width: 24, height: 24)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            }
    }

    @ViewBuilder
    private func authorIdentityBadge(for commit: Commit) -> some View {
        if let authorAvatarURL {
            avatarBadge {
                AsyncImage(url: authorAvatarURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        initialsBadgeFill(for: commit)
                    }
                }
            }
        } else {
            initialsBadge(for: commit)
        }
    }

    private func initialsBadge(for commit: Commit) -> some View {
        avatarBadge {
            initialsBadgeFill(for: commit)
        }
    }

    private func initialsBadgeFill(for commit: Commit) -> some View {
        Text(authorInitials(for: commit))
            .font(WorkbenchTypography.detail.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Color.accentColor)
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
