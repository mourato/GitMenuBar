import Foundation

enum MainMenuRoute: Equatable {
    case main
    case createRepo(path: String)
    case historyDetail(commitID: String)
}

enum RefreshState: Equatable {
    case idle
    case refreshing
    case failed(message: String)

    var isRefreshing: Bool {
        if case .refreshing = self {
            return true
        }

        return false
    }
}

enum RemoteExistenceState: Equatable {
    case unknown
    case checking
    case exists
    case missing
}

@MainActor
final class MainMenuPresentationModel: ObservableObject {
    @Published private(set) var route: MainMenuRoute = .main
    @Published private(set) var refreshState: RefreshState = .idle
    @Published private(set) var focusCommitFieldToken = 0
    @Published private(set) var showCommandPaletteToken = 0
    @Published private(set) var createRepoSuggestionPath: String?

    func prepareForPresentation(route: MainMenuRoute, requestCommitFocus: Bool) {
        self.route = route

        if case .createRepo = route {
            createRepoSuggestionPath = nil
        }

        if requestCommitFocus, route == .main {
            self.requestCommitFocus()
        }
    }

    func showMain(requestCommitFocus: Bool = false) {
        route = .main

        if requestCommitFocus {
            self.requestCommitFocus()
        }
    }

    func showCreateRepo(path: String) {
        route = .createRepo(path: path)
        createRepoSuggestionPath = nil
    }

    func showHistoryDetail(commitID: String) {
        route = .historyDetail(commitID: commitID)
    }

    func startRefresh() {
        refreshState = .refreshing
    }

    func finishRefresh() {
        refreshState = .idle
    }

    func failRefresh(message: String) {
        refreshState = .failed(message: message)
    }

    func clearRefreshError() {
        if case .failed = refreshState {
            refreshState = .idle
        }
    }

    func suggestCreateRepo(path: String) {
        createRepoSuggestionPath = path
    }

    func clearCreateRepoSuggestion() {
        createRepoSuggestionPath = nil
    }

    func requestCommitFocus() {
        focusCommitFieldToken += 1
    }

    func requestCommandPalettePresentation() {
        showCommandPaletteToken += 1
    }
}
