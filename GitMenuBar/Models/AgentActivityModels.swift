import Foundation

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

    var fallbackIcon: LucideIconName {
        switch self {
        case .claudeCode: .cloud
        case .codex: .cpu
        case .cursor: .mousePointerClick
        case .opencode: .terminal
        case .antigravity: .sparkles
        }
    }
}

enum AgentActivityStatus: Equatable, Sendable {
    case running
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

struct AgentProjectActivity: Equatable, Identifiable, Sendable {
    static func lead(in activities: [Self]) -> Self? {
        activities.first(where: \.status.isRunning) ?? activities.first
    }

    var id: AgentHarnessID {
        harness
    }

    let harness: AgentHarnessID
    let status: AgentActivityStatus

    var accessibilityDescription: String {
        "\(harness.displayName) agent \(status.isRunning ? "active" : "recent")"
    }
}
