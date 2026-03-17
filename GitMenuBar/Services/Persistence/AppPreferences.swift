import Foundation

enum AppPreferences {
    enum Keys {
        static let gitRepoPath = "gitRepoPath"
        static let recentRepoPaths = "recentRepoPaths"
        static let showFullPathInRecents = "showFullPathInRecents"
        static let isStagedSectionCollapsed = "isStagedSectionCollapsed"
        static let isUnstagedSectionCollapsed = "isUnstagedSectionCollapsed"
        static let isHistorySectionCollapsed = "isHistorySectionCollapsed"
        static let autoHideMainWindowOnBlur = "autoHideMainWindowOnBlur"
        static let toggleShortcutUsesMouseMonitor = "toggleShortcutUsesMouseMonitor"
        static let appearanceMode = "appearanceMode"
        static let hasMigratedKeychainDomain = "hasMigratedKeychainDomain"
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
