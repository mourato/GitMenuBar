import Foundation
import Observation

/// Presentation state for the Issues side panel. Network reads and label
/// writes go through injected actions; every response is checked against the
/// request generation, so a late reply for an earlier project or filter never
/// shows or overwrites the list.
@MainActor
@Observable
final class IssueListModel {
    typealias PageFetcher = @Sendable (
        GitHubRemoteReference,
        GitHubIssueState,
        String?
    ) async throws(GitHubIssueListError) -> GitHubIssuePage

    typealias LabelFetcher = @Sendable (
        GitHubRemoteReference
    ) async throws(GitHubIssueLabelError) -> GitHubIssueLabelSnapshot

    typealias LabelMutator = @Sendable (
        _ issueID: String,
        _ labelID: String,
        _ adding: Bool
    ) async throws(GitHubIssueLabelError) -> [GitHubIssueLabel]

    typealias LabelCreator = @Sendable (
        _ repositoryID: String,
        _ name: String,
        _ color: String,
        _ description: String?
    ) async throws(GitHubIssueLabelError) -> GitHubIssueLabel

    /// Label reads and writes for one issue, kept separate from the page
    /// fetcher so list-only callers do not need label networking. `createLabel`
    /// is optional so fixtures and list-only callers keep working without a
    /// creator; production always supplies one.
    struct IssueLabelActions: Sendable {
        let fetchLabels: LabelFetcher
        let mutateLabel: LabelMutator
        let createLabel: LabelCreator?

        init(
            fetchLabels: @escaping LabelFetcher,
            mutateLabel: @escaping LabelMutator,
            createLabel: LabelCreator? = nil
        ) {
            self.fetchLabels = fetchLabels
            self.mutateLabel = mutateLabel
            self.createLabel = createLabel
        }
    }

    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(GitHubIssueListError)
    }

    enum LabelsPhase: Equatable {
        case idle
        case loading
        case loaded
        case failed(GitHubIssueLabelError)
    }

    struct LabelChange: Equatable {
        let issueNumber: Int
        let labelName: String
        let isAdding: Bool
    }

    private(set) var phase: Phase = .idle
    private(set) var issues: [GitHubIssue] = []
    private(set) var repository: GitHubRemoteReference?
    private(set) var stateFilter: GitHubIssueState = .open
    private(set) var isLoadingMore = false
    private(set) var loadMoreFailed = false

    private(set) var labelsPhase: LabelsPhase = .idle
    private(set) var availableLabels: [GitHubIssueLabel] = []
    private(set) var canEditLabels = false
    private(set) var pendingLabelChange: LabelChange?
    private(set) var labelError: GitHubIssueLabelError?
    private(set) var isCreatingLabel = false
    private(set) var labelCreationError: IssueLabelCreationError?

    var canLoadMore: Bool {
        phase == .loaded && nextCursor != nil
    }

    /// The create action exists only after the label list confirms both write
    /// access and a repository to create in.
    var canCreateLabels: Bool {
        canEditLabels && labelsPhase == .loaded && labelActions?.createLabel != nil
    }

    @ObservationIgnored private var nextCursor: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var labelGeneration = 0
    @ObservationIgnored private var labelRepositoryID = ""
    @ObservationIgnored private var labelCreationToken = 0
    @ObservationIgnored private var lastFailedLabelChange: LabelChange?
    @ObservationIgnored private let fetchPage: PageFetcher
    @ObservationIgnored private let labelActions: IssueLabelActions?

    init(fetchPage: @escaping PageFetcher, labels: IssueLabelActions? = nil) {
        self.fetchPage = fetchPage
        labelActions = labels
    }

    convenience init(service: GitHubIssueListService, labelService: GitHubIssueLabelService) {
        self.init(
            fetchPage: { repository, state, cursor throws(GitHubIssueListError) in
                try await service.fetchPage(repository: repository, state: state, after: cursor)
            },
            labels: IssueLabelActions(
                fetchLabels: { repository throws(GitHubIssueLabelError) in
                    try await labelService.fetchSnapshot(repository: repository)
                },
                mutateLabel: { issueID, labelID, adding throws(GitHubIssueLabelError) in
                    if adding {
                        try await labelService.addLabel(issueID: issueID, labelID: labelID)
                    } else {
                        try await labelService.removeLabel(issueID: issueID, labelID: labelID)
                    }
                },
                createLabel: { repositoryID, name, color, description throws(GitHubIssueLabelError) in
                    try await labelService.createLabel(
                        repositoryID: repositoryID,
                        name: name,
                        color: color,
                        description: description
                    )
                }
            )
        )
    }

    /// Points the list at a remote and filter, then loads the first page and
    /// the repository's labels. Switching repositories discards both.
    func load(remoteURL: String, state: GitHubIssueState) async {
        stateFilter = state
        guard let reference = GitHubRemoteURLParser.parse(remoteURL),
              GitHubRemoteURLParser.host(remoteURL) == "github.com"
        else {
            generation += 1
            labelGeneration += 1
            repository = nil
            resetLabels()
            reset(to: .failed(.unsupportedRepository))
            return
        }
        if repository != reference {
            repository = reference
            labelGeneration += 1
            resetLabels()
        } else {
            // A page reload starts a new list context; old retry feedback no
            // longer points at a row the user can see.
            labelError = nil
            lastFailedLabelChange = nil
            // A failed label list (for example before sign-in) tries again
            // when the panel reloads instead of staying stale.
            if case .failed = labelsPhase {
                labelsPhase = .idle
            }
        }
        // Labels load independently of page reloads: a cancelled panel task
        // must not leave a half-loaded picker, and the label generation guard
        // drops a reply that belongs to an earlier repository.
        let labelsLoaded = Task { await loadLabelsIfNeeded() }
        await reload()
        await labelsLoaded.value
    }

    /// Reloads issues and labels, so permission changes on GitHub show up.
    func refresh() async {
        labelError = nil
        lastFailedLabelChange = nil
        async let labels: Void = reloadLabels()
        await reload()
        await labels
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

    // MARK: - Labels

    /// Retries the repository label list, for example after a connection error.
    func reloadLabels() async {
        guard labelActions != nil, labelsPhase != .loading else { return }
        await loadLabels()
    }

    /// Adds or removes one label on one issue. Only a GitHub-confirmed reply
    /// updates the list, and one change runs at a time so a second tap cannot
    /// duplicate the request.
    func setLabel(_ label: GitHubIssueLabel, on issue: GitHubIssue, adding: Bool) async {
        guard labelsPhase == .loaded, canEditLabels, pendingLabelChange == nil else { return }
        guard !issue.nodeID.isEmpty, !label.nodeID.isEmpty else {
            labelError = .requestFailed
            return
        }
        let hasLabel = issue.labels.contains { $0.name == label.name }
        guard hasLabel != adding else { return }
        let change = LabelChange(issueNumber: issue.number, labelName: label.name, isAdding: adding)
        await performLabelChange(change, issueID: issue.nodeID, labelID: label.nodeID)
    }

    /// Repeats the last failed change without touching other labels.
    /// Without a change to repeat, it reloads the list and labels instead,
    /// so Try Again never does nothing.
    func retryLastLabelChange() async {
        guard canEditLabels, labelError != nil else { return }
        guard let change = lastFailedLabelChange,
              let issue = issues.first(where: { $0.number == change.issueNumber }),
              let label = availableLabels.first(where: { $0.name == change.labelName })
        else {
            await refresh()
            return
        }
        lastFailedLabelChange = nil
        await performLabelChange(change, issueID: issue.nodeID, labelID: label.nodeID)
    }

    /// Creates one repository label. Required fields and a duplicate name stop
    /// before any request; only a GitHub-confirmed reply adds the label to the
    /// picker. Creating never applies the label to an issue: applying stays the
    /// separate toggle action. Returns true only after that confirmation.
    func createLabel(name: String, color: String, description: String) async -> Bool {
        labelCreationError = nil
        guard canCreateLabels,
              pendingLabelChange == nil,
              !isCreatingLabel,
              let createLabel = labelActions?.createLabel,
              let repository
        else {
            return false
        }
        let draft: IssueLabelDraft
        do {
            draft = try IssueLabelDraft.make(
                name: name,
                color: color,
                description: description,
                existingNames: availableLabels.map(\.name)
            )
        } catch {
            labelCreationError = .validation(error)
            return false
        }
        guard !labelRepositoryID.isEmpty else {
            labelCreationError = .repository(.requestFailed)
            return false
        }
        labelCreationToken += 1
        let requestToken = labelCreationToken
        isCreatingLabel = true
        defer {
            // A repository switch clears this flag and may start another
            // creation; only clear the state this call still owns.
            if requestToken == labelCreationToken {
                isCreatingLabel = false
            }
        }
        do {
            let label = try await createLabel(labelRepositoryID, draft.name, draft.color, draft.description)
            guard repository == self.repository else { return false }
            if !availableLabels.contains(where: { $0.name.caseInsensitiveCompare(label.name) == .orderedSame }) {
                availableLabels.append(label)
            }
            return true
        } catch {
            guard repository == self.repository else { return false }
            labelCreationError = .repository(error)
            if error == .forbidden {
                canEditLabels = false
            }
            return false
        }
    }

    /// Dismisses creation feedback without touching GitHub.
    func clearLabelCreationError() {
        labelCreationError = nil
    }

    private func loadLabelsIfNeeded() async {
        guard labelsPhase == .idle else { return }
        await loadLabels()
    }

    private func loadLabels() async {
        guard let labelActions, let repository else { return }
        labelGeneration += 1
        let requestGeneration = labelGeneration
        labelsPhase = .loading
        labelError = nil
        do {
            let snapshot = try await labelActions.fetchLabels(repository)
            guard requestGeneration == labelGeneration else { return }
            availableLabels = snapshot.labels
            canEditLabels = snapshot.canWrite
            labelRepositoryID = snapshot.repositoryID
            labelsPhase = .loaded
        } catch {
            guard requestGeneration == labelGeneration else { return }
            availableLabels = []
            canEditLabels = false
            labelRepositoryID = ""
            labelsPhase = .failed(error)
        }
    }

    private func performLabelChange(
        _ change: LabelChange,
        issueID: String,
        labelID: String
    ) async {
        guard let labelActions, pendingLabelChange == nil else { return }
        pendingLabelChange = change
        labelError = nil
        lastFailedLabelChange = nil
        let requestGeneration = generation
        defer {
            // A repository switch may have cleared this and started another
            // change; only clear the state this call still owns.
            if pendingLabelChange == change {
                pendingLabelChange = nil
            }
        }
        do {
            let labels = try await labelActions.mutateLabel(issueID, labelID, change.isAdding)
            guard requestGeneration == generation,
                  let index = issues.firstIndex(where: { $0.number == change.issueNumber })
            else {
                return
            }
            issues[index] = issues[index].replacingLabels(labels)
        } catch {
            guard requestGeneration == generation else { return }
            labelError = error
            lastFailedLabelChange = change
            if error == .forbidden {
                canEditLabels = false
            }
        }
    }

    private func resetLabels() {
        availableLabels = []
        labelsPhase = .idle
        canEditLabels = false
        labelError = nil
        pendingLabelChange = nil
        lastFailedLabelChange = nil
        labelRepositoryID = ""
        labelCreationToken += 1
        isCreatingLabel = false
        labelCreationError = nil
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
