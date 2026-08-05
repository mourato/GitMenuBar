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
        static let autoHideMainWindowOnBlur = "autoHideMainWindowOnBlur"
        static let toggleShortcutUsesMouseMonitor = "toggleShortcutUsesMouseMonitor"
        static let hideCommitMessageField = "hideCommitMessageField"
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
}
