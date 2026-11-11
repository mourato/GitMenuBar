@testable import GitMenuBar
import XCTest

@MainActor
final class IssueListModelLabelTests: XCTestCase {
    private let remoteA = "https://github.com/mourato/GitMenuBar.git"

    func testAddingLabelUpdatesOnlyTargetIssueAndKeepsOtherLabels() async {
        let bug = Self.label("bug", id: "L_bug")
        let docs = Self.label("docs", id: "L_docs")
        let enhancement = Self.label("enhancement", id: "L_enh")
        let firstIssue = Self.issue(1, nodeID: "I_1", labels: [bug])
        let secondIssue = Self.issue(2, nodeID: "I_2", labels: [docs])
        let recorder = MutationRecorder()
        let model = Self.model(issues: [firstIssue, secondIssue], available: [bug, docs, enhancement]) { issueID, labelID, adding in
            await recorder.record(Call(issueID: issueID, labelID: labelID, adding: adding))
            return [bug, enhancement]
        }

        await model.load(remoteURL: remoteA, state: .open)
        await model.setLabel(enhancement, on: model.issues[0], adding: true)

        XCTAssertEqual(model.issues[0].labels, [bug, enhancement])
        XCTAssertEqual(model.issues[1].labels, [docs])
        let calls = await recorder.calls
        XCTAssertEqual(calls, [Call(issueID: "I_1", labelID: "L_enh", adding: true)])
        XCTAssertNil(model.labelError)
        XCTAssertNil(model.pendingLabelChange)
    }

    func testRemovingLabelLeavesOtherLabelsAndUpdatesList() async {
        let bug = Self.label("bug", id: "L_bug")
        let enhancement = Self.label("enhancement", id: "L_enh")
        let model = Self.model(
            issues: [Self.issue(1, nodeID: "I_1", labels: [bug, enhancement])],
            available: [bug, enhancement]
        ) { _, _, _ in
            [bug]
        }

        await model.load(remoteURL: remoteA, state: .open)
        await model.setLabel(enhancement, on: model.issues[0], adding: false)

        XCTAssertEqual(model.issues[0].labels, [bug])
    }

    func testSecondTapWhileFirstChangeRunsSendsOneRequest() async {
        let bug = Self.label("bug", id: "L_bug")
        let gate = AsyncGate()
        let recorder = MutationRecorder()
        let model = Self.model(issues: [Self.issue(1, nodeID: "I_1", labels: [])], available: [bug]) { issueID, labelID, adding in
            await gate.wait()
            await recorder.record(Call(issueID: issueID, labelID: labelID, adding: adding))
            return [bug]
        }

        await model.load(remoteURL: remoteA, state: .open)
        let first = Task { await model.setLabel(bug, on: model.issues[0], adding: true) }
        await gate.waitUntilEntered()
        XCTAssertEqual(model.pendingLabelChange?.issueNumber, 1)
        await model.setLabel(bug, on: model.issues[0], adding: true)
        await gate.open()
        await first.value

        let callCount = await recorder.calls.count
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(model.issues[0].labels, [bug])
    }

    func testFailureKeepsLabelsAndRetryAppliesTheChange() async {
        let bug = Self.label("bug", id: "L_bug")
        let enhancement = Self.label("enhancement", id: "L_enh")
        let attempts = Counter()
        let model = Self.model(
            issues: [Self.issue(1, nodeID: "I_1", labels: [bug])],
            available: [bug, enhancement]
        ) { _, _, _ throws(GitHubIssueLabelError) in
            if await attempts.increment() == 1 {
                throw .requestFailed
            }
            return [bug, enhancement]
        }

        await model.load(remoteURL: remoteA, state: .open)
        await model.setLabel(enhancement, on: model.issues[0], adding: true)

        XCTAssertEqual(model.issues[0].labels, [bug])
        XCTAssertEqual(model.labelError, .requestFailed)
        XCTAssertNil(model.pendingLabelChange)

        await model.retryLastLabelChange()
        XCTAssertNil(model.labelError)
        XCTAssertEqual(model.issues[0].labels, [bug, enhancement])
    }

    func testForbiddenMutationKeepsReadAccessAndStopsWrites() async {
        let bug = Self.label("bug", id: "L_bug")
        let model = Self.model(
            issues: [Self.issue(1, nodeID: "I_1", labels: [])],
            available: [bug]
        ) { _, _, _ throws(GitHubIssueLabelError) in
            throw .forbidden
        }

        await model.load(remoteURL: remoteA, state: .open)
        await model.setLabel(bug, on: model.issues[0], adding: true)

        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.issues.map(\.number), [1])
        XCTAssertEqual(model.labelError, .forbidden)
        XCTAssertFalse(model.canEditLabels)
        XCTAssertEqual(model.issues[0].labels, [])
    }

    func testReadOnlyPermissionSkipsMutatingRequests() async {
        let bug = Self.label("bug", id: "L_bug")
        let recorder = MutationRecorder()
        let model = Self.model(
            issues: [Self.issue(1, nodeID: "I_1", labels: [])],
            available: [bug],
            canWrite: false
        ) { issueID, labelID, adding in
            await recorder.record(Call(issueID: issueID, labelID: labelID, adding: adding))
            return [bug]
        }

        await model.load(remoteURL: remoteA, state: .open)
        XCTAssertEqual(model.labelsPhase, .loaded)
        XCTAssertFalse(model.canEditLabels)
        await model.setLabel(bug, on: model.issues[0], adding: true)

        let callCount = await recorder.calls.count
        XCTAssertEqual(callCount, 0)
        XCTAssertNil(model.labelError)
    }

    func testLabelListFailureKeepsIssuesReadable() async {
        let model = IssueListModel(
            fetchPage: { _, _, _ in GitHubIssuePage(issues: [Self.issue(1, nodeID: "I_1", labels: [])], nextCursor: nil) },
            labels: IssueListModel.IssueLabelActions(
                fetchLabels: { _ throws(GitHubIssueLabelError) in throw .requestFailed },
                mutateLabel: { _, _, _ in [] }
            )
        )

        await model.load(remoteURL: remoteA, state: .open)

        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.issues.map(\.number), [1])
        XCTAssertEqual(model.labelsPhase, .failed(.requestFailed))
        XCTAssertFalse(model.canEditLabels)
    }

    func testMutationReplyAfterRepositorySwitchIsIgnored() async {
        let bug = Self.label("bug", id: "L_bug")
        let firstIssues = [Self.issue(1, nodeID: "I_1", labels: [])]
        let otherIssues = [Self.issue(99, nodeID: "I_99", labels: [])]
        let gate = AsyncGate()
        let switchingModel = IssueListModel(
            fetchPage: { repository, _, _ in
                GitHubIssuePage(
                    issues: repository.repository == "Other" ? otherIssues : firstIssues,
                    nextCursor: nil
                )
            },
            labels: IssueListModel.IssueLabelActions(
                fetchLabels: { _ in GitHubIssueLabelSnapshot(labels: [bug], canWrite: true) },
                mutateLabel: { _, _, _ in
                    await gate.wait()
                    return [bug]
                }
            )
        )

        await switchingModel.load(remoteURL: "https://github.com/mourato/GitMenuBar.git", state: .open)
        let pending = Task { await switchingModel.setLabel(bug, on: switchingModel.issues[0], adding: true) }
        await gate.waitUntilEntered()
        await switchingModel.load(remoteURL: "https://github.com/mourato/Other.git", state: .open)
        await gate.open()
        await pending.value

        XCTAssertEqual(switchingModel.issues.map(\.number), [99])
        XCTAssertNil(switchingModel.labelError)
        XCTAssertNil(switchingModel.pendingLabelChange)
    }

    func testStaleCompletionDoesNotClearTheCurrentRepositoryChange() async {
        let bug = Self.label("bug", id: "L_bug")
        let firstGate = AsyncGate()
        let secondGate = AsyncGate()
        let issuesByRepository: [String: [GitHubIssue]] = [
            "GitMenuBar": [Self.issue(1, nodeID: "I_1", labels: [])],
            "Other": [Self.issue(99, nodeID: "I_99", labels: [])]
        ]
        let switchingModel = IssueListModel(
            fetchPage: { repository, _, _ in
                GitHubIssuePage(issues: issuesByRepository[repository.repository] ?? [], nextCursor: nil)
            },
            labels: IssueListModel.IssueLabelActions(
                fetchLabels: { _ in GitHubIssueLabelSnapshot(labels: [bug], canWrite: true) },
                mutateLabel: { issueID, _, _ in
                    if issueID == "I_1" {
                        await firstGate.wait()
                    } else {
                        await secondGate.wait()
                    }
                    return [bug]
                }
            )
        )

        await switchingModel.load(remoteURL: "https://github.com/mourato/GitMenuBar.git", state: .open)
        let firstChange = Task { await switchingModel.setLabel(bug, on: switchingModel.issues[0], adding: true) }
        await firstGate.waitUntilEntered()
        await switchingModel.load(remoteURL: "https://github.com/mourato/Other.git", state: .open)
        let secondChange = Task { await switchingModel.setLabel(bug, on: switchingModel.issues[0], adding: true) }
        await secondGate.waitUntilEntered()

        await firstGate.open()
        await firstChange.value
        XCTAssertEqual(switchingModel.pendingLabelChange?.issueNumber, 99)

        await secondGate.open()
        await secondChange.value
        XCTAssertEqual(switchingModel.issues.map(\.number), [99])
        XCTAssertEqual(switchingModel.issues[0].labels, [bug])
        XCTAssertNil(switchingModel.pendingLabelChange)
    }

    func testFailedLabelListLoadsAgainWhenThePanelReloads() async {
        let signedIn = SignInFlag()
        let model = IssueListModel(
            fetchPage: { _, _, _ in GitHubIssuePage(issues: [Self.issue(1, nodeID: "I_1", labels: [])], nextCursor: nil) },
            labels: IssueListModel.IssueLabelActions(
                fetchLabels: { _ throws(GitHubIssueLabelError) in
                    guard await signedIn.value else { throw .notAuthenticated }
                    return GitHubIssueLabelSnapshot(labels: [Self.label("bug", id: "L_bug")], canWrite: true)
                },
                mutateLabel: { _, _, _ in [] }
            )
        )

        await model.load(remoteURL: remoteA, state: .open)
        XCTAssertEqual(model.labelsPhase, .failed(.notAuthenticated))

        await signedIn.set()
        await model.load(remoteURL: remoteA, state: .open)

        XCTAssertEqual(model.labelsPhase, .loaded)
        XCTAssertTrue(model.canEditLabels)
    }

    func testTryAgainWithoutARepeatableChangeRefreshesInstead() async {
        let bug = Self.label("bug", id: "L_bug")
        let pageCalls = Counter()
        let labelCalls = Counter()
        let model = IssueListModel(
            fetchPage: { _, _, _ in
                _ = await pageCalls.increment()
                return GitHubIssuePage(issues: [Self.issue(1, nodeID: "", labels: [])], nextCursor: nil)
            },
            labels: IssueListModel.IssueLabelActions(
                fetchLabels: { _ in
                    _ = await labelCalls.increment()
                    return GitHubIssueLabelSnapshot(labels: [bug], canWrite: true, repositoryID: "R_1")
                },
                mutateLabel: { _, _, _ in [] }
            )
        )
        await model.load(remoteURL: remoteA, state: .open)
        let pagesBeforeRetry = await pageCalls.value
        let labelsBeforeRetry = await labelCalls.value

        await model.setLabel(bug, on: model.issues[0], adding: true)
        XCTAssertEqual(model.labelError, .requestFailed)

        await model.retryLastLabelChange()

        XCTAssertNil(model.labelError)
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.labelsPhase, .loaded)
        let pagesAfterRetry = await pageCalls.value
        let labelsAfterRetry = await labelCalls.value
        XCTAssertEqual(pagesAfterRetry, pagesBeforeRetry + 1, "Try Again must reload the issue page")
        XCTAssertEqual(labelsAfterRetry, labelsBeforeRetry + 1, "Try Again must reload the label list")
    }

    // MARK: - Helpers

    private nonisolated static func label(_ name: String, id: String) -> GitHubIssueLabel {
        GitHubIssueLabel(name: name, colorHex: "d73a4a", nodeID: id)
    }

    private nonisolated static func issue(
        _ number: Int,
        nodeID: String,
        labels: [GitHubIssueLabel]
    ) -> GitHubIssue {
        GitHubIssue(
            number: number,
            title: "Issue \(number)",
            state: .open,
            authorLogin: "octocat",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            labels: labels,
            url: URL(fileURLWithPath: "/issues/\(number)"),
            nodeID: nodeID
        )
    }

    private static func model(
        issues: [GitHubIssue],
        available: [GitHubIssueLabel],
        canWrite: Bool = true,
        mutate: @escaping IssueListModel.LabelMutator
    ) -> IssueListModel {
        IssueListModel(
            fetchPage: { _, _, _ in GitHubIssuePage(issues: issues, nextCursor: nil) },
            labels: IssueListModel.IssueLabelActions(
                fetchLabels: { _ in GitHubIssueLabelSnapshot(labels: available, canWrite: canWrite) },
                mutateLabel: mutate
            )
        )
    }
}

private actor SignInFlag {
    private(set) var value = false

    func set() {
        value = true
    }
}

private struct Call: Equatable, Sendable {
    let issueID: String
    let labelID: String
    let adding: Bool
}

private actor MutationRecorder {
    private(set) var calls: [Call] = []

    func record(_ call: Call) {
        calls.append(call)
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func waitUntilEntered() async {
        while waiters.isEmpty, !isOpen {
            await Task.yield()
        }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

private actor Counter {
    private(set) var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}
