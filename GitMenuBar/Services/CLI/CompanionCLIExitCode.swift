import Foundation

/// Stable exit codes for the Companion CLI (`gitmenubar`).
public enum CompanionCLIExitCode: Int32, Sendable {
    case success = 0
    case operationalFailure = 1
    case notReady = 2
    case invalidRepository = 3
    case policyRejected = 4

    public var description: String {
        switch self {
        case .success:
            "Success"
        case .operationalFailure:
            "Operational failure"
        case .notReady:
            "CLI not ready (missing AI provider, API key, or model)"
        case .invalidRepository:
            "Invalid repository path scope"
        case .policyRejected:
            "Commit message rejected by Message policy"
        }
    }
}
