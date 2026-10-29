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
        managementUnits: [GitCleanupUnit]? = nil,
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
            cleanupUnits: cleanupUnits,
            managementUnits: managementUnits ?? cleanupUnits
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
            worktreePath: worktreeInfo?.worktree.path
        )
        return GitCleanupUnit(repositoryIdentity: "test-repo", branch: branchInfo, worktree: worktreeInfo, mode: mode)
    }

    private func makeWorktreeInfo(
        branchName: String,
        path: String,
        status: GitWorktreeCleanupStatus
    ) -> GitWorktreeCleanupInfo {
        GitWorktreeCleanupInfo(
            worktree: GitWorktreeInfo(path: path, headHash: "hash123", branchName: branchName),
            status: status
        )
    }

    // MARK: - Tests

    func testCurrentBranchLeadsLocalRows() {
        let current = makeLocalBranch(name: "main", isCurrent: true)
        let other = makeLocalBranch(name: "feature", isCurrent: false)
        let model = BranchListResolver.resolve(branches: [other, current], now: fixedNow)
        XCTAssertEqual(model.local.map(\.branch.name), ["main", "feature"])
    }

    func testCurrentBranchIsOmittedWhenQueryDoesNotMatchIt() {
        let current = makeLocalBranch(name: "main", isCurrent: true)
        let other = makeLocalBranch(name: "feature", isCurrent: false)
        let model = BranchListResolver.resolve(branches: [other, current], query: "feat", now: fixedNow)
        XCTAssertEqual(model.local.map(\.branch.name), ["feature"])
    }

    func testStaleTenDayBoundary() {
        let daySeconds: TimeInterval = 86400
        let tenDaysSeconds: TimeInterval = 10 * daySeconds

        // 10d - 1s -> not stale
        let tenDaysMinus1s = fixedNow.addingTimeInterval(-(tenDaysSeconds - 1))
        let branch10dMinus1s = makeLocalBranch(name: "b-10d-minus-1s", lastCommitDate: tenDaysMinus1s)
        XCTAssertFalse(BranchListResolver.isStale(branch: branch10dMinus1s, now: fixedNow))

        // 10d exact boundary -> not stale
        let tenDaysExact = fixedNow.addingTimeInterval(-tenDaysSeconds)
        let branch10d = makeLocalBranch(name: "b-10d", lastCommitDate: tenDaysExact)
        XCTAssertFalse(BranchListResolver.isStale(branch: branch10d, now: fixedNow))

        // 10d + 1s -> stale
        let tenDaysPlus1s = fixedNow.addingTimeInterval(-(tenDaysSeconds + 1))
        let branch10dPlus1s = makeLocalBranch(name: "b-10d-plus-1s", lastCommitDate: tenDaysPlus1s)
        XCTAssertTrue(BranchListResolver.isStale(branch: branch10dPlus1s, now: fixedNow))

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

        let model = BranchListResolver.resolve(
            branches: [currentOld, branch10dMinus1s, branch10d, branch10dPlus1s, remoteOld, noDate],
            filter: .stale,
            now: fixedNow
        )
        XCTAssertEqual(model.local.map(\.branch.name), ["b-10d-plus-1s"])
        XCTAssertEqual(model.filterCounts[.stale], 1)
    }

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

    func testPrecedenceDirtyWorktreeWinsOverMerged() {
        let branch = makeLocalBranch(name: "feature-merged-dirty")
        let dirtyWorktree = makeWorktreeInfo(branchName: "feature-merged-dirty", path: "/tmp/wt-dirty", status: .dirty)
        let mergedUnit = makeCleanupUnit(
            branchName: "feature-merged-dirty",
            branchStatus: .mergedIntoDefault,
            worktreeInfo: dirtyWorktree
        )
        let snapshot = makeSnapshot(cleanupUnits: [mergedUnit], worktrees: [dirtyWorktree])

        let allModel = BranchListResolver.resolve(branches: [branch], snapshot: snapshot, filter: .all, now: fixedNow)
        XCTAssertEqual(allModel.local.count, 1)
        let row = allModel.local[0]
        XCTAssertEqual(row.cleanupStatus, .dirty)
        XCTAssertTrue(row.isDirty)
        XCTAssertFalse(row.isMerged)
        XCTAssertEqual(allModel.count(for: .dirty), 1)
        XCTAssertEqual(allModel.count(for: .mergeable), 0)

        let mergeableModel = BranchListResolver.resolve(branches: [branch], snapshot: snapshot, filter: .mergeable, now: fixedNow)
        XCTAssertTrue(mergeableModel.local.isEmpty)

        let dirtyModel = BranchListResolver.resolve(branches: [branch], snapshot: snapshot, filter: .dirty, now: fixedNow)
        XCTAssertEqual(dirtyModel.local.map(\.branch.name), ["feature-merged-dirty"])
    }

    func testFallbackFromBranchInfoStatusNeverYieldsMerged() {
        let branch = makeLocalBranch(name: "feature-unconfirmed-merge")
        let branchInfo = GitBranchCleanupInfo(
            reference: GitBranchReference(name: "feature-unconfirmed-merge", headHash: "h1", isRemote: false),
            status: .mergedIntoDefault,
            worktreePath: nil
        )
        let snapshot = makeSnapshot(cleanupUnits: [], managementUnits: [], branches: [branchInfo])

        let model = BranchListResolver.resolve(branches: [branch], snapshot: snapshot, filter: .all, now: fixedNow)
        XCTAssertEqual(model.local.count, 1)
        XCTAssertNil(model.local[0].cleanupStatus)
        XCTAssertFalse(model.local[0].isMerged)
        XCTAssertEqual(model.count(for: .mergeable), 0)
    }

    func testQueryFilteringAndOrdering() {
        let current = makeLocalBranch(name: "z-main", isCurrent: true)
        let featAlpha = makeLocalBranch(name: "alpha-feature")
        let featBeta = makeLocalBranch(name: "beta-feature")
        let bugfix = makeLocalBranch(name: "bugfix-123")
        let remAlpha = makeRemoteBranch(name: "alpha-feature")
        let remBeta = makeRemoteBranch(name: "beta-feature")

        let modelAll = BranchListResolver.resolve(
            branches: [featBeta, current, featAlpha, bugfix],
            filter: .all,
            now: fixedNow
        )
        XCTAssertEqual(modelAll.local.map(\.branch.name), ["z-main", "alpha-feature", "beta-feature", "bugfix-123"])

        let modelFiltered = BranchListResolver.resolve(
            branches: [current, featAlpha, featBeta, bugfix, remAlpha, remBeta],
            query: "feature",
            filter: .all,
            now: fixedNow
        )
        XCTAssertEqual(modelFiltered.local.map(\.branch.name), ["alpha-feature", "beta-feature"])
        XCTAssertEqual(modelFiltered.filterCounts[.all], 2)
    }

    func testMergedCollapseWithThreeOrFewerMergedRows() {
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
        let current = makeLocalBranch(name: "main", isCurrent: true)
        let m1 = makeLocalBranch(name: "m1")
        let m2 = makeLocalBranch(name: "m2")
        let m3 = makeLocalBranch(name: "m3")
        let m4 = makeLocalBranch(name: "m4")
        let m5 = makeLocalBranch(name: "m5")
        let nonMerged = makeLocalBranch(name: "wip")
        let units = [m1, m2, m3, m4, m5].map { makeCleanupUnit(branchName: $0.name, branchStatus: .mergedIntoDefault) }
        let snapshot = makeSnapshot(cleanupUnits: units)

        let model = BranchListResolver.resolve(
            branches: [current, m1, m2, m3, m4, m5, nonMerged],
            snapshot: snapshot,
            filter: .all,
            now: fixedNow
        )
        XCTAssertEqual(model.visible.map(\.branch.name), ["main", "m1", "m2", "m3", "wip"])
        XCTAssertEqual(model.collapsedMerged.map(\.branch.name), ["m4", "m5"])
        XCTAssertTrue(model.hasCollapsedMerged)
        XCTAssertEqual(model.visible.count + model.collapsedMerged.count, model.local.count)
    }

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
        XCTAssertEqual(model.remoteGroups.count, 2)
        let depGroup = model.remoteGroups.first { $0.name == "dependabot/npm_and_yarn" }
        XCTAssertEqual(depGroup?.branches.map(\.name), ["dependabot/npm_and_yarn/axios-1.6.0", "dependabot/npm_and_yarn/lodash-4.17.21"])

        let featGroup = model.remoteGroups.first { $0.name == "feature" }
        XCTAssertEqual(featGroup?.branches.map(\.name), ["feature/auth", "feature/profile"])
        XCTAssertEqual(model.ungroupedRemote.map(\.name), ["bugfix/solo-fix", "main"])
    }

    func testRemoteGroupsEmptyUnderNonAllFilter() {
        let r1 = makeRemoteBranch(name: "feature/a")
        let r2 = makeRemoteBranch(name: "feature/b")
        let model = BranchListResolver.resolve(branches: [r1, r2], filter: .mergeable, now: fixedNow)
        XCTAssertTrue(model.remoteGroups.isEmpty)
        XCTAssertTrue(model.ungroupedRemote.isEmpty)
    }

    func testReadyAndBlockedCountsDifferBetweenManagementUnitsAndCleanupUnits() {
        // Disparity: cleanupUnits has only 1 unit (ready: 1, blocked: 0)
        let cleanupOnlyUnit = makeCleanupUnit(branchName: "cleanup-only", branchStatus: .mergedIntoDefault)

        // managementUnits has 5 units:
        let readyAlpha = makeCleanupUnit(branchName: "ready-alpha", branchStatus: .mergedIntoDefault)
        let cleanWt = makeWorktreeInfo(branchName: "ready-beta", path: "/tmp/wt-clean", status: .eligible)
        let readyBeta = makeCleanupUnit(branchName: "ready-beta", branchStatus: .mergedIntoDefault, worktreeInfo: cleanWt)
        let blockedProtected = makeCleanupUnit(branchName: "blocked-protected", branchStatus: .protected)
        let dirtyWt = makeWorktreeInfo(branchName: "blocked-dirty", path: "/tmp/wt-dirty", status: .dirty)
        let blockedDirty = makeCleanupUnit(branchName: "blocked-dirty", branchStatus: .mergedIntoDefault, worktreeInfo: dirtyWt)
        let targetWt = makeWorktreeInfo(branchName: "other-branch", path: "/tmp/special-project-path", status: .eligible)
        let readyPath = makeCleanupUnit(branchName: "other-branch", branchStatus: .mergedIntoDefault, worktreeInfo: targetWt)

        let snapshot = makeSnapshot(
            cleanupUnits: [cleanupOnlyUnit],
            managementUnits: [readyAlpha, readyBeta, blockedProtected, blockedDirty, readyPath]
        )
        XCTAssertEqual(snapshot.cleanupUnits.count, 1)
        XCTAssertEqual(snapshot.managementUnits.count, 5)

        // 1. Without query: derived from managementUnits (ready: 3, blocked: 2)
        let modelNoQuery = BranchListResolver.resolve(branches: [], snapshot: snapshot, now: fixedNow)
        XCTAssertEqual(modelNoQuery.readyCount, 3)
        XCTAssertEqual(modelNoQuery.blockedCount, 2)
        let snapshotCounts = snapshot.cleanupCounts()
        XCTAssertEqual(snapshotCounts.ready, 3)
        XCTAssertEqual(snapshotCounts.blocked, 2)

        // 2. Query with surrounding spaces matching ready units: "   ready   " -> 2 ready, 0 blocked
        let modelReady = BranchListResolver.resolve(branches: [], snapshot: snapshot, query: "   ready   ", now: fixedNow)
        XCTAssertEqual(modelReady.readyCount, 2)
        XCTAssertEqual(modelReady.blockedCount, 0)
        XCTAssertEqual(snapshot.cleanupCounts(matching: "   ready   ").ready, 2)
        XCTAssertEqual(snapshot.cleanupCounts(matching: "   ready   ").blocked, 0)

        // 3. Query with surrounding spaces matching blocked units: "   blocked   " -> 0 ready, 2 blocked
        let modelBlocked = BranchListResolver.resolve(branches: [], snapshot: snapshot, query: "   blocked   ", now: fixedNow)
        XCTAssertEqual(modelBlocked.readyCount, 0)
        XCTAssertEqual(modelBlocked.blockedCount, 2)
        XCTAssertEqual(snapshot.cleanupCounts(matching: "   blocked   ").ready, 0)
        XCTAssertEqual(snapshot.cleanupCounts(matching: "   blocked   ").blocked, 2)

        // 4. Query matching worktree path with spaces: "   special-project-path   " -> 1 ready, 0 blocked
        let modelPath = BranchListResolver.resolve(branches: [], snapshot: snapshot, query: "   special-project-path   ", now: fixedNow)
        XCTAssertEqual(modelPath.readyCount, 1)
        XCTAssertEqual(modelPath.blockedCount, 0)
        XCTAssertEqual(snapshot.cleanupCounts(matching: "   special-project-path   ").ready, 1)
        XCTAssertEqual(snapshot.cleanupCounts(matching: "   special-project-path   ").blocked, 0)

        // 5. Query matching nothing with surrounding spaces
        let modelEmpty = BranchListResolver.resolve(branches: [], snapshot: snapshot, query: "   none   ", now: fixedNow)
        XCTAssertEqual(modelEmpty.readyCount, 0)
        XCTAssertEqual(modelEmpty.blockedCount, 0)

        // 6. Nil snapshot gives zero counts
        let nilModel = BranchListResolver.resolve(branches: [], snapshot: nil, now: fixedNow)
        XCTAssertEqual(nilModel.readyCount, 0)
        XCTAssertEqual(nilModel.blockedCount, 0)
    }

    func testFilterCounts() {
        let current = makeLocalBranch(name: "main", isCurrent: true)
        let merged = makeLocalBranch(name: "merged-branch")
        let dirty = makeLocalBranch(name: "dirty-branch")
        let stale = makeLocalBranch(name: "stale-branch", lastCommitDate: fixedNow.addingTimeInterval(-15 * 86400))
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

    func testWorktreeRemovalUnitReachesDetachedWorktreeButNotDirtyOne() {
        let detached = GitWorktreeCleanupInfo(
            worktree: GitWorktreeInfo(path: "/tmp/detached", headHash: "hash123", branchName: nil),
            status: .detached
        )
        let dirty = makeWorktreeInfo(branchName: "feature/dirty", path: "/tmp/dirty", status: .dirty)
        let detachedUnit = GitCleanupUnit(
            repositoryIdentity: "test-repo",
            branch: GitBranchCleanupInfo(
                reference: GitBranchReference(name: "detached", headHash: "hash123", isRemote: false),
                status: .notMerged,
                worktreePath: detached.worktree.path
            ),
            worktree: detached,
            mode: .removeWorktree
        )
        let dirtyUnit = makeCleanupUnit(branchName: "feature/dirty", branchStatus: .notMerged, worktreeInfo: dirty)
        let snapshot = makeSnapshot(managementUnits: [detachedUnit, dirtyUnit], worktrees: [detached, dirty])

        let removal = snapshot.worktreeRemovalUnit(for: detached)
        XCTAssertEqual(removal?.mode, .removeWorktree)
        XCTAssertEqual(removal?.worktree, detached)
        XCTAssertNil(snapshot.worktreeRemovalUnit(for: dirty))
    }

    func testCleanupConfirmationDefaultSelectionExcludesUnmergedBranches() {
        let merged = makeCleanupUnit(branchName: "feature/merged", branchStatus: .mergedIntoDefault)
        let unmerged = makeCleanupUnit(branchName: "feature/unmerged", branchStatus: .notMerged)
        let worktreeOnly = makeCleanupUnit(
            branchName: "feature/clean-worktree",
            branchStatus: .notMerged,
            worktreeInfo: makeWorktreeInfo(branchName: "feature/clean-worktree", path: "/tmp/clean", status: .eligible),
            mode: .removeWorktree
        )

        let selected = CleanupConfirmationView.defaultSelectedIDs(for: [merged, unmerged, worktreeOnly])
        XCTAssertTrue(selected.contains(merged.id))
        XCTAssertFalse(selected.contains(unmerged.id))
        XCTAssertTrue(selected.contains(worktreeOnly.id))
    }
}
