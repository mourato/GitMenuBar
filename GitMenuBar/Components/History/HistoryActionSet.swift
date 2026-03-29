import Foundation

struct HistoryActionSet: Equatable {
    let commitURL: URL?
    let isCurrentCommit: Bool
    let isFutureCommit: Bool
    let canOpenOnGitHub: Bool
    let canEditMessage: Bool
    let canGenerateMessage: Bool
    let canRestore: Bool

    init(commit: Commit, currentHash: String, remoteUrl: String, isCommitInFuture: Bool) {
        if let reference = GitHubRemoteURLParser.parse(remoteUrl) {
            commitURL = URL(string: "https://github.com/\(reference.owner)/\(reference.repository)/commit/\(commit.id)")
        } else {
            commitURL = nil
        }

        isCurrentCommit = commit.id == currentHash
        isFutureCommit = isCommitInFuture
        canOpenOnGitHub = commitURL != nil
        canEditMessage = !commit.isMergeCommit
        canGenerateMessage = !commit.isMergeCommit
        canRestore = commit.id != currentHash
    }
}
