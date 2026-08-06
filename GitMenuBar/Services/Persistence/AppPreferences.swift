import Foundation

enum AppPreferences {
    enum Keys {
        static let gitRepoPath = "gitRepoPath"
        static let recentRepoPaths = "recentRepoPaths"
        static let monitoredProjects = "monitoredProjects"
        static let monitoredProjectsSeeded = "monitoredProjectsSeeded"
        static let isProjectsSidebarCollapsed = "isProjectsSidebarCollapsed"
        static let isCleanProjectsGroupCollapsed = "isCleanProjectsGroupCollapsed"
        static let projectsSidebarWidth = "projectsSidebarWidth"
        static let isStagedSectionCollapsed = "isStagedSectionCollapsed"
        static let isUnstagedSectionCollapsed = "isUnstagedSectionCollapsed"
        static let isHistorySectionCollapsed = "isHistorySectionCollapsed"
        static let isUsageQuotaSectionCollapsed = "isUsageQuotaSectionCollapsed"
        static let autoHideMainWindowOnBlur = "autoHideMainWindowOnBlur"
        static let toggleShortcutUsesMouseMonitor = "toggleShortcutUsesMouseMonitor"
        static let hideCommitMessageField = "hideCommitMessageField"
        static let commitButtonAction = "commitButtonAction"
        static let appearanceMode = "appearanceMode"
        static let hasMigratedKeychainDomain = "hasMigratedKeychainDomain"
        static let aiCredentialMigrationVersion = "aiCredentialMigrationVersion"
        static let showAIUsageQuotas = "showAIUsageQuotas"
        static let showCodexUsageQuota = "showCodexUsageQuota"
        static let showCursorUsageQuota = "showCursorUsageQuota"
        static let showOpenRouterUsageQuota = "showOpenRouterUsageQuota"
    }

    enum AppearanceMode: String, CaseIterable, Identifiable {
        case systemDefault = "system"
        case light
        case dark

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .systemDefault:
                "System Default"
            case .light:
                "Light Mode"
            case .dark:
                "Dark Mode"
            }
        }

        static var defaultMode: AppearanceMode {
            .systemDefault
        }

        static func resolve(rawValue: String) -> AppearanceMode {
            AppearanceMode(rawValue: rawValue) ?? defaultMode
        }
    }

    enum CommitButtonAction: String, CaseIterable, Identifiable {
        case commit
        case commitAndPush

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .commit:
                "Commit only"
            case .commitAndPush:
                "Commit & Push"
            }
        }

        var buttonTitle: String {
            switch self {
            case .commit:
                "Commit"
            case .commitAndPush:
                "Commit & Push"
            }
        }

        static var defaultAction: CommitButtonAction {
            .commit
        }

        static func resolve(rawValue: String) -> CommitButtonAction {
            CommitButtonAction(rawValue: rawValue) ?? defaultAction
        }
    }
}
