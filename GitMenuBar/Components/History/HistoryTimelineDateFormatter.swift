import Foundation

enum HistoryTimelineDateFormatter {
    private nonisolated(unsafe) static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private nonisolated(unsafe) static let rowTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private nonisolated(unsafe) static let rowDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    private nonisolated(unsafe) static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()

    static func rowTimestamp(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return rowTimeFormatter.string(from: date)
        }

        return rowDateFormatter.string(from: date)
    }

    static func relativeTimestamp(for date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    static func absoluteTimestamp(for date: Date) -> String {
        absoluteFormatter.string(from: date)
    }
}
