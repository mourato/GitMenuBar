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
        commitURL = GitHubRemoteURLParser.commitURL(remoteURL: remoteUrl, sha: commit.id)

        isCurrentCommit = commit.id == currentHash
        isFutureCommit = isCommitInFuture
        canOpenOnGitHub = commitURL != nil
        canEditMessage = !commit.isMergeCommit
        canGenerateMessage = !commit.isMergeCommit
        canRestore = commit.id != currentHash
    }
}
