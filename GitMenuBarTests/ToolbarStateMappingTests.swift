@testable import GitMenuBar
import XCTest

extension ToolbarStateMappingTests {
    // MARK: - Working Tree Entry Point

    func testToolbarDoesNotExposeCommitActionWhenChangesExist() {
        let state = makeToolbarState(changeCount: 3)

        XCTAssertEqual(state.repositoryItems, [.branchPicker, .aheadBehind, .fetch])
    }

    func testToolbarDoesNotExposeCommitActionWhileCommitIsBusy() {
        let state = makeToolbarState(
            changeCount: 3,
            isBusy: true,
            progressAccessibilityLabel: "Committing changes"
        )

        XCTAssertEqual(state.repositoryItems, [.branchPicker, .aheadBehind, .fetch])
        XCTAssertNil(state.busyItem)
    }

    // MARK: - Commit Count Belongs to the Working Tree

    @MainActor
    func testGitManagerCommitFileCountMatchesWorkingTreeCommitRule() {
        let gitManager = GitManager(repositoryPathOverride: "")
        gitManager.stagedFiles = []
        gitManager.changedFiles = [
            WorkingTreeFile(path: "A.swift", lineDiff: .zero, status: .modified),
            WorkingTreeFile(path: "B.swift", lineDiff: .zero, status: .untracked),
            WorkingTreeFile(path: "C.swift", lineDiff: .zero, status: .modified)
        ]
        XCTAssertEqual(gitManager.commitFileCount, 3)

        gitManager.stagedFiles = [WorkingTreeFile(path: "A.swift", lineDiff: .zero, status: .modified)]
        XCTAssertEqual(gitManager.commitFileCount, 1)
    }

    // MARK: - Helper

    private func makeToolbarState(
        repositoryName: String = "TestRepo",
        branchName: String = "main",
        aheadCount: Int = 0,
        behindCount: Int = 0,
        changeCount: Int = 0,
        isBusy: Bool = false,
        busyItem: MainWindowToolbarRepositoryItem? = nil,
        progressAccessibilityLabel: String? = nil
    ) -> MainWindowToolbarRepositoryState {
        MainWindowToolbarRepositoryState(
            repositoryName: repositoryName,
            branchName: branchName,
            aheadCount: aheadCount,
            behindCount: behindCount,
            changeCount: changeCount,
            isBusy: isBusy,
            busyItem: busyItem,
            progressAccessibilityLabel: progressAccessibilityLabel
        )
    }
}
