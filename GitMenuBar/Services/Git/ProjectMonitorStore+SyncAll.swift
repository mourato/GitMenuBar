import Foundation

struct SyncAllResult: Sendable {
    var updatedNames: [String]
    var skippedNames: [String]
    var failedNames: [String]

    var didAnything: Bool {
        !updatedNames.isEmpty || !skippedNames.isEmpty || !failedNames.isEmpty
    }
}

extension ProjectMonitorStore {
    static func isSafeToFastForward(_ snapshot: ProjectStatusSnapshot) -> Bool {
        snapshot.lastErrorDescription == nil
            && !snapshot.isDetachedHead
            && !snapshot.branchName.isEmpty
            && snapshot.hasUpstream
            && snapshot.behindCount > 0
            && snapshot.aheadCount == 0
            && !snapshot.hasWorkingTreeChanges
    }

    func syncAllSafe() async -> SyncAllResult {
        let projects = monitoredProjects
        let runner = runner
        #if DEBUG
            let fetchOperation = fetchOperation
            let refreshOperation = refreshOperation
            let syncPullOperation = syncPullOperation
        #endif
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let reader = ProjectStatusReader(runner: runner)
                var updated: [String] = []
                var skipped: [String] = []
                var failed: [String] = []
                var fresh: [ProjectStatusSnapshot] = []
                for project in projects {
                    let snapshot: ProjectStatusSnapshot
                    #if DEBUG
                        if let fetchOperation {
                            snapshot = fetchOperation(project, runner)
                        } else {
                            _ = runner.runGitCommand(in: project.path, args: ["fetch"])
                            snapshot = reader.read(
                                project: project,
                                includeLineDiff: false,
                                mode: .remote
                            )
                        }
                    #else
                        _ = runner.runGitCommand(in: project.path, args: ["fetch"])
                        snapshot = reader.read(
                            project: project,
                            includeLineDiff: false,
                            mode: .remote
                        )
                    #endif
                    fresh.append(snapshot)
                    guard Self.isSafeToFastForward(snapshot) else {
                        if snapshot.behindCount > 0 {
                            skipped.append(project.name)
                        }
                        continue
                    }
                    let pull: (output: String, failure: Bool)
                    #if DEBUG
                        if let syncPullOperation {
                            pull = syncPullOperation(project, runner)
                        } else {
                            pull = runner.runGitCommand(in: project.path, args: ["pull", "--ff-only"])
                        }
                    #else
                        pull = runner.runGitCommand(in: project.path, args: ["pull", "--ff-only"])
                    #endif
                    guard !pull.failure else {
                        failed.append(project.name)
                        continue
                    }
                    #if DEBUG
                        if let refreshOperation {
                            fresh[fresh.count - 1] = refreshOperation(project, runner)
                        } else {
                            fresh[fresh.count - 1] = reader.read(
                                project: project,
                                includeLineDiff: false,
                                mode: .remote
                            )
                        }
                    #else
                        fresh[fresh.count - 1] = reader.read(
                            project: project,
                            includeLineDiff: false,
                            mode: .remote
                        )
                    #endif
                    updated.append(project.name)
                }
                let result = SyncAllResult(updatedNames: updated, skippedNames: skipped, failedNames: failed)
                let published = fresh
                Task { @MainActor [weak self] in
                    self?.publishSnapshots(published)
                    continuation.resume(returning: result)
                }
            }
        }
    }
}
