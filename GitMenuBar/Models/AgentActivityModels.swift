import Foundation

/// Canonical identifier for coding agent harnesses.
public enum AgentHarnessID: String, CaseIterable, Sendable, Identifiable {
    case codex = "Codex"
    case antigravity = "Antigravity"
    case opencode = "OpenCode"
    case cursor = "Cursor"
    case claudeCode = "Claude Code"

    public var id: String {
        rawValue
    }

    public var displayName: String {
        rawValue
    }

    public var iconResourceName: String {
        switch self {
        case .codex: "ProviderIcon-codex"
        case .antigravity: "ProviderIcon-antigravity"
        case .opencode: "ProviderIcon-opencode"
        case .cursor: "ProviderIcon-cursor"
        case .claudeCode: "ProviderIcon-claude-code"
        }
    }

    public var fallbackSymbol: String {
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
public enum AgentActivityStatus: Equatable, Sendable {
    /// Actively running process with working directory matching the project.
    case running
    /// Recent session activity recorded within the project.
    case recent(Date)

    public var isRunning: Bool {
        if case .running = self {
            return true
        }
        return false
    }

    public var lastActivityDate: Date? {
        if case let .recent(date) = self {
            return date
        }
        return nil
    }
}

/// Snapshot of an agent's presence or activity on a specific project.
public struct AgentProjectActivity: Equatable, Identifiable, Sendable {
    public var id: AgentHarnessID {
        harness
    }

    public let harness: AgentHarnessID
    public let status: AgentActivityStatus

    public init(harness: AgentHarnessID, status: AgentActivityStatus) {
        self.harness = harness
        self.status = status
    }

    public var accessibilityDescription: String {
        "\(harness.displayName) agent \(status.isRunning ? "active" : "recent")"
    }
}
