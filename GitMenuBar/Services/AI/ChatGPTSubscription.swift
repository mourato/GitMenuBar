import Foundation

enum ChatGPTSubscription {
    enum Phase: Equatable, Sendable {
        case idle
        case starting
        case signedOut
        case connected
        case unavailable(String)
        case failed(String)

        var title: String {
            switch self {
            case .idle: "Not checked"
            case .starting: "Checking account…"
            case .signedOut: "Not signed in"
            case .connected: "Connected"
            case .unavailable: "Codex CLI unavailable"
            case .failed: "Connection failed"
            }
        }
    }

    struct Account: Equatable, Sendable {
        let email: String?
        let plan: String

        var planTitle: String {
            switch plan.lowercased() {
            case "free": "Free"
            case "go": "Go"
            case "plus": "Plus"
            case "pro": "Pro"
            case "prolite": "Pro Lite"
            case "team": "Team"
            case "business", "self_serve_business_usage_based": "Business"
            case "enterprise", "enterprise_cbp_usage_based": "Enterprise"
            case "edu": "Edu"
            default: "ChatGPT"
            }
        }
    }

    struct Effort: Equatable, Identifiable, Sendable {
        let id: String
        let detail: String?

        var title: String {
            switch id {
            case "xhigh": "Extra high"
            case "minimal": "Minimal"
            default: id.prefix(1).uppercased() + id.dropFirst()
            }
        }
    }

    struct Model: Equatable, Identifiable, Sendable {
        let id: String
        let name: String
        let efforts: [Effort]
        let defaultEffort: String?
        let isDefault: Bool

        func resolvedEffort(_ preferred: String?) -> String? {
            guard !efforts.isEmpty else { return nil }
            if let preferred, efforts.contains(where: { $0.id == preferred }) {
                return preferred
            }
            if let defaultEffort, efforts.contains(where: { $0.id == defaultEffort }) {
                return defaultEffort
            }
            return efforts.first?.id
        }
    }
}
