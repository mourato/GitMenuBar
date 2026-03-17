import Foundation

enum MainWindowPreferences {
    static let defaultAutoHideOnBlur = false

    static func isAutoHideOnBlurEnabled(userDefaults: UserDefaults = .standard) -> Bool {
        guard userDefaults.object(forKey: AppPreferences.Keys.autoHideMainWindowOnBlur) != nil else {
            return defaultAutoHideOnBlur
        }

        return userDefaults.bool(forKey: AppPreferences.Keys.autoHideMainWindowOnBlur)
    }

    static func setAutoHideOnBlurEnabled(_ enabled: Bool, userDefaults: UserDefaults = .standard) {
        userDefaults.set(enabled, forKey: AppPreferences.Keys.autoHideMainWindowOnBlur)
    }
}
