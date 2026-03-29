import Foundation

struct RepositoryActionSet: Equatable {
    let currentRepoPath: String
    let remoteUrl: String
    let isGitHubAuthenticated: Bool
    let isPrivate: Bool

    var canRevealInFinder: Bool {
        !currentRepoPath.isEmpty
    }

    var canOpenOnGitHub: Bool {
        GitHubRemoteURLParser.parse(remoteUrl) != nil
    }

    var canShowRepositoryOptions: Bool {
        isGitHubAuthenticated && canOpenOnGitHub
    }

    var visibilityActionTitle: String {
        isPrivate ? "Make Public" : "Make Private"
    }

    var visibilityStatusDescription: String {
        isPrivate ? "This repository is currently private." : "This repository is currently public."
    }

    var visibilityConfirmationTitle: String {
        isPrivate ? "Make Repository Public?" : "Make Repository Private?"
    }

    var visibilityConfirmationMessage: String {
        if isPrivate {
            return "Anyone on the internet will be able to see this repository."
        }

        return "You will choose who can see and commit to this repository."
    }
}
