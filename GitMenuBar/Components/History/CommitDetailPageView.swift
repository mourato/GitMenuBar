import AppKit
import SwiftUI

struct CommitDetailPageView: View {
    let commit: Commit?
    let currentHash: String
    let remoteUrl: String
    let isCommitInFuture: (Commit) -> Bool
    let onBack: () -> Void
    let onRestoreCommit: (Commit) -> Void

    var body: some View {
        VStack(spacing: 16) {
            header

            Divider()

            if let commit {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        metadataSection(commit: commit)
                        titleSection(commit: commit)
                        statsSection(commit: commit)
                        
                        Divider()
                        
                        changedFilesSection(commit: commit)
                    }
                }
                .frame(maxHeight: 520)
                .frame(width: .infinity, alignment: .leading)
            } else {
                missingCommitSection
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                onBack()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .focusable(false)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.blue)
                Text("Commit Details")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
    }

    private func metadataSection(commit: Commit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(authorInitials(for: commit))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 2) {
                        Text(commit.authorName)
                            .font(.system(size: 12, weight: .semibold))
                        Text(commit.authorEmail)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Text(timestampLine(for: commit))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)

                if isCommitInFuture(commit) {
                    Text("Future")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
    }
    
    private func titleSection(commit: Commit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(commit.subject)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !commit.body.isEmpty {
                Text(commit.body)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statsSection(commit: Commit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(statsSummary(for: commit))
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                Button("Open on GitHub") {
                    if let commitURL = commitURL(for: commit) {
                        NSWorkspace.shared.open(commitURL)
                    }
                }
                .buttonStyle(.link)
                .disabled(commitURL(for: commit) == nil)

                Text("•")
                    .foregroundColor(.secondary)

                Button("Copy Hash") {
                    copyToPasteboard(commit.id)
                }
                .buttonStyle(.link)

                Text("•")
                    .foregroundColor(.secondary)

                Button("Copy Message") {
                    copyToPasteboard(commit.subject)
                }
                .buttonStyle(.link)
                
                Text("•")
                    .foregroundColor(.secondary)
                
                Button("Reset to Here") {
                    onRestoreCommit(commit)
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .disabled(commit.id == currentHash)
            }
            .font(.system(size: 11, weight: .medium))
        }
    }

    private func changedFilesSection(commit: Commit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Changed Files")
                .font(.system(size: 12, weight: .semibold))

            if commit.changedFiles.isEmpty {
                Text("No file list available for this commit.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(commit.changedFiles) { file in
                        CommitChangedFileRowView(file: file)
                    }
                }
            }
        }
    }

    private var missingCommitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Commit not available in current history view.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            Button("Back to History") {
                onBack()
            }
            .buttonStyle(.borderless)
            .focusable(false)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
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

    private func statsSummary(for commit: Commit) -> String {
        "\(commit.stats.filesChanged) files changed, \(commit.stats.insertions) insertions(+), \(commit.stats.deletions) deletions(-)"
    }

    private func commitURL(for commit: Commit) -> URL? {
        guard let reference = GitHubRemoteURLParser.parse(remoteUrl) else {
            return nil
        }

        return URL(string: "https://github.com/\(reference.owner)/\(reference.repository)/commit/\(commit.id)")
    }
}

private struct CommitChangedFileRowView: View {
    let file: CommitFileChange

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 14, alignment: .center)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(file.fileName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                if !file.directoryPath.isEmpty {
                    Text(file.directoryPath)
                        .font(.system(size: 10, weight: .light))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(0)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                if file.lineDiff.added > 0 {
                    Text("+\(file.lineDiff.added)")
                        .foregroundColor(.green)
                }

                if file.lineDiff.removed > 0 {
                    Text("-\(file.lineDiff.removed)")
                        .foregroundColor(.red)
                }
            }
            .font(.system(size: 10, weight: .medium))
        }
    }
}

private enum CommitDetailPagePreviewData {
    static let commit = Commit(
        id: "1234567890abcdef1234567890abcdef12345678",
        shortHash: "1234567",
        subject: "feat(history): improve commit detail layout and actions",
        body: "Refines metadata, changed files presentation, and quick actions for commit inspection.",
        authorName: "Renato Silva",
        authorEmail: "renato@example.com",
        committedAt: .now.addingTimeInterval(-5400),
        stats: CommitStats(filesChanged: 3, insertions: 48, deletions: 12),
        changedFiles: [
            CommitFileChange(
                path: "GitMenuBar/Components/History/CommitDetailPageView.swift",
                lineDiff: LineDiffStats(added: 32, removed: 9)
            ),
            CommitFileChange(
                path: "GitMenuBar/Services/Git/GitManager.swift",
                lineDiff: LineDiffStats(added: 14, removed: 3)
            ),
            CommitFileChange(
                path: "README.md",
                lineDiff: LineDiffStats(added: 2, removed: 0)
            )
        ]
    )
}

#Preview("Commit Detail") {
    CommitDetailPageView(
        commit: CommitDetailPagePreviewData.commit,
        currentHash: "abcdef1234567890",
        remoteUrl: "https://github.com/example/repo.git",
        isCommitInFuture: { _ in false },
        onBack: {},
        onRestoreCommit: { _ in }
    )
    .frame(width: 400, height: 580)
}

#Preview("Commit Detail - Missing Commit") {
    CommitDetailPageView(
        commit: nil,
        currentHash: "abcdef1234567890",
        remoteUrl: "https://github.com/example/repo.git",
        isCommitInFuture: { _ in false },
        onBack: {},
        onRestoreCommit: { _ in }
    )
    .padding()
    .frame(width: 400)
}
