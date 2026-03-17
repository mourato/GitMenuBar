import Foundation

struct HistoryCommitDaySection: Identifiable, Equatable {
    let dayStart: Date
    let title: String
    let commits: [Commit]

    var id: Date {
        dayStart
    }
}

enum HistoryCommitGrouping {
    private static let absoluteDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func group(
        commits: [Commit],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [HistoryCommitDaySection] {
        let grouped = Dictionary(grouping: commits) { commit in
            calendar.startOfDay(for: commit.committedAt)
        }

        return grouped
            .keys
            .sorted(by: >)
            .map { dayStart in
                let dayCommits = grouped[dayStart, default: []]
                    .sorted(by: { $0.committedAt > $1.committedAt })

                return HistoryCommitDaySection(
                    dayStart: dayStart,
                    title: title(for: dayStart, now: now, calendar: calendar),
                    commits: dayCommits
                )
            }
    }

    static func title(for dayStart: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let nowDayStart = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: nowDayStart)
        let absolute = absoluteDayFormatter.string(from: dayStart)

        if dayStart == nowDayStart {
            return "Today — \(absolute)"
        }

        if dayStart == yesterday {
            return "Yesterday — \(absolute)"
        }

        return absolute
    }
}
