import Foundation
import Observation

/// Presentation state for the Issues side panel. Network reads go through the
/// injected page fetcher; every response is checked against the request
/// generation, so a late reply for an earlier project or filter never shows.
@MainActor
@Observable
final class IssueListModel {
    typealias PageFetcher = @Sendable (
        GitHubRemoteReference,
        GitHubIssueState,
        String?
    ) async throws(GitHubIssueListError) -> GitHubIssuePage

    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(GitHubIssueListError)
    }

    private(set) var phase: Phase = .idle
    private(set) var issues: [GitHubIssue] = []
    private(set) var repository: GitHubRemoteReference?
    private(set) var stateFilter: GitHubIssueState = .open
    private(set) var isLoadingMore = false
    private(set) var loadMoreFailed = false

    var canLoadMore: Bool {
        phase == .loaded && nextCursor != nil
    }

    @ObservationIgnored private var nextCursor: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let fetchPage: PageFetcher

    init(fetchPage: @escaping PageFetcher) {
        self.fetchPage = fetchPage
    }

    convenience init(service: GitHubIssueListService) {
        self.init { repository, state, cursor throws(GitHubIssueListError) in
            try await service.fetchPage(repository: repository, state: state, after: cursor)
        }
    }

    /// Points the list at a remote and filter, then loads the first page.
    func load(remoteURL: String, state: GitHubIssueState) async {
        stateFilter = state
        guard let reference = GitHubRemoteURLParser.parse(remoteURL),
              GitHubRemoteURLParser.host(remoteURL) == "github.com"
        else {
            generation += 1
            repository = nil
            reset(to: .failed(.unsupportedRepository))
            return
        }
        repository = reference
        await reload()
    }

    /// Reloads the first page for the current repository and filter.
    func reload() async {
        generation += 1
        let requestGeneration = generation
        guard let repository else {
            reset(to: .failed(.unsupportedRepository))
            return
        }
        reset(to: .loading)
        do {
            let page = try await fetchPage(repository, stateFilter, nil)
            guard requestGeneration == generation else { return }
            issues = []
            append(page)
            phase = .loaded
        } catch {
            guard requestGeneration == generation else { return }
            phase = .failed(error)
        }
    }

    func loadMore() async {
        guard canLoadMore, !isLoadingMore, let repository, let cursor = nextCursor else { return }
        let requestGeneration = generation
        isLoadingMore = true
        loadMoreFailed = false
        defer { isLoadingMore = false }
        do {
            let page = try await fetchPage(repository, stateFilter, cursor)
            guard requestGeneration == generation else { return }
            append(page)
        } catch {
            guard requestGeneration == generation else { return }
            loadMoreFailed = true
        }
    }

    private func reset(to phase: Phase) {
        self.phase = phase
        issues = []
        nextCursor = nil
        isLoadingMore = false
        loadMoreFailed = false
    }

    /// Appends a page while skipping issue numbers already shown.
    private func append(_ page: GitHubIssuePage) {
        let known = Set(issues.map(\.number))
        issues += page.issues.filter { !known.contains($0.number) }
        nextCursor = page.nextCursor
    }
}
