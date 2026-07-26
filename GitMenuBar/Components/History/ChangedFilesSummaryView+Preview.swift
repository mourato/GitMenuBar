import SwiftUI

private enum ChangedFilesSummaryPreviewData {
    static let fewFiles: [CommitFileChange] = [
        CommitFileChange(
            path: "GitMenuBar/Components/History/ChangedFilesSummaryView.swift",
            lineDiff: LineDiffStats(added: 120, removed: 12)
        ),
        CommitFileChange(
            path: "GitMenuBar/Utils/GitHub/GitHubRemoteURLParser.swift",
            lineDiff: LineDiffStats(added: 24, removed: 2)
        ),
        CommitFileChange(
            path: "README.md",
            lineDiff: LineDiffStats(added: 4, removed: 0)
        )
    ]

    static let manyFiles: [CommitFileChange] = [
        CommitFileChange(path: "GitMenuBar/Pages/MainMenu/MainMenuContent.swift", lineDiff: LineDiffStats(added: 42, removed: 8)),
        CommitFileChange(path: "GitMenuBar/Pages/MainMenu/MainMenuView.swift", lineDiff: LineDiffStats(added: 18, removed: 3)),
        CommitFileChange(path: "GitMenuBar/Services/Git/GitManager.swift", lineDiff: LineDiffStats(added: 64, removed: 21)),
        CommitFileChange(
            path: "GitMenuBar/Components/History/HistoryTimelineSectionView.swift",
            lineDiff: LineDiffStats(added: 12, removed: 6)
        ),
        CommitFileChange(path: "GitMenuBar/Components/WorkingTree/WorkingTreeFileRow.swift", lineDiff: LineDiffStats(added: 9, removed: 1)),
        CommitFileChange(path: "GitMenuBarTests/DiffTreeBuilderTests.swift", lineDiff: LineDiffStats(added: 55, removed: 0)),
        CommitFileChange(path: "docs/architecture/overview.md", lineDiff: LineDiffStats(added: 7, removed: 2)),
        CommitFileChange(path: "Resources/Assets.xcassets/AppIcon.appiconset/Contents.json", lineDiff: LineDiffStats(added: 1, removed: 1))
    ]
}

#Preview("Changed Files Summary — Expanded") {
    ChangedFilesSummaryView(
        changedFiles: ChangedFilesSummaryPreviewData.fewFiles,
        commitSHA: "1234567890abcdef1234567890abcdef12345678",
        remoteURL: "https://github.com/example/repo.git"
    )
    .padding()
    .frame(width: 420, alignment: .leading)
}

#Preview("Changed Files Summary — Compact Preview") {
    ChangedFilesSummaryView(
        changedFiles: ChangedFilesSummaryPreviewData.manyFiles,
        commitSHA: "1234567890abcdef1234567890abcdef12345678",
        remoteURL: "https://github.com/example/repo.git"
    )
    .padding()
    .frame(width: 420, alignment: .leading)
}

#Preview("Changed Files Summary — Empty") {
    ChangedFilesSummaryView(
        changedFiles: [],
        commitSHA: "1234567890abcdef1234567890abcdef12345678",
        remoteURL: "https://github.com/example/repo.git"
    )
    .padding()
    .frame(width: 420, alignment: .leading)
}

#Preview("Changed Files Summary — Local Remote") {
    ChangedFilesSummaryView(
        changedFiles: ChangedFilesSummaryPreviewData.fewFiles,
        commitSHA: "1234567890abcdef1234567890abcdef12345678",
        remoteURL: "/Users/example/project/.git",
        onOpenLocalFile: { _ in }
    )
    .padding()
    .frame(width: 420, alignment: .leading)
}
