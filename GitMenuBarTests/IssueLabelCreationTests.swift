@testable import GitMenuBar
import XCTest

final class IssueLabelDraftTests: XCTestCase {
    func testTrimsFieldsAndNormalizesTheColor() throws {
        let draft = try IssueLabelDraft.make(
            name: "  needs triage ",
            color: " #D73A4A ",
            description: "  Waits for triage  "
        )

        XCTAssertEqual(
            draft,
            IssueLabelDraft(name: "needs triage", color: "d73a4a", description: "Waits for triage")
        )
    }

    func testEmptyDescriptionBecomesNil() throws {
        let draft = try IssueLabelDraft.make(name: "bug", color: "d73a4a", description: "   ")

        XCTAssertNil(draft.description)
    }

    func testRequiredNameAndColorAreRejected() {
        XCTAssertThrowsError(try IssueLabelDraft.make(name: "   ", color: "d73a4a", description: "")) {
            XCTAssertEqual($0 as? IssueLabelDraft.ValidationError, .nameRequired)
        }
        for color in ["", "red", "d73a4", "d73a4aa", "zzzzzz", "##d73a4a"] {
            XCTAssertThrowsError(try IssueLabelDraft.make(name: "bug", color: color, description: "")) {
                XCTAssertEqual($0 as? IssueLabelDraft.ValidationError, .colorInvalid, color)
            }
        }
    }

    func testNameAndDescriptionLimits() {
        let longestName = String(repeating: "a", count: IssueLabelDraft.maximumNameLength)
        XCTAssertNoThrow(try IssueLabelDraft.make(name: longestName, color: "d73a4a", description: ""))
        XCTAssertThrowsError(try IssueLabelDraft.make(name: longestName + "a", color: "d73a4a", description: "")) {
            XCTAssertEqual($0 as? IssueLabelDraft.ValidationError, .nameTooLong)
        }

        let longestDescription = String(repeating: "a", count: IssueLabelDraft.maximumDescriptionLength)
        XCTAssertNoThrow(try IssueLabelDraft.make(name: "bug", color: "d73a4a", description: longestDescription))
        XCTAssertThrowsError(try IssueLabelDraft.make(name: "bug", color: "d73a4a", description: longestDescription + "a")) {
            XCTAssertEqual($0 as? IssueLabelDraft.ValidationError, .descriptionTooLong)
        }
    }

    func testExistingNameIsDetectedWithoutCase() {
        XCTAssertThrowsError(
            try IssueLabelDraft.make(name: "Bug", color: "d73a4a", description: "", existingNames: ["bug"])
        ) {
            XCTAssertEqual($0 as? IssueLabelDraft.ValidationError, .nameTaken)
        }

        XCTAssertNoThrow(
            try IssueLabelDraft.make(name: "bugfix", color: "d73a4a", description: "", existingNames: ["bug"])
        )
    }
}

@MainActor
final class IssueListModelLabelCreationTests: XCTestCase {
    private let remoteA = "https://github.com/mourato/GitMenuBar.git"
    private let remoteB = "https://github.com/mourato/Other.git"

    func testCreatingLabelAddsItWithoutApplyingItToAnIssue() async {
        let created = Self.label("needs triage", id: "L_new")
        let createdCalls = CreationRecorder()
        let mutationCalls = MutationRecorder()
        let model = Self.model(
            create: { repositoryID, name, color, description in
                await createdCalls.record(
                    CreationCall(
                        repositoryID: repositoryID,
                        name: name,
                        color: color,
                        description: description
                    )
                )
                return created
            },
            mutate: { issueID, labelID, adding in
                await mutationCalls.record(MutationCall(issueID: issueID, labelID: labelID, adding: adding))
                return [created]
            }
        )
        await model.load(remoteURL: remoteA, state: .open)

        let succeeded = await model.createLabel(
            name: " needs triage ",
            color: "#D73A4A",
            description: "Waits for triage"
        )

        XCTAssertTrue(succeeded)
        XCTAssertEqual(model.availableLabels, [created])
        XCTAssertEqual(model.issues[0].labels, [], "Creating a label must not apply it to the issue")
        XCTAssertNil(model.labelCreationError)
        XCTAssertFalse(model.isCreatingLabel)
        let requests = await createdCalls.calls
        XCTAssertEqual(
            requests,
            [
                CreationCall(
                    repositoryID: "R_1",
                    name: "needs triage",
                    color: "d73a4a",
                    description: "Waits for triage"
                )
            ]
        )
        let applied = await mutationCalls.calls
        XCTAssertEqual(applied.count, 0)
    }

    func testCreatedLabelCanBeAppliedWithTheExistingAction() async {
        let created = Self.label("needs triage", id: "L_new")
        let model = Self.model(
            issues: [Self.issue(1, nodeID: "I_1", labels: [])],
            create: { _, _, _, _ in created },
            mutate: { _, _, _ in [created] }
        )
        await model.load(remoteURL: remoteA, state: .open)
        await model.createLabel(name: "needs triage", color: "d73a4a", description: "")

        await model.setLabel(created, on: model.issues[0], adding: true)

        XCTAssertEqual(model.issues[0].labels, [created])
        XCTAssertNil(model.labelError)
    }

    func testNewLabelAppearsOnlyAfterGitHubConfirms() async {
        let created = Self.label("needs triage", id: "L_new")
        let gate = CreationGate()
        let model = Self.model(create: { _, _, _, _ in
            await gate.wait()
            return created
        })
        await model.load(remoteURL: remoteA, state: .open)

        let creation = Task { await model.createLabel(name: "needs triage", color: "d73a4a", description: "") }
        await gate.waitUntilEntered()

        XCTAssertTrue(model.isCreatingLabel)
        XCTAssertEqual(model.availableLabels, [])

        await gate.open()
        let succeeded = await creation.value

        XCTAssertTrue(succeeded)
        XCTAssertEqual(model.availableLabels, [created])
        XCTAssertFalse(model.isCreatingLabel)
    }

    func testReadOnlyAccountNeverCreatesALabel() async {
        let recorder = CreationRecorder()
        let model = Self.model(canWrite: false, create: { _, _, _, _ in
            await recorder.record(CreationCall(repositoryID: "R_1", name: "x", color: "d73a4a", description: nil))
            return Self.label("x", id: "L_x")
        })
        await model.load(remoteURL: remoteA, state: .open)

        XCTAssertFalse(model.canCreateLabels)
        let succeeded = await model.createLabel(name: "needs triage", color: "d73a4a", description: "")

        XCTAssertFalse(succeeded)
        XCTAssertNil(model.labelCreationError)
        let requests = await recorder.calls
        XCTAssertEqual(requests.count, 0)
    }

    func testValidationAndExistingNamesStopBeforeAnyRequest() async {
        let recorder = CreationRecorder()
        let model = Self.model(
            available: [Self.label("bug", id: "L_bug")],
            create: { _, name, color, description in
                await recorder.record(
                    CreationCall(repositoryID: "R_1", name: name, color: color, description: description)
                )
                return Self.label(name, id: "L_new")
            }
        )
        await model.load(remoteURL: remoteA, state: .open)
        XCTAssertTrue(model.canCreateLabels)

        let emptyName = await model.createLabel(name: "  ", color: "d73a4a", description: "")
        XCTAssertFalse(emptyName)
        XCTAssertEqual(model.labelCreationError, .validation(.nameRequired))

        let invalidColor = await model.createLabel(name: "needs triage", color: "red", description: "")
        XCTAssertFalse(invalidColor)
        XCTAssertEqual(model.labelCreationError, .validation(.colorInvalid))

        let duplicate = await model.createLabel(name: "Bug", color: "d73a4a", description: "")
        XCTAssertFalse(duplicate)
        XCTAssertEqual(model.labelCreationError, .validation(.nameTaken))

        let requests = await recorder.calls
        XCTAssertEqual(requests.count, 0)
        XCTAssertEqual(model.availableLabels, [Self.label("bug", id: "L_bug")])
    }

    func testFailureKeepsThePickerUnchangedAndReportsTheError() async {
        let bug = Self.label("bug", id: "L_bug")
        let model = Self.model(available: [bug], create: { _, _, _, _ throws(GitHubIssueLabelError) in
            throw .requestFailed
        })
        await model.load(remoteURL: remoteA, state: .open)

        let succeeded = await model.createLabel(name: "needs triage", color: "d73a4a", description: "")

        XCTAssertFalse(succeeded)
        XCTAssertEqual(model.availableLabels, [bug])
        XCTAssertEqual(model.labelCreationError, .repository(.requestFailed))
        XCTAssertFalse(model.isCreatingLabel)
    }

    func testForbiddenCreationSwitchesThePanelToReadOnly() async {
        let model = Self.model(create: { _, _, _, _ throws(GitHubIssueLabelError) in
            throw .forbidden
        })
        await model.load(remoteURL: remoteA, state: .open)
        XCTAssertTrue(model.canCreateLabels)

        let succeeded = await model.createLabel(name: "needs triage", color: "d73a4a", description: "")

        XCTAssertFalse(succeeded)
        XCTAssertEqual(model.labelCreationError, .repository(.forbidden))
        XCTAssertFalse(model.canEditLabels)
        XCTAssertFalse(model.canCreateLabels)
        XCTAssertEqual(model.availableLabels, [])
    }

    func testDuplicateNameReplyKeepsTheDraftOpen() async {
        let bug = Self.label("bug", id: "L_bug")
        let model = Self.model(available: [bug], create: { _, _, _, _ throws(GitHubIssueLabelError) in
            throw .labelNameTaken
        })
        await model.load(remoteURL: remoteA, state: .open)

        let succeeded = await model.createLabel(name: "needs triage", color: "d73a4a", description: "")

        XCTAssertFalse(succeeded)
        XCTAssertEqual(model.labelCreationError, .repository(.labelNameTaken))
        XCTAssertEqual(model.availableLabels, [bug])
    }

    func testClearingFeedbackSendsNoRequest() async {
        let recorder = CreationRecorder()
        let model = Self.model(create: { _, _, _, _ throws(GitHubIssueLabelError) in
            await recorder.record(CreationCall(repositoryID: "R_1", name: "x", color: "d73a4a", description: nil))
            throw .requestFailed
        })
        await model.load(remoteURL: remoteA, state: .open)
        await model.createLabel(name: "needs triage", color: "d73a4a", description: "")

        model.clearLabelCreationError()

        XCTAssertNil(model.labelCreationError)
        let requests = await recorder.calls
        XCTAssertEqual(requests.count, 1)
    }

    func testCreationAfterRepositorySwitchIsIgnored() async {
        let created = Self.label("needs triage", id: "L_new")
        let otherLabels = [Self.label("docs", id: "L_docs")]
        let gate = CreationGate()
        let model = IssueListModel(
            fetchPage: { _, _, _ in
                GitHubIssuePage(issues: [Self.issue(1, nodeID: "I_1", labels: [])], nextCursor: nil)
            },
            labels: IssueListModel.IssueLabelActions(
                fetchLabels: { repository in
                    if repository.repository == "Other" {
                        return GitHubIssueLabelSnapshot(labels: otherLabels, canWrite: true, repositoryID: "R_2")
                    }
                    return GitHubIssueLabelSnapshot(
                        labels: [Self.label("bug", id: "L_bug")],
                        canWrite: true,
                        repositoryID: "R_1"
                    )
                },
                mutateLabel: { _, _, _ in [] },
                createLabel: { _, _, _, _ in
                    await gate.wait()
                    return created
                }
            )
        )
        await model.load(remoteURL: remoteA, state: .open)
        let creation = Task { await model.createLabel(name: "needs triage", color: "d73a4a", description: "") }
        await gate.waitUntilEntered()

        await model.load(remoteURL: remoteB, state: .open)
        await gate.open()
        let succeeded = await creation.value

        XCTAssertFalse(succeeded)
        XCTAssertEqual(model.availableLabels.map(\.name), ["docs"])
        XCTAssertFalse(model.isCreatingLabel)
        XCTAssertNil(model.labelCreationError)
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
        issues: [GitHubIssue] = [GitHubIssue(
            number: 1,
            title: "Issue 1",
            state: .open,
            authorLogin: "octocat",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            labels: [],
            url: URL(fileURLWithPath: "/issues/1"),
            nodeID: "I_1"
        )],
        available: [GitHubIssueLabel] = [],
        canWrite: Bool = true,
        repositoryID: String = "R_1",
        create: @escaping IssueListModel.LabelCreator,
        mutate: @escaping IssueListModel.LabelMutator = { _, _, _ in [] }
    ) -> IssueListModel {
        IssueListModel(
            fetchPage: { _, _, _ in GitHubIssuePage(issues: issues, nextCursor: nil) },
            labels: IssueListModel.IssueLabelActions(
                fetchLabels: { _ in
                    GitHubIssueLabelSnapshot(
                        labels: available,
                        canWrite: canWrite,
                        repositoryID: repositoryID
                    )
                },
                mutateLabel: mutate,
                createLabel: create
            )
        )
    }
}

private struct CreationCall: Equatable, Sendable {
    let repositoryID: String
    let name: String
    let color: String
    let description: String?
}

private struct MutationCall: Equatable, Sendable {
    let issueID: String
    let labelID: String
    let adding: Bool
}

private actor CreationRecorder {
    private(set) var calls: [CreationCall] = []

    func record(_ call: CreationCall) {
        calls.append(call)
    }
}

private actor MutationRecorder {
    private(set) var calls: [MutationCall] = []

    func record(_ call: MutationCall) {
        calls.append(call)
    }
}

private actor CreationGate {
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
