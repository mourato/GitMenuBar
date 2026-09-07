import Foundation

enum MainMenuRoute: Equatable {
    case main
    case createRepo(path: String)
    case projectCleanup
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
    @Published private(set) var isFastLoading = false
    @Published private(set) var isDetailLoading = false
    @Published private(set) var focusCommitFieldToken = 0
    @Published private(set) var showCommandPaletteToken = 0
    @Published private(set) var showRepositoryOptionsToken = 0
    @Published private(set) var createRepoSuggestionPath: String?
    @Published private(set) var quotaInfoSnapshot: UsageQuotaSnapshot?

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

    func showProjectCleanup() {
        route = .projectCleanup
    }

    @discardableResult
    func startRefresh() -> Int {
        refreshGeneration += 1
        isFastLoading = true
        isDetailLoading = true
        refreshState = .refreshing
        return refreshGeneration
    }

    func markFastPhaseReady(generation: Int? = nil) {
        guard generation.map({ $0 == refreshGeneration }) ?? true else { return }
        isFastLoading = false
    }

    func finishRefresh(generation: Int? = nil) {
        guard generation.map({ $0 == refreshGeneration }) ?? true else { return }
        isFastLoading = false
        isDetailLoading = false
        refreshState = .idle
    }

    func failRefresh(message: String) {
        isFastLoading = false
        isDetailLoading = false
        refreshState = .failed(message: message)
    }

    func clearRefreshError() {
        if case .failed = refreshState {
            refreshState = .idle
        }
    }

    private var refreshGeneration = 0

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

    func requestRepositoryOptionsPresentation() {
        showRepositoryOptionsToken += 1
    }

    func requestQuotaInfo(snapshot: UsageQuotaSnapshot) {
        quotaInfoSnapshot = snapshot
    }

    func clearQuotaInfo() {
        quotaInfoSnapshot = nil
    }
}
