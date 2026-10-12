import Foundation

/// Canonical identifier for coding agent harnesses.
enum AgentHarnessID: String, CaseIterable, Sendable, Identifiable {
    case codex = "Codex"
    case antigravity = "Antigravity"
    case opencode = "OpenCode"
    case cursor = "Cursor"
    case claudeCode = "Claude Code"

    var id: String {
        rawValue
    }

    var displayName: String {
        rawValue
    }

    var iconResourceName: String {
        switch self {
        case .codex: "ProviderIcon-codex"
        case .antigravity: "ProviderIcon-antigravity"
        case .opencode: "ProviderIcon-opencode"
        case .cursor: "ProviderIcon-cursor"
        case .claudeCode: "ProviderIcon-claude-code"
        }
    }

    var fallbackSymbol: String {
        switch self {
        case .claudeCode: "cloud.fill"
        case .codex: "cpu"
        case .cursor: "cursorarrow.rays"
        case .opencode: "terminal.fill"
        case .antigravity: "sparkles"
        }
    }

    /// Tint for the harness icon; nil keeps the neutral primary and secondary styles.
    var brandColorHex: UInt32? {
        switch self {
        case .claudeCode: 0xD97757
        case .codex: 0x71A597
        case .opencode: 0xF49CBB
        case .antigravity: 0x4A85EF
        case .cursor: nil
        }
    }
}

/// Activity state for an agent within a project.
enum AgentActivityStatus: Equatable, Sendable {
    /// Actively running process with working directory matching the project.
    case running
    /// Recent session activity recorded within the project.
    case recent(Date)

    var isRunning: Bool {
        if case .running = self {
            return true
        }
        return false
    }

    var lastActivityDate: Date? {
        if case let .recent(date) = self {
            return date
        }
        return nil
    }
}

/// Snapshot of an agent's presence or activity on a specific project.
struct AgentProjectActivity: Equatable, Identifiable, Sendable {
    var id: AgentHarnessID {
        harness
    }

    let harness: AgentHarnessID
    let status: AgentActivityStatus

    var accessibilityDescription: String {
        "\(harness.displayName) agent \(status.isRunning ? "active" : "recent")"
    }
}
