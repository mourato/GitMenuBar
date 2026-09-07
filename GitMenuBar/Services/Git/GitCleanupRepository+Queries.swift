import Foundation

extension GitCleanupRepository {
    func defaultBranchName(in path: String) -> String? {
        let remotes = execute(path, ["remote"]).output
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        for remote in remotes {
            let result = execute(path, ["symbolic-ref", "refs/remotes/\(remote)/HEAD"])
            let prefix = "refs/remotes/\(remote)/"
            let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.failure, value.hasPrefix(prefix) else { continue }
            let name = String(value.dropFirst(prefix.count))
            if !name.isEmpty {
                return name
            }
        }
        return nil
    }

    func cleanupDetail(for unit: GitCleanupUnit) -> String {
        if let worktree = unit.worktree {
            return "Removing worktree \(worktree.worktree.path)"
        }
        return "Deleting branch \(unit.branch.reference.name)"
    }

    func unitValidationReason(_ unit: GitCleanupUnit, snapshot: GitWorktreeSnapshot) -> String? {
        guard unit.repositoryIdentity == snapshot.repositoryIdentity else {
            return "The cleanup unit belongs to another repository; it was skipped."
        }
        if unit.isForceWorktreeRemoval {
            guard let worktree = unit.worktree,
                  snapshot.worktrees.contains(where: { $0.worktree == worktree.worktree })
            else {
                return "The worktree is not part of the analyzed repository snapshot; it was skipped."
            }
            return nil
        }
        let knownUnits = snapshot.managementUnits + snapshot.cleanupUnits
        guard knownUnits.contains(where: { candidate in
            candidate.branch == unit.branch && candidate.worktree == unit.worktree
        }) else {
            return "The cleanup unit is stale or not part of the analyzed snapshot; it was skipped."
        }
        return nil
    }

    func targetValidationReason(_ target: GitCleanupTarget, snapshot: GitWorktreeSnapshot) -> String? {
        switch target {
        case let .localBranch(info), let .remoteBranch(info):
            snapshot.branches.contains { $0.reference == info.reference }
                ? nil
                : "The branch is not part of the analyzed repository snapshot; it was skipped."
        case let .worktree(info):
            snapshot.worktrees.contains { $0.worktree == info.worktree }
                ? nil
                : "The worktree is not part of the analyzed repository snapshot; it was skipped."
        }
    }

    func branchDeleteArguments(
        for info: GitBranchCleanupInfo,
        defaultBranchRef: String,
        repositoryPath: String,
        allowUnmerged: Bool
    ) -> [String] {
        let reachable = queryMerged(repositoryPath, ref: defaultBranchRef, scope: "refs/heads")?.contains(info.reference.name) == true
        if reachable {
            return ["branch", "--delete", info.reference.name]
        }
        if allowUnmerged {
            return ["branch", "--delete", "--force", info.reference.name]
        }
        if isCherryEquivalent(repositoryPath, upstreamRef: defaultBranchRef, branchRef: info.reference.name) {
            return ["update-ref", "-d", "refs/heads/\(info.reference.name)", info.reference.headHash]
        }
        return ["branch", "--delete", info.reference.name]
    }

    func queryReferences(_ path: String, remote: Bool) -> [GitBranchReference]? {
        let scope = remote ? "refs/remotes" : "refs/heads"
        let result = execute(path, ["for-each-ref", "--format=%(refname:short)%00%(objectname)", scope])
        guard !result.failure else { return nil }
        return result.output.components(separatedBy: .newlines).compactMap { line in
            let parts = line.components(separatedBy: "\u{0}")
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
            if remote {
                let remoteParts = parts[0].split(separator: "/", maxSplits: 1).map(String.init)
                guard remoteParts.count == 2, remoteParts[1] != "HEAD" else { return nil }
                return GitBranchReference(
                    name: remoteParts[1],
                    headHash: parts[1],
                    isRemote: true,
                    remoteName: remoteParts[0]
                )
            }
            return GitBranchReference(name: parts[0], headHash: parts[1], isRemote: false)
        }
    }

    func queryMerged(_ path: String, ref: String, scope: String) -> Set<String>? {
        let result = execute(path, ["for-each-ref", "--merged=\(ref)", "--format=%(refname:short)", scope])
        guard !result.failure else { return nil }
        return Set(result.output.split(whereSeparator: \.isNewline).map(String.init))
    }

    func queryMergedRemote(
        _ path: String,
        defaultBranchName: String,
        references: [GitBranchReference]
    ) -> [String: Set<String>]? {
        let remoteNames = Set(references.compactMap(\.remoteName))
        var result: [String: Set<String>] = [:]
        for remoteName in remoteNames {
            let ref = "refs/remotes/\(remoteName)/\(defaultBranchName)"
            guard !execute(path, ["show-ref", "--verify", "--quiet", ref]).failure,
                  let names = queryMerged(path, ref: ref, scope: "refs/remotes/\(remoteName)") else { continue }
            let merged = Set(names.compactMap { name -> String? in
                let prefix = "\(remoteName)/"
                guard name.hasPrefix(prefix) else { return nil }
                return String(name.dropFirst(prefix.count))
            })
            let remoteReferences = references.filter { $0.remoteName == remoteName }
            result[remoteName] = merged.union(
                cherryPickedBranches(
                    path,
                    upstreamRef: ref,
                    references: remoteReferences
                )
            )
        }
        return result.isEmpty ? nil : result
    }

    func cherryPickedBranches(
        _ path: String,
        upstreamRef: String,
        references: [GitBranchReference]
    ) -> Set<String> {
        Set(references.compactMap { reference in
            isCherryEquivalent(path, upstreamRef: upstreamRef, branchRef: reference.qualifiedName)
                ? reference.name
                : nil
        })
    }

    func isCherryEquivalent(_ path: String, upstreamRef: String, branchRef: String) -> Bool {
        let result = execute(path, ["cherry", upstreamRef, branchRef])
        guard !result.failure else { return false }
        return !result.output.split(whereSeparator: \.isNewline).contains { line in
            line.first == "+"
        }
    }
}
