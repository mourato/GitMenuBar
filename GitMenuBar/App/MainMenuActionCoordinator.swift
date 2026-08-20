import Foundation

struct MainMenuActionAlert: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

struct MainMenuWhitespaceCommitPrompt: Identifiable, Equatable {
    let id = UUID()
    let rawCommentText: String
    let shouldPushAfterCommit: Bool
}

enum MainMenuCommitExecutionResult: Equatable {
    case skipped
    case committed
    case committedAndNeedsSyncOptions
    case failed

    var didCommit: Bool {
        switch self {
        case .committed, .committedAndNeedsSyncOptions:
            true
        case .skipped, .failed:
            false
        }
    }

    var shouldOpenPopover: Bool {
        switch self {
        case .committedAndNeedsSyncOptions, .failed:
            true
        case .skipped, .committed:
            false
        }
    }
}

enum MainMenuSyncExecutionResult: Equatable {
    case skipped
    case synced
    case requiresOptions
    case failed

    var shouldOpenPopover: Bool {
        switch self {
        case .requiresOptions, .failed:
            true
        case .skipped, .synced:
            false
        }
    }
}

@MainActor
final class MainMenuActionCoordinator: ObservableObject {
    private enum CommitMessageInputState: Equatable {
        case empty
        case whitespaceOnly(raw: String)
        case manual(trimmed: String)
    }

    @Published var alert: MainMenuActionAlert?
    @Published var success: MainMenuActionAlert?
    @Published var showSyncOptions = false
    @Published var whitespaceCommitPrompt: MainMenuWhitespaceCommitPrompt?
    @Published private(set) var isExecutingPrimaryAction = false
    @Published var operationStatus: MainMenuOperationStatus?

    let gitManager: GitManager
    private let aiCommitCoordinator: AICommitCoordinator
    private let onCommitCompleted: (@MainActor (String) -> Void)?

    init(
        gitManager: GitManager,
        aiCommitCoordinator: AICommitCoordinator,
        onCommitCompleted: (@MainActor (String) -> Void)? = nil
    ) {
        self.gitManager = gitManager
        self.aiCommitCoordinator = aiCommitCoordinator
        self.onCommitCompleted = onCommitCompleted
    }

    var hasWorkingTreeChanges: Bool {
        !gitManager.stagedFiles.isEmpty || !gitManager.changedFiles.isEmpty
    }

    var hasSyncWork: Bool {
        gitManager.isAheadOfRemote || gitManager.isRemoteAhead
    }

    var syncActionTitle: String {
        gitManager.isAheadOfRemote && !gitManager.isRemoteAhead ? "Push Changes" : "Sync Changes"
    }

    var isBusy: Bool {
        gitManager.isCommitting || aiCommitCoordinator.isGenerating || isExecutingPrimaryAction
    }

    var canSwitchRepository: Bool { // ponytail: serialize project switching; use an immutable context for concurrent projects.
        !isBusy
    }

    var canAutoCommit: Bool {
        hasWorkingTreeChanges && aiCommitCoordinator.isReadyForGeneration && !isBusy
    }

    var canSync: Bool {
        hasSyncWork && !hasWorkingTreeChanges && !isBusy
    }

    func clearAlert() {
        alert = nil
        success = nil
    }

    func dismissWhitespaceCommitPrompt() {
        whitespaceCommitPrompt = nil
    }

    func dismissSyncOptions() {
        showSyncOptions = false
    }

    func performCommit(
        commentText: String,
        forceAutomaticMessage: Bool = false,
        shouldPushAfterCommit: Bool = false
    ) async -> MainMenuCommitExecutionResult {
        guard hasWorkingTreeChanges, !isBusy else {
            return .skipped
        }

        return await executeCommitOperation {
            clearAlert()
            showSyncOptions = false
            whitespaceCommitPrompt = nil

            let failureTitle = shouldPushAfterCommit ? "Commit & Push Failed" : "Commit Failed"

            if forceAutomaticMessage {
                return await commitUsingGeneratedMessage(
                    failureTitle: failureTitle,
                    shouldPushAfterCommit: shouldPushAfterCommit
                )
            }

            switch resolveCommitMessageInputState(commentText) {
            case .empty:
                return await commitUsingGeneratedMessage(
                    failureTitle: failureTitle,
                    shouldPushAfterCommit: shouldPushAfterCommit
                )
            case let .manual(trimmed):
                return await executeCommitFlow(
                    message: trimmed,
                    failureTitle: failureTitle,
                    shouldPushAfterCommit: shouldPushAfterCommit
                )
            case let .whitespaceOnly(raw):
                whitespaceCommitPrompt = MainMenuWhitespaceCommitPrompt(
                    rawCommentText: raw,
                    shouldPushAfterCommit: shouldPushAfterCommit
                )
                return .skipped
            }
        }
    }

    func commitUsingCurrentWhitespaceMessage(
        _ rawMessage: String,
        shouldPushAfterCommit: Bool = false
    ) async -> MainMenuCommitExecutionResult {
        guard hasWorkingTreeChanges, !isBusy else {
            return .skipped
        }

        return await executeCommitOperation {
            clearAlert()
            showSyncOptions = false
            whitespaceCommitPrompt = nil

            let failureTitle = shouldPushAfterCommit ? "Commit & Push Failed" : "Commit Failed"
            return await executeCommitFlow(
                message: rawMessage,
                failureTitle: failureTitle,
                shouldPushAfterCommit: shouldPushAfterCommit
            )
        }
    }

    func commitByGeneratingMessage(
        afterDiscardingWhitespace _: String,
        shouldPushAfterCommit: Bool = false
    ) async -> MainMenuCommitExecutionResult {
        guard hasWorkingTreeChanges, !isBusy else {
            return .skipped
        }

        return await executeCommitOperation {
            clearAlert()
            showSyncOptions = false
            whitespaceCommitPrompt = nil

            let failureTitle = shouldPushAfterCommit ? "Commit & Push Failed" : "Commit Failed"
            return await commitUsingGeneratedMessage(
                failureTitle: failureTitle,
                shouldPushAfterCommit: shouldPushAfterCommit
            )
        }
    }

    func performSync() async -> MainMenuSyncExecutionResult {
        guard canSync else {
            return .skipped
        }

        return await executePrimaryAction {
            clearAlert()
            showSyncOptions = false

            if gitManager.isRemoteAhead {
                showSyncOptions = true
                return .requiresOptions
            }

            let pushResult = await pushToRemote()
            guard case .success = pushResult else {
                if case let .failure(error) = pushResult {
                    publishAlert(title: "Sync Failed", message: error.localizedDescription)
                }
                return .failed
            }

            await refreshRepository()
            await refreshRemoteStatus()
            return .synced
        }
    }

    func performAtomicCommitsAndPush(groups: [AtomicCommitGroup]) async -> MainMenuCommitExecutionResult {
        guard !groups.isEmpty, !isBusy else {
            return .skipped
        }

        return await executeCommitOperation {
            clearAlert()
            showSyncOptions = false
            return await executeAtomicCommits(groups: groups, shouldPush: true)
        }
    }

    func performReviewedAtomicCommits(
        plan: AtomicCommitExecutionPlan
    ) async -> MainMenuCommitExecutionResult {
        guard !plan.groups.isEmpty, !isBusy else {
            return .skipped
        }

        return await executeCommitOperation {
            clearAlert()
            showSyncOptions = false
            return await executeAtomicCommits(
                groups: plan.groups,
                snapshot: plan.snapshot,
                shouldPush: false
            )
        }
    }

    func performAutomaticHunkCommitsAndPush(
        generatePlan: @escaping () async -> AtomicCommitExecutionPlan?
    ) async -> MainMenuCommitExecutionResult {
        guard !isBusy else { return .skipped }
        return await executeCommitOperation {
            clearAlert()
            showSyncOptions = false
            operationStatus = .groupingChanges
            guard let plan = await generatePlan(), !plan.groups.isEmpty else {
                publishAlert(title: "Split Commits Failed", message: "No changes could be grouped into commits.")
                return .failed
            }
            return await executeAtomicCommits(
                groups: plan.groups,
                snapshot: plan.snapshot,
                shouldPush: true
            )
        }
    }

    func syncWithRemote(rebase: Bool) async -> MainMenuSyncExecutionResult {
        guard !isBusy else {
            return .skipped
        }

        return await executePrimaryAction {
            clearAlert()
            showSyncOptions = false

            let pullResult = await pullFromRemote(rebase: rebase)
            guard case .success = pullResult else {
                if case let .failure(error) = pullResult {
                    publishAlert(title: "Sync Failed", message: error.localizedDescription)
                }
                return .failed
            }

            let pushResult = await pushToRemote()
            guard case .success = pushResult else {
                if case let .failure(error) = pushResult {
                    publishAlert(title: "Push Failed", message: error.localizedDescription)
                }
                return .failed
            }

            await refreshRepository()
            return .synced
        }
    }

    private var preferredCommitScope: DiffScope {
        gitManager.stagedFiles.isEmpty ? .unstaged : .staged
    }

    private func resolveCommitMessageInputState(_ rawInput: String) -> CommitMessageInputState {
        if rawInput.isEmpty {
            return .empty
        }

        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .whitespaceOnly(raw: rawInput)
        }

        return .manual(trimmed: trimmed)
    }

    func publishAlert(title: String, message: String) {
        alert = MainMenuActionAlert(title: title, message: message)
    }

    func publishSuccess(title: String, message: String) {
        success = MainMenuActionAlert(title: title, message: message)
    }

    private func commitUsingGeneratedMessage(
        failureTitle: String,
        shouldPushAfterCommit: Bool
    ) async -> MainMenuCommitExecutionResult {
        operationStatus = .generatingCommitMessage

        do {
            guard aiCommitCoordinator.isReadyForGeneration else {
                throw NSError(
                    domain: "MainMenuActionCoordinator",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: aiCommitCoordinator.generationDisabledReason]
                )
            }

            let message = try await aiCommitCoordinator.generateMessage(scopeOverride: preferredCommitScope)
            return await executeCommitFlow(
                message: message,
                failureTitle: failureTitle,
                shouldPushAfterCommit: shouldPushAfterCommit
            )
        } catch {
            publishAlert(title: failureTitle, message: error.localizedDescription)
            return .failed
        }
    }

    private func executeCommitFlow(
        message: String,
        failureTitle: String,
        shouldPushAfterCommit: Bool
    ) async -> MainMenuCommitExecutionResult {
        aiCommitCoordinator.generationError = nil
        operationStatus = .committing

        let commitResult = await commitLocally(message, skipUIUpdates: shouldPushAfterCommit)
        guard case .success = commitResult else {
            if case let .failure(error) = commitResult {
                publishAlert(title: failureTitle, message: error.localizedDescription)
            }
            return .failed
        }

        commitWasCreated = true

        await refreshRemoteStatus()

        guard shouldPushAfterCommit else {
            publishSuccess(title: "Commit complete", message: "Your changes were committed locally.")
            return .committed
        }

        if gitManager.isRemoteAhead {
            showSyncOptions = true
            return .committedAndNeedsSyncOptions
        }

        operationStatus = .pushing
        let pushResult = await pushToRemote()
        guard case .success = pushResult else {
            if case let .failure(error) = pushResult {
                publishAlert(
                    title: "Push Failed",
                    message: "The commit was created locally, but the push failed. "
                        + "\(error.localizedDescription) Try pushing again."
                )
            }
            return .failed
        }

        await refreshRepository()
        await refreshRemoteStatus()
        publishSuccess(title: "Commit & Push complete", message: "Your changes are now on the remote.")
        return .committed
    }

    private func executePrimaryAction<T>(_ operation: () async -> T) async -> T {
        let trace = GitPerformanceTrace.begin("primary.action")
        isExecutingPrimaryAction = true
        defer {
            isExecutingPrimaryAction = false
            operationStatus = nil
            GitPerformanceTrace.end("primary.action", id: trace)
        }
        return await operation()
    }

    var commitWasCreated = false

    private func executeCommitOperation(
        _ operation: () async -> MainMenuCommitExecutionResult
    ) async -> MainMenuCommitExecutionResult {
        commitWasCreated = false
        let repositoryPath = gitManager.repositoryPath
        let result = await executePrimaryAction(operation)
        if commitWasCreated {
            onCommitCompleted?(repositoryPath)
        }
        commitWasCreated = false
        return result
    }

    private func commitLocally(
        _ message: String,
        skipUIUpdates: Bool = false
    ) async -> Result<Void, Error> {
        await tracePrimaryPhase("primary.commit") {
            await gitManager.commitLocallyWithFallbackAsync(message, skipUIUpdates: skipUIUpdates)
        }
    }

    func pushToRemote() async -> Result<Void, Error> {
        await tracePrimaryPhase("primary.push") {
            await gitManager.pushToRemoteAsync()
        }
    }

    private func pullFromRemote(rebase: Bool) async -> Result<Void, Error> {
        await gitManager.pullFromRemoteAsync(rebase: rebase)
    }

    func refreshRepository(includeReflogHistory: Bool = false) async {
        await gitManager.refreshAsync(includeReflogHistory: includeReflogHistory)
    }

    func refreshRemoteStatus() async {
        await tracePrimaryPhase("primary.remote_status") {
            await gitManager.checkRemoteStatusAsync()
        }
    }

    private func tracePrimaryPhase<T>(
        _ name: StaticString,
        operation: () async -> T
    ) async -> T {
        let trace = GitPerformanceTrace.begin(name)
        defer { GitPerformanceTrace.end(name, id: trace) }
        return await operation()
    }
}
