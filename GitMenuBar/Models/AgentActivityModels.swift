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
