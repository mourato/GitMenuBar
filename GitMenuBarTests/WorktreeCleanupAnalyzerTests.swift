@testable import GitMenuBar
import XCTest

final class WorktreeCleanupAnalyzerTests: XCTestCase {
    private let analyzer = WorktreeCleanupAnalyzer()

    func testMergedBranchIsEligibleWhenNotCheckedOut() {
        let input = makeInput(
            localBranches: [reference("feature/merged")],
            mergedLocalNames: ["feature/merged"]
        )

        let snapshot = analyzer.analyze(input)

        XCTAssertEqual(snapshot.branches.first?.status, .mergedIntoDefault)
        XCTAssertTrue(snapshot.branches.first?.isEligible == true)
    }

    func testCurrentAndCheckedOutElsewhereBranchesAreBlocked() {
        let input = makeInput(
            currentBranchName: "main",
            localBranches: [
                reference("main"),
                reference("feature/elsewhere")
            ],
            worktrees: [
                worktree(path: "/repo", branchName: "main", isMain: true),
                worktree(path: "/repo-feature", branchName: "feature/elsewhere")
            ],
            mergedLocalNames: ["main", "feature/elsewhere"]
        )

        let snapshot = analyzer.analyze(input)

        XCTAssertEqual(status(for: "main", in: snapshot), .protected)
        XCTAssertEqual(
            status(for: "feature/elsewhere", in: snapshot),
            .checkedOutElsewhere(path: "/repo-feature")
        )
    }

    func testDirtyLockedPrunableAndDetachedWorktreesAreBlocked() {
        let input = makeInput(
            localBranches: [reference("feature/clean"), reference("feature/dirty")],
            worktrees: [
                worktree(path: "/repo", branchName: "main", isMain: true),
                worktree(path: "/clean", branchName: "feature/clean"),
                worktree(path: "/dirty", branchName: "feature/dirty", state: .dirty),
                worktree(path: "/locked", branchName: "feature/clean", lockReason: "build"),
                worktree(path: "/detached", branchName: nil)
            ],
            mergedLocalNames: ["main", "feature/clean", "feature/dirty"]
        )

        let snapshot = analyzer.analyze(input)

        XCTAssertEqual(worktreeStatus(for: "/repo", in: snapshot), .main)
        XCTAssertEqual(worktreeStatus(for: "/clean", in: snapshot), .eligible)
        XCTAssertEqual(worktreeStatus(for: "/dirty", in: snapshot), .dirty)
        XCTAssertEqual(worktreeStatus(for: "/locked", in: snapshot), .locked(reason: "build"))
        XCTAssertEqual(worktreeStatus(for: "/detached", in: snapshot), .detached)
    }

    func testUnmergedBranchAndWorktreeAreBlocked() {
        let input = makeInput(
            localBranches: [reference("feature/unmerged")],
            worktrees: [worktree(path: "/repo-feature", branchName: "feature/unmerged")],
            mergedLocalNames: []
        )

        let snapshot = analyzer.analyze(input)

        XCTAssertEqual(status(for: "feature/unmerged", in: snapshot), .checkedOutElsewhere(path: "/repo-feature"))
        XCTAssertEqual(worktreeStatus(for: "/repo-feature", in: snapshot), .branchNotMerged)
    }

    func testFailedWorkingTreeStatusIsUnknownAndNotEligible() {
        let input = makeInput(
            localBranches: [reference("feature/unknown")],
            worktrees: [worktree(path: "/unknown", branchName: "feature/unknown", state: .unknown)],
            mergedLocalNames: ["feature/unknown"]
        )

        let snapshot = analyzer.analyze(input)

        XCTAssertEqual(
            worktreeStatus(for: "/unknown", in: snapshot),
            .unknown(reason: "Working tree status is unavailable.")
        )
    }

    func testUnavailableRemoteMergeStatusIsUnknown() {
        let input = makeInput(
            localBranches: [reference("feature/remote-only")],
            remoteBranches: [reference("feature/remote-only", isRemote: true)],
            mergedLocalNames: [],
            mergedRemoteNames: nil
        )

        let snapshot = analyzer.analyze(input)

        XCTAssertEqual(
            snapshot.branches.first {
                $0.reference.name == "feature/remote-only" && $0.reference.isRemote
            }?.status,
            .unknown(reason: "Remote default branch ref is unavailable.")
        )
        XCTAssertFalse(snapshot.branches.contains { $0.reference.isRemote && $0.isEligible })
    }

    private func makeInput(
        defaultBranchName: String = "main",
        currentBranchName: String? = nil,
        localBranches: [GitBranchReference]? = nil,
        worktrees: [GitWorktreeInfo]? = nil,
        remoteBranches: [GitBranchReference] = [],
        mergedLocalNames: Set<String> = ["main"],
        mergedRemoteNames: Set<String>? = []
    ) -> GitWorktreeAnalysisInput {
        GitWorktreeAnalysisInput(
            defaultBranchName: defaultBranchName,
            defaultBranchRef: "refs/heads/\(defaultBranchName)",
            currentBranchName: currentBranchName,
            currentWorktreePath: "/repo",
            worktrees: worktrees ?? [
                GitWorktreeInfo(
                    path: "/repo",
                    headHash: "head-/repo",
                    branchName: "main",
                    isMainWorktree: true,
                    workingTreeState: .clean
                )
            ],
            localBranches: localBranches ?? [
                GitBranchReference(name: "main", headHash: "hash-main", isRemote: false)
            ],
            remoteBranches: remoteBranches,
            mergedLocalBranchNames: mergedLocalNames,
            mergedRemoteBranchNames: mergedRemoteNames,
            analysisDescription: "test"
        )
    }

    private func reference(_ name: String, isRemote: Bool = false) -> GitBranchReference {
        GitBranchReference(name: name, headHash: "hash-\(name)", isRemote: isRemote)
    }

    private func worktree(
        path: String,
        branchName: String?,
        isMain: Bool = false,
        state: GitWorktreeWorkingTreeState = .clean,
        lockReason: String? = nil,
        pruneReason: String? = nil
    ) -> GitWorktreeInfo {
        GitWorktreeInfo(
            path: path,
            headHash: "head-\(path)",
            branchName: branchName,
            isMainWorktree: isMain,
            lockReason: lockReason,
            pruneReason: pruneReason,
            workingTreeState: state
        )
    }

    private func status(for name: String, in snapshot: GitWorktreeSnapshot) -> GitBranchCleanupStatus? {
        snapshot.branches.first { $0.reference.name == name && !$0.reference.isRemote }?.status
    }

    private func worktreeStatus(for path: String, in snapshot: GitWorktreeSnapshot) -> GitWorktreeCleanupStatus? {
        snapshot.worktrees.first { $0.worktree.path == path }?.status
    }
}
