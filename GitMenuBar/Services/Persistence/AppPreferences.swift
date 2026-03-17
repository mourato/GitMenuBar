import Foundation

enum AppPreferences {
    enum Keys {
        static let gitRepoPath = "gitRepoPath"
        static let recentRepoPaths = "recentRepoPaths"
        static let showSettings = "showSettings"
        static let showFullPathInRecents = "showFullPathInRecents"
        static let isStagedSectionCollapsed = "isStagedSectionCollapsed"
        static let isUnstagedSectionCollapsed = "isUnstagedSectionCollapsed"
        static let autoHideMainWindowOnBlur = "autoHideMainWindowOnBlur"
        static let hasMigratedKeychainDomain = "hasMigratedKeychainDomain"
    }
}
