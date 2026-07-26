import Foundation

/// Stable exit codes for the Companion CLI (`gitmenubar`).
public enum CompanionCLIExitCode: Int32, Sendable {
    case success = 0
    case notReady = 2
    case invalidRepository = 3
    case policyRejected = 4

    public static let operationalFailure: Int32 = 1

    public var description: String {
        switch self {
        case .success:
            return "Success"
        case .notReady:
            return "CLI not ready (missing AI provider, API key, or model)"
        case .invalidRepository:
            return "Invalid repository path scope"
        case .policyRejected:
            return "Commit message rejected by Message policy"
        }
    }
}
