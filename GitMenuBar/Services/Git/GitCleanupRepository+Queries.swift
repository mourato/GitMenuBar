import Foundation

extension GitCleanupRepository {
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
