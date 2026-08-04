import Foundation

enum AppPreferences {
    enum Keys {
        static let gitRepoPath = "gitRepoPath"
        static let recentRepoPaths = "recentRepoPaths"
        static let monitoredProjects = "monitoredProjects"
        static let monitoredProjectsSeeded = "monitoredProjectsSeeded"
        static let isProjectsSidebarCollapsed = "isProjectsSidebarCollapsed"
        static let projectsSidebarWidth = "projectsSidebarWidth"
        static let isStagedSectionCollapsed = "isStagedSectionCollapsed"
        static let isUnstagedSectionCollapsed = "isUnstagedSectionCollapsed"
        static let isHistorySectionCollapsed = "isHistorySectionCollapsed"
        static let autoHideMainWindowOnBlur = "autoHideMainWindowOnBlur"
        static let toggleShortcutUsesMouseMonitor = "toggleShortcutUsesMouseMonitor"
        static let hideCommitMessageField = "hideCommitMessageField"
        static let appearanceMode = "appearanceMode"
        static let hasMigratedKeychainDomain = "hasMigratedKeychainDomain"
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
                return "System Default"
            case .light:
                return "Light Mode"
            case .dark:
                return "Dark Mode"
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
