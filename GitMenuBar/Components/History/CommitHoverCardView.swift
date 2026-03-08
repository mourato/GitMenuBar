import AppKit
import SwiftUI

struct CommitHoverCardView: View {
    let commit: Commit
    let remoteUrl: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            subject

            if !commit.body.isEmpty {
                bodyText
            }

            Divider()

            footer
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(authorInitials)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(commit.authorName)
                    .font(.system(size: 12, weight: .semibold))

                Text(timestampLine)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
    }

    private var subject: some View {
        Text(commit.subject)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var bodyText: some View {
        ScrollView {
            Text(commit.body)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: 108)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(statsSummary)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Text(commit.shortHash)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentColor)

                Spacer()

                if let commitURL {
                    Button("Open on GitHub") {
                        NSWorkspace.shared.open(commitURL)
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11, weight: .medium))
                }
            }
        }
    }

    private var authorInitials: String {
        let characters = commit.authorName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)

        let initials = String(characters)
        return initials.isEmpty ? "?" : initials.uppercased()
    }

    private var timestampLine: String {
        let relative = HistoryTimelineDateFormatter.relativeTimestamp(for: commit.committedAt)
        let absolute = HistoryTimelineDateFormatter.absoluteTimestamp(for: commit.committedAt)
        return "\(relative) (\(absolute))"
    }

    private var statsSummary: String {
        "\(commit.stats.filesChanged) files changed, \(commit.stats.insertions) insertions(+), \(commit.stats.deletions) deletions(-)"
    }

    private var commitURL: URL? {
        guard let reference = GitHubRemoteURLParser.parse(remoteUrl) else {
            return nil
        }

        return URL(string: "https://github.com/\(reference.owner)/\(reference.repository)/commit/\(commit.id)")
    }
}

enum HistoryTimelineDateFormatter {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private static let rowTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static let rowDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()

    static func rowTimestamp(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return rowTimeFormatter.string(from: date)
        }

        return rowDateFormatter.string(from: date)
    }

    static func relativeTimestamp(for date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    static func absoluteTimestamp(for date: Date) -> String {
        absoluteFormatter.string(from: date)
    }
}

#Preview("Commit Hover Card") {
    CommitHoverCardView(
        commit: Commit(
            id: "68d8e91c7a0b7f4c1d2e3f4567890abc12345678",
            shortHash: "68d8e91",
            subject: "feat(git): improve status bar and menu item logic",
            body: """
            - Introduce StatusBarContextMenuActionState for dynamic menu entries.
            - Refactor StatusBarController to centralize visibility rules.
            - Add tests for the updated action state logic.
            """,
            authorName: "Renato Costa",
            authorEmail: "renato@example.com",
            committedAt: .now.addingTimeInterval(-13 * 3600),
            stats: CommitStats(filesChanged: 5, insertions: 114, deletions: 19),
            changedFiles: [
                CommitFileChange(path: "GitMenuBar/App/StatusBarController.swift", lineDiff: LineDiffStats(added: 72, removed: 12))
            ]
        ),
        remoteUrl: "https://github.com/example/gitmenubar"
    )
    .padding()
    .frame(width: 340)
}
