@testable import GitMenuBar
import XCTest

final class BranchListModelTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Test Helpers

    private func makeLocalBranch(
        name: String,
        isCurrent: Bool = false,
        trackingStatus: BranchTrackingStatus = .noRemote,
        lastCommitDate: Date? = nil
    ) -> BranchInfo {
        BranchInfo(
            name: name,
            isLocal: true,
            isRemote: false,
            isCurrent: isCurrent,
            trackingStatus: trackingStatus,
            lastCommitDate: lastCommitDate
        )
    }

    private func makeRemoteBranch(
        name: String,
        remoteName: String? = "origin",
        lastCommitDate: Date? = nil
    ) -> BranchInfo {
        BranchInfo(
            name: name,
            isLocal: false,
            isRemote: true,
            isCurrent: false,
            trackingStatus: .noRemote,
            lastCommitDate: lastCommitDate,
            remoteName: remoteName
        )
    }

    private func makeSnapshot(
        cleanupUnits: [GitCleanupUnit] = [],
        worktrees: [GitWorktreeCleanupInfo] = [],
        branches: [GitBranchCleanupInfo] = []
    ) -> GitWorktreeSnapshot {
        GitWorktreeSnapshot(
            repositoryPath: "/tmp/test-repo",
            defaultBranchName: "main",
            defaultBranchRef: "refs/heads/main",
            analysisDescription: "test snapshot",
            worktrees: worktrees,
            branches: branches,
            repositoryIdentity: "test-repo",
            cleanupUnits: cleanupUnits
        )
    }

    private func makeCleanupUnit(
        branchName: String,
        branchStatus: GitBranchCleanupStatus = .mergedIntoDefault,
        worktreeInfo: GitWorktreeCleanupInfo? = nil,
        mode: GitCleanupUnitMode = .safe
    ) -> GitCleanupUnit {
        let branchInfo = GitBranchCleanupInfo(
            reference: GitBranchReference(name: branchName, headHash: "hash123", isRemote: false),
            status: branchStatus,
            worktreePath: nil
        )
        return GitCleanupUnit(
            repositoryIdentity: "test-repo",
            branch: branchInfo,
            worktree: worktreeInfo,
            mode: mode
        )
    }

    private func makeWorktreeInfo(
        branchName: String,
        path: String,
        status: GitWorktreeCleanupStatus
    ) -> GitWorktreeCleanupInfo {
        let worktree = GitWorktreeInfo(
            path: path,
            headHash: "hash123",
            branchName: branchName
        )
        return GitWorktreeCleanupInfo(
            worktree: worktree,
            status: status
        )
    }

    // MARK: - 1. BranchFilter titles and cases

    func testBranchFilterTitles() {
        XCTAssertEqual(BranchFilter.allCases, [.all, .mergeable, .dirty, .stale])
        XCTAssertEqual(BranchFilter.all.title, "All")
        XCTAssertEqual(BranchFilter.mergeable.title, "Mergeable")
        XCTAssertEqual(BranchFilter.dirty.title, "Dirty")
        XCTAssertEqual(BranchFilter.stale.title, "Stale")

        // displayName mirrors title
        for filter in BranchFilter.allCases {
            XCTAssertEqual(filter.displayName, filter.title)
        }
    }

    // MARK: - 2. Current branch resolution

    func testResolveCurrentBranch() {
        let current = makeLocalBranch(name: "main", isCurrent: true)
        let other = makeLocalBranch(name: "feature", isCurrent: false)

        let model = BranchListResolver.resolve(
            branches: [other, current],
            now: fixedNow
        )

        XCTAssertEqual(model.current?.name, "main")
        XCTAssertEqual(model.current?.isCurrent, true)
    }

    func testResolveCurrentBranchNilWhenDetached() {
        let branch1 = makeLocalBranch(name: "feature-1", isCurrent: false)
        let branch2 = makeLocalBranch(name: "feature-2", isCurrent: false)

        let model = BranchListResolver.resolve(
            branches: [branch1, branch2],
            now: fixedNow
        )

        XCTAssertNil(model.current)
    }

    // MARK: - 3. Stale 10-day boundary tests

    func testStaleTenDayBoundary() {
        let daySeconds: TimeInterval = 86400

        // 9 days ago -> not stale
        let nineDaysAgo = fixedNow.addingTimeInterval(-9 * daySeconds)
        let branch9d = makeLocalBranch(name: "b-9d", lastCommitDate: nineDaysAgo)
        XCTAssertFalse(BranchListResolver.isStale(branch: branch9d, now: fixedNow))

        // 10 days ago (exact boundary) -> not stale (must be older than 10 days)
        let tenDaysAgo = fixedNow.addingTimeInterval(-10 * daySeconds)
        let branch10d = makeLocalBranch(name: "b-10d", lastCommitDate: tenDaysAgo)
        XCTAssertFalse(BranchListResolver.isStale(branch: branch10d, now: fixedNow))

        // 11 days ago -> stale
        let elevenDaysAgo = fixedNow.addingTimeInterval(-11 * daySeconds)
        let branch11d = makeLocalBranch(name: "b-11d", lastCommitDate: elevenDaysAgo)
        XCTAssertTrue(BranchListResolver.isStale(branch: branch11d, now: fixedNow))

        // Current branch with 30 days old commit -> NEVER stale
        let thirtyDaysAgo = fixedNow.addingTimeInterval(-30 * daySeconds)
        let currentOld = makeLocalBranch(name: "main", isCurrent: true, lastCommitDate: thirtyDaysAgo)
        XCTAssertFalse(BranchListResolver.isStale(branch: currentOld, now: fixedNow))

        // Remote branch with 30 days old commit -> NEVER stale
        let remoteOld = makeRemoteBranch(name: "origin/old-feature", lastCommitDate: thirtyDaysAgo)
        XCTAssertFalse(BranchListResolver.isStale(branch: remoteOld, now: fixedNow))

        // Branch with nil date -> not stale
        let noDate = makeLocalBranch(name: "no-date", lastCommitDate: nil)
        XCTAssertFalse(BranchListResolver.isStale(branch: noDate, now: fixedNow))

        // Resolver filter with .stale includes only branch11d
        let model = BranchListResolver.resolve(
            branches: [currentOld, branch9d, branch10d, branch11d, remoteOld, noDate],
            filter: .stale,
            now: fixedNow
        )

        XCTAssertEqual(model.local.map(\.branch.name), ["b-11d"])
        XCTAssertEqual(model.filterCounts[.stale], 1)
    }

    // MARK: - 4. Mergeable filter tests

    func testFilterMergeable() {
        let mergedBranch = makeLocalBranch(name: "feature-merged")
        let unmergedBranch = makeLocalBranch(name: "feature-wip")
        let protectedBranch = makeLocalBranch(name: "protected-branch")

        let actionableUnit = makeCleanupUnit(branchName: "feature-merged", branchStatus: .mergedIntoDefault)
        let protectedUnit = makeCleanupUnit(branchName: "protected-branch", branchStatus: .protected)

        let snapshot = makeSnapshot(cleanupUnits: [actionableUnit, protectedUnit])

        let model = BranchListResolver.resolve(
            branches: [mergedBranch, unmergedBranch, protectedBranch],
            snapshot: snapshot,
            filter: .mergeable,
            now: fixedNow
        )

        XCTAssertEqual(model.local.map(\.branch.name), ["feature-merged"])
        XCTAssertEqual(model.local.first?.isMerged, true)
        XCTAssertEqual(model.filterCounts[.mergeable], 1)
    }

    // MARK: - 5. Dirty filter tests

    func testFilterDirty() {
        let dirtyBranch = makeLocalBranch(name: "feature-dirty")
        let cleanBranch = makeLocalBranch(name: "feature-clean")
        let noWorktreeBranch = makeLocalBranch(name: "feature-nowt")

        let dirtyWorktree = makeWorktreeInfo(branchName: "feature-dirty", path: "/tmp/wt-dirty", status: .dirty)
        let cleanWorktree = makeWorktreeInfo(branchName: "feature-clean", path: "/tmp/wt-clean", status: .eligible)

        let snapshot = makeSnapshot(worktrees: [dirtyWorktree, cleanWorktree])

        let model = BranchListResolver.resolve(
            branches: [dirtyBranch, cleanBranch, noWorktreeBranch],
            snapshot: snapshot,
            filter: .dirty,
            now: fixedNow
        )

        XCTAssertEqual(model.local.map(\.branch.name), ["feature-dirty"])
        XCTAssertEqual(model.local.first?.isDirty, true)
        XCTAssertEqual(model.local.first?.hasWorktree, true)
        XCTAssertEqual(model.filterCounts[.dirty], 1)
    }

    // MARK: - 6. Query filtering and ordering

    func testQueryFilteringAndOrdering() {
        let current = makeLocalBranch(name: "z-main", isCurrent: true)
        let featAlpha = makeLocalBranch(name: "alpha-feature")
        let featBeta = makeLocalBranch(name: "beta-feature")
        let bugfix = makeLocalBranch(name: "bugfix-123")

        let remAlpha = makeRemoteBranch(name: "alpha-feature")
        let remBeta = makeRemoteBranch(name: "beta-feature")
        let remOther = makeRemoteBranch(name: "other-remote")

        // Test ordering under .all filter with empty query
        // Semantics: current first, then localizedStandardCompare
        let modelAll = BranchListResolver.resolve(
            branches: [featBeta, current, featAlpha, bugfix],
            filter: .all,
            now: fixedNow
        )

        XCTAssertEqual(modelAll.local.map(\.branch.name), ["z-main", "alpha-feature", "beta-feature", "bugfix-123"])

        // Query filtering: "feature" matches alpha-feature and beta-feature
        let modelFiltered = BranchListResolver.resolve(
            branches: [current, featAlpha, featBeta, bugfix, remAlpha, remBeta, remOther],
            query: "feature",
            filter: .all,
            now: fixedNow
        )

        XCTAssertEqual(modelFiltered.local.map(\.branch.name), ["alpha-feature", "beta-feature"])
        XCTAssertEqual(modelFiltered.filterCounts[.all], 2)
    }

    // MARK: - 7. Merged collapse split

    func testMergedCollapseWithThreeOrFewerMergedRows() {
        // When <= 3 merged rows, all rows stay visible and collapsedMerged is empty
        let current = makeLocalBranch(name: "main", isCurrent: true)
        let m1 = makeLocalBranch(name: "m1")
        let m2 = makeLocalBranch(name: "m2")
        let nonMerged = makeLocalBranch(name: "wip")

        let u1 = makeCleanupUnit(branchName: "m1", branchStatus: .mergedIntoDefault)
        let u2 = makeCleanupUnit(branchName: "m2", branchStatus: .mergedIntoDefault)
        let snapshot = makeSnapshot(cleanupUnits: [u1, u2])

        let model = BranchListResolver.resolve(
            branches: [current, m1, m2, nonMerged],
            snapshot: snapshot,
            filter: .all,
            now: fixedNow
        )

        XCTAssertEqual(model.visible.map(\.branch.name), ["main", "m1", "m2", "wip"])
        XCTAssertTrue(model.collapsedMerged.isEmpty)
        XCTAssertFalse(model.hasCollapsedMerged)
    }

    func testMergedCollapseWithMoreThanThreeMergedRows() {
        // When > 3 merged rows, first 3 stay visible, 4+ go to collapsedMerged, non-merged always visible
        let current = makeLocalBranch(name: "main", isCurrent: true)
        let m1 = makeLocalBranch(name: "m1")
        let m2 = makeLocalBranch(name: "m2")
        let m3 = makeLocalBranch(name: "m3")
        let m4 = makeLocalBranch(name: "m4")
        let m5 = makeLocalBranch(name: "m5")
        let nonMerged = makeLocalBranch(name: "wip")

        let units = [m1, m2, m3, m4, m5].map {
            makeCleanupUnit(branchName: $0.name, branchStatus: .mergedIntoDefault)
        }
        let snapshot = makeSnapshot(cleanupUnits: units)

        let model = BranchListResolver.resolve(
            branches: [current, m1, m2, m3, m4, m5, nonMerged],
            snapshot: snapshot,
            filter: .all,
            now: fixedNow
        )

        // Sorted order: main (current), m1, m2, m3, m4, m5, wip
        // Merged encountered in order: m1 (#1), m2 (#2), m3 (#3), m4 (#4 -> collapsed), m5 (#5 -> collapsed)
        // Non-merged: main, wip -> always visible
        XCTAssertEqual(model.visible.map(\.branch.name), ["main", "m1", "m2", "m3", "wip"])
        XCTAssertEqual(model.collapsedMerged.map(\.branch.name), ["m4", "m5"])
        XCTAssertTrue(model.hasCollapsedMerged)
        XCTAssertEqual(model.visible.count + model.collapsedMerged.count, model.local.count)
    }

    // MARK: - 8. Remote branch grouping

    func testRemoteBranchGrouping() {
        let r1 = makeRemoteBranch(name: "dependabot/npm_and_yarn/lodash-4.17.21")
        let r2 = makeRemoteBranch(name: "dependabot/npm_and_yarn/axios-1.6.0")
        let r3 = makeRemoteBranch(name: "feature/auth")
        let r4 = makeRemoteBranch(name: "feature/profile")
        let singleton = makeRemoteBranch(name: "bugfix/solo-fix")
        let root = makeRemoteBranch(name: "main")

        let model = BranchListResolver.resolve(
            branches: [r1, r2, r3, r4, singleton, root],
            filter: .all,
            now: fixedNow
        )

        // Groups: "dependabot/npm_and_yarn" and "feature"
        XCTAssertEqual(model.remoteGroups.count, 2)

        let depGroup = model.remoteGroups.first { $0.name == "dependabot/npm_and_yarn" }
        XCTAssertNotNil(depGroup)
        XCTAssertEqual(depGroup?.branches.count, 2)
        XCTAssertEqual(
            depGroup?.branches.map(\.name),
            ["dependabot/npm_and_yarn/axios-1.6.0", "dependabot/npm_and_yarn/lodash-4.17.21"]
        )

        let featGroup = model.remoteGroups.first { $0.name == "feature" }
        XCTAssertNotNil(featGroup)
        XCTAssertEqual(featGroup?.branches.count, 2)
        XCTAssertEqual(featGroup?.branches.map(\.name), ["feature/auth", "feature/profile"])

        // Ungrouped: singleton ("bugfix/solo-fix") and root ("main")
        XCTAssertEqual(model.ungroupedRemote.map(\.name), ["bugfix/solo-fix", "main"])
    }

    func testRemoteGroupsEmptyUnderNonAllFilter() {
        let r1 = makeRemoteBranch(name: "feature/a")
        let r2 = makeRemoteBranch(name: "feature/b")

        let model = BranchListResolver.resolve(
            branches: [r1, r2],
            filter: .mergeable,
            now: fixedNow
        )

        XCTAssertTrue(model.remoteGroups.isEmpty)
        XCTAssertTrue(model.ungroupedRemote.isEmpty)
    }

    // MARK: - 9. Ready and Blocked counts

    func testReadyAndBlockedCounts() {
        let ready1 = makeCleanupUnit(branchName: "b1", branchStatus: .mergedIntoDefault)
        let ready2 = makeCleanupUnit(branchName: "b2", branchStatus: .mergedIntoDefault)
        let blockedProtected = makeCleanupUnit(branchName: "b-prot", branchStatus: .protected)

        let snapshot = makeSnapshot(cleanupUnits: [ready1, ready2, blockedProtected])

        let model = BranchListResolver.resolve(
            branches: [],
            snapshot: snapshot,
            now: fixedNow
        )

        XCTAssertEqual(model.readyCount, 2)
        XCTAssertEqual(model.blockedCount, 1)

        // Nil snapshot
        let nilModel = BranchListResolver.resolve(branches: [], snapshot: nil, now: fixedNow)
        XCTAssertEqual(nilModel.readyCount, 0)
        XCTAssertEqual(nilModel.blockedCount, 0)
    }

    // MARK: - 10. Filter counts per BranchFilter for chip badges

    func testFilterCounts() {
        let current = makeLocalBranch(name: "main", isCurrent: true)
        let merged = makeLocalBranch(name: "merged-branch")
        let dirty = makeLocalBranch(name: "dirty-branch")
        let stale = makeLocalBranch(
            name: "stale-branch",
            lastCommitDate: fixedNow.addingTimeInterval(-15 * 86400)
        )

        let mergedUnit = makeCleanupUnit(branchName: "merged-branch", branchStatus: .mergedIntoDefault)
        let dirtyWorktree = makeWorktreeInfo(branchName: "dirty-branch", path: "/tmp/wt-dirty", status: .dirty)
        let snapshot = makeSnapshot(cleanupUnits: [mergedUnit], worktrees: [dirtyWorktree])

        let model = BranchListResolver.resolve(
            branches: [current, merged, dirty, stale],
            snapshot: snapshot,
            filter: .all,
            now: fixedNow
        )

        XCTAssertEqual(model.count(for: .all), 4)
        XCTAssertEqual(model.count(for: .mergeable), 1)
        XCTAssertEqual(model.count(for: .dirty), 1)
        XCTAssertEqual(model.count(for: .stale), 1)
    }
}
