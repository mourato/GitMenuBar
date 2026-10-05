import Foundation

/// Failures presented by Git operations, independent of NSError domain and numeric codes.
enum GitOperationError: LocalizedError {
    case noRepository
    case commandFailed(String)
    case invalidInput(String)
    case invalidState(String)
    case conflict(String)

    var errorDescription: String? {
        switch self {
        case .noRepository:
            "No repository path configured"
        case let .commandFailed(message), let .invalidInput(message),
             let .invalidState(message), let .conflict(message):
            message
        }
    }
}
