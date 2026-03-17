@testable import GitMenuBar
import XCTest

final class HistoryCommitGroupingTests: XCTestCase {
    func testGroupCommitsByDayWithRelativeTitles() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let now = makeDate(
            DateComponents(year: 2026, month: 3, day: 16, hour: 14, minute: 0),
            calendar: calendar
        )
        let todayMorning = makeDate(
            DateComponents(year: 2026, month: 3, day: 16, hour: 9, minute: 30),
            calendar: calendar
        )
        let yesterdayEvening = makeDate(
            DateComponents(year: 2026, month: 3, day: 15, hour: 21, minute: 0),
            calendar: calendar
        )
        let olderDay = makeDate(
            DateComponents(year: 2026, month: 3, day: 10, hour: 8, minute: 0),
            calendar: calendar
        )

        let commits = [
            makeCommit(id: "today", committedAt: todayMorning),
            makeCommit(id: "yesterday", committedAt: yesterdayEvening),
            makeCommit(id: "older", committedAt: olderDay)
        ]

        let sections = HistoryCommitGrouping.group(commits: commits, now: now, calendar: calendar)

        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections[0].commits.map(\.id), ["today"])
        XCTAssertTrue(sections[0].title.hasPrefix("Today"))
        XCTAssertEqual(sections[1].commits.map(\.id), ["yesterday"])
        XCTAssertTrue(sections[1].title.hasPrefix("Yesterday"))
        XCTAssertEqual(sections[2].commits.map(\.id), ["older"])
        XCTAssertFalse(sections[2].title.hasPrefix("Today"))
        XCTAssertFalse(sections[2].title.hasPrefix("Yesterday"))
    }

    func testGroupSortsCommitsWithinTheSameDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let now = makeDate(
            DateComponents(year: 2026, month: 3, day: 16, hour: 14, minute: 0),
            calendar: calendar
        )
        let morning = makeDate(
            DateComponents(year: 2026, month: 3, day: 16, hour: 9, minute: 30),
            calendar: calendar
        )
        let evening = makeDate(
            DateComponents(year: 2026, month: 3, day: 16, hour: 21, minute: 0),
            calendar: calendar
        )

        let commits = [
            makeCommit(id: "morning", committedAt: morning),
            makeCommit(id: "evening", committedAt: evening)
        ]

        let sections = HistoryCommitGrouping.group(commits: commits, now: now, calendar: calendar)

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].commits.map(\.id), ["evening", "morning"])
    }

    private func makeDate(_ components: DateComponents, calendar: Calendar) -> Date {
        var components = components
        components.calendar = calendar
        return components.date ?? Date()
    }

    private func makeCommit(id: String, committedAt: Date) -> Commit {
        Commit(
            id: id,
            shortHash: String(id.prefix(7)),
            subject: "feat: \(id)",
            body: "",
            authorName: "Renato",
            authorEmail: "renato@example.com",
            committedAt: committedAt,
            stats: CommitStats(filesChanged: 1, insertions: 1, deletions: 0),
            changedFiles: []
        )
    }
}
