import SwiftUI

private enum ChangedFilesSummaryPreviewData {
    static let singleFile: [CommitFileChange] = [
        CommitFileChange(
            path: "GitMenuBar/Components/History/CommitDetailPageView.swift",
            lineDiff: LineDiffStats(added: 38, removed: 6)
        )
    ]

    static let twoGroups: [CommitFileChange] = [
        CommitFileChange(
            path: "GitMenuBar/Components/History/ChangedFilesSummaryView.swift",
            lineDiff: LineDiffStats(added: 120, removed: 12)
        ),
        CommitFileChange(
            path: "GitMenuBar/Components/History/CommitDetailPageView.swift",
            lineDiff: LineDiffStats(added: 24, removed: 2)
        ),
        CommitFileChange(
            path: "GitMenuBar/Utils/GitHub/GitHubRemoteURLParser.swift",
            lineDiff: LineDiffStats(added: 7, removed: 1)
        ),
        CommitFileChange(
            path: "docs/ui.md",
            lineDiff: LineDiffStats(added: 4, removed: 0)
        )
    ]

    static let thirtyFiles: [CommitFileChange] = [
        CommitFileChange(path: "GitMenuBar/App/AppDelegate.swift", lineDiff: LineDiffStats(added: 42, removed: 8)),
        CommitFileChange(path: "GitMenuBar/App/MainWindowController.swift", lineDiff: LineDiffStats(added: 18, removed: 3)),
        CommitFileChange(path: "GitMenuBar/App/StatusBarController.swift", lineDiff: LineDiffStats(added: 64, removed: 21)),
        CommitFileChange(path: "GitMenuBar/App/WorkbenchWindowChrome.swift", lineDiff: LineDiffStats(added: 12, removed: 6)),
        CommitFileChange(path: "GitMenuBar/Components/Common/WorkbenchButtonStyles.swift", lineDiff: LineDiffStats(added: 9, removed: 1)),
        CommitFileChange(path: "GitMenuBar/Components/Common/WorkbenchMetrics.swift", lineDiff: LineDiffStats(added: 55, removed: 0)),
        CommitFileChange(path: "GitMenuBar/Components/Common/WorkbenchMotion.swift", lineDiff: LineDiffStats(added: 7, removed: 2)),
        CommitFileChange(path: "GitMenuBar/Components/History/ChangedFilesDiffTreeViews.swift", lineDiff: LineDiffStats(added: 1, removed: 1)),
        CommitFileChange(path: "GitMenuBar/Components/History/ChangedFilesSummaryView.swift", lineDiff: LineDiffStats(added: 96, removed: 74)),
        CommitFileChange(path: "GitMenuBar/Components/History/CommitDetailPageView.swift", lineDiff: LineDiffStats(added: 31, removed: 12)),
        CommitFileChange(path: "GitMenuBar/Components/History/HistoryTimelineSectionView.swift", lineDiff: LineDiffStats(added: 5, removed: 0)),
        CommitFileChange(path: "GitMenuBar/Components/WorkingTree/WorkingTreeFileRow.swift", lineDiff: LineDiffStats(added: 14, removed: 9)),
        CommitFileChange(path: "GitMenuBar/Components/WorkingTree/WorkingTreeSectionHeaderView.swift", lineDiff: LineDiffStats(added: 3, removed: 3)),
        CommitFileChange(path: "GitMenuBar/Models/GitModels.swift", lineDiff: LineDiffStats(added: 2, removed: 0)),
        CommitFileChange(path: "GitMenuBar/Pages/MainMenu/MainMenuContent.swift", lineDiff: LineDiffStats(added: 21, removed: 4)),
        CommitFileChange(path: "GitMenuBar/Pages/MainMenu/MainMenuView.swift", lineDiff: LineDiffStats(added: 8, removed: 8)),
        CommitFileChange(path: "GitMenuBar/Pages/MainMenu/HistorySidePanelView.swift", lineDiff: LineDiffStats(added: 17, removed: 5)),
        CommitFileChange(path: "GitMenuBar/Pages/MainMenu/SidePanelDetailView.swift", lineDiff: LineDiffStats(added: 40, removed: 16)),
        CommitFileChange(path: "GitMenuBar/Pages/Settings/SettingsView.swift", lineDiff: LineDiffStats(added: 6, removed: 2)),
        CommitFileChange(path: "GitMenuBar/Services/Git/GitManager.swift", lineDiff: LineDiffStats(added: 27, removed: 11)),
        CommitFileChange(path: "GitMenuBar/Services/GitHub/GitHubAuthManager.swift", lineDiff: LineDiffStats(added: 0, removed: 9)),
        CommitFileChange(path: "GitMenuBar/Utils/DiffTree/DiffTreeBuilder.swift", lineDiff: LineDiffStats(added: 4, removed: 1)),
        CommitFileChange(path: "GitMenuBarTests/ChangedFilesPresentationTests.swift", lineDiff: LineDiffStats(added: 88, removed: 12)),
        CommitFileChange(path: "GitMenuBarTests/CommitDetailPresentationTests.swift", lineDiff: LineDiffStats(added: 9, removed: 0)),
        CommitFileChange(path: "docs/agents/project-workflow.md", lineDiff: LineDiffStats(added: 6, removed: 1)),
        CommitFileChange(path: "docs/adr/0021-side-panel-split-column.md", lineDiff: LineDiffStats(added: 12, removed: 0)),
        CommitFileChange(path: "docs/ui.md", lineDiff: LineDiffStats(added: 3, removed: 3)),
        CommitFileChange(path: "Makefile", lineDiff: LineDiffStats(added: 1, removed: 0)),
        CommitFileChange(path: "README.md", lineDiff: LineDiffStats(added: 2, removed: 5)),
        CommitFileChange(path: "Resources/Assets.xcassets/AppIcon.appiconset/Contents.json", lineDiff: LineDiffStats(added: 1, removed: 1))
    ]

    static let longPath: [CommitFileChange] = [
        CommitFileChange(
            path: "GitMenuBar/Components/History/CommitInspector/ChangedFilesDirectoryBreadcrumb/"
                + "ChangedFilesDirectoryBreadcrumbFormatter.swift",
            lineDiff: LineDiffStats(added: 218, removed: 37)
        ),
        CommitFileChange(
            path: "GitMenuBarTests/Components/History/CommitInspector/ChangedFilesDirectoryBreadcrumb/"
                + "ChangedFilesDirectoryBreadcrumbFormatterTests.swift",
            lineDiff: LineDiffStats(added: 146, removed: 0)
        )
    ]
}

#Preview("Changed Files — 1 File") {
    ChangedFilesSummaryView(
        changedFiles: ChangedFilesSummaryPreviewData.singleFile,
        commitSHA: "1234567890abcdef1234567890abcdef12345678",
        remoteURL: "https://github.com/example/repo.git"
    )
    .padding()
    .frame(width: WorkbenchMetrics.sidePanelWidth - (WorkbenchMetrics.panelPadding * 2), alignment: .leading)
}

#Preview("Changed Files — 4 Files in Two Groups") {
    ChangedFilesSummaryView(
        changedFiles: ChangedFilesSummaryPreviewData.twoGroups,
        commitSHA: "1234567890abcdef1234567890abcdef12345678",
        remoteURL: "https://github.com/example/repo.git"
    )
    .padding()
    .frame(width: WorkbenchMetrics.sidePanelWidth - (WorkbenchMetrics.panelPadding * 2), alignment: .leading)
}

#Preview("Changed Files — 4 Files in Two Groups Dark") {
    ChangedFilesSummaryView(
        changedFiles: ChangedFilesSummaryPreviewData.twoGroups,
        commitSHA: "1234567890abcdef1234567890abcdef12345678",
        remoteURL: "https://github.com/example/repo.git"
    )
    .padding()
    .frame(width: WorkbenchMetrics.sidePanelWidth - (WorkbenchMetrics.panelPadding * 2), alignment: .leading)
    .preferredColorScheme(.dark)
}

#Preview("Changed Files — 30 Files") {
    ChangedFilesSummaryView(
        changedFiles: ChangedFilesSummaryPreviewData.thirtyFiles,
        commitSHA: "1234567890abcdef1234567890abcdef12345678",
        remoteURL: "https://github.com/example/repo.git"
    )
    .padding()
    .frame(width: WorkbenchMetrics.sidePanelWidth - (WorkbenchMetrics.panelPadding * 2), alignment: .leading)
}

#Preview("Changed Files — Long Path") {
    ChangedFilesSummaryView(
        changedFiles: ChangedFilesSummaryPreviewData.longPath,
        commitSHA: "1234567890abcdef1234567890abcdef12345678",
        remoteURL: "https://github.com/example/repo.git"
    )
    .padding()
    .frame(width: WorkbenchMetrics.sidePanelWidth - (WorkbenchMetrics.panelPadding * 2), alignment: .leading)
}

#Preview("Changed Files — Empty") {
    ChangedFilesSummaryView(
        changedFiles: [],
        commitSHA: "1234567890abcdef1234567890abcdef12345678",
        remoteURL: "https://github.com/example/repo.git"
    )
    .padding()
    .frame(width: WorkbenchMetrics.sidePanelWidth - (WorkbenchMetrics.panelPadding * 2), alignment: .leading)
}

#Preview("Changed Files — Local Remote") {
    ChangedFilesSummaryView(
        changedFiles: ChangedFilesSummaryPreviewData.twoGroups,
        commitSHA: "1234567890abcdef1234567890abcdef12345678",
        remoteURL: "/Users/example/project/.git",
        onOpenLocalFile: { _ in }
    )
    .padding()
    .frame(width: WorkbenchMetrics.sidePanelWidth - (WorkbenchMetrics.panelPadding * 2), alignment: .leading)
}
