@testable import GitMenuBar
import XCTest

@MainActor
final class GitManagerRefreshTests: XCTestCase {
    func testNormalizingEmptyRepositoryPathRemainsEmpty() {
        XCTAssertEqual(GitRepositoryContext.normalizedPath(""), "")
    }

    func testSupersededSelectedRefreshCannotPublishOrFinish() async {
        let manager = GitManager(repositoryPathOverride: "")
        let firstStarted = XCTestExpectation(description: "first refresh starts")
        let secondFinished = XCTestExpectation(description: "second refresh finishes")
        var completions = 0

        manager.selectedRefreshOperation = { [weak manager] session in
            if session.generation == 1 {
                firstStarted.fulfill()
                while !Task.isCancelled {
                    await Task.yield()
                }
                await GitExecution.publishOnMainActor(ifCurrent: session) {
                    manager?.remoteUrl = "A"
                }
                return
            }

            await GitExecution.publishOnMainActor(ifCurrent: session) {
                manager?.remoteUrl = "B"
            }
        }

        await manager.refreshSelectedRepository(path: "/tmp/project-a") {
            completions += 1
        }
        await fulfillment(of: [firstStarted])

        await manager.refreshSelectedRepository(path: "/tmp/project-b") {
            completions += 1
            secondFinished.fulfill()
        }
        await fulfillment(of: [secondFinished])

        XCTAssertEqual(manager.remoteUrl, "B")
        XCTAssertEqual(completions, 1)
    }

    func testPullToRefreshTerminatesAndCannotPublishAfterRepositorySwitch() async {
        let manager = GitManager(repositoryPathOverride: "")
        let firstStarted = XCTestExpectation(description: "pull refresh starts")
        let secondFinished = XCTestExpectation(description: "selected refresh finishes")

        manager.selectedRefreshOperation = { [weak manager] session in
            if session.generation == 1 {
                firstStarted.fulfill()
                while !Task.isCancelled {
                    await Task.yield()
                }
                await GitExecution.publishOnMainActor(ifCurrent: session) {
                    manager?.remoteUrl = "A"
                    manager?.currentBranch = "branch-a"
                }
                return
            }

            await GitExecution.publishOnMainActor(ifCurrent: session) {
                manager?.remoteUrl = "B"
                manager?.currentBranch = "branch-b"
            }
            secondFinished.fulfill()
        }

        let pullRefresh = Task { @MainActor in
            await manager.refreshSelectedRepositoryAsync(
                path: "/tmp/project-a",
                includeReflogHistory: false
            )
        }
        await fulfillment(of: [firstStarted])

        await manager.refreshSelectedRepository(path: "/tmp/project-b")
        await fulfillment(of: [secondFinished])
        await pullRefresh.value

        XCTAssertEqual(manager.remoteUrl, "B")
        XCTAssertEqual(manager.currentBranch, "branch-b")
    }

    func testFastCompletionPrecedesFinalCompletionAndKeepsDetailState() async {
        let manager = GitManager(repositoryPathOverride: "")
        let finished = XCTestExpectation(description: "refresh finishes")
        var events: [String] = []

        manager.selectedRefreshOperation = { [weak manager] session in
            await GitExecution.publishOnMainActor(ifCurrent: session) {
                manager?.changedFiles = [WorkingTreeFile(path: "README.md", lineDiff: .zero, status: .modified)]
                manager?.currentBranch = "feature/progressive"
                events.append("fast-state")
            }
            session.fastCompletion()
            await GitExecution.publishOnMainActor(ifCurrent: session) {
                manager?.remoteUrl = "https://github.com/example/project"
                events.append("detail-state")
            }
        }

        await manager.refreshSelectedRepository(
            fastCompletion: { events.append("fast") },
            completion: {
                events.append("final")
                finished.fulfill()
            }
        )
        await fulfillment(of: [finished])

        XCTAssertEqual(events, ["fast-state", "fast", "detail-state", "final"])
        XCTAssertEqual(manager.remoteUrl, "https://github.com/example/project")
    }
}
