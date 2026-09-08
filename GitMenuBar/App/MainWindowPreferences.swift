import Foundation

enum MainWindowPreferences {
    static let defaultAutoHideOnBlur = false
    static let defaultToggleShortcutUsesMouseMonitor = false
    static let defaultShowDockIcon = true
    static let defaultShowMenuBarIcon = true

    static func isAutoHideOnBlurEnabled(userDefaults: UserDefaults = .standard) -> Bool {
        guard userDefaults.object(forKey: AppPreferences.Keys.autoHideMainWindowOnBlur) != nil else {
            return defaultAutoHideOnBlur
        }

        return userDefaults.bool(forKey: AppPreferences.Keys.autoHideMainWindowOnBlur)
    }

    static func setAutoHideOnBlurEnabled(_ enabled: Bool, userDefaults: UserDefaults = .standard) {
        userDefaults.set(enabled, forKey: AppPreferences.Keys.autoHideMainWindowOnBlur)
    }

    static func isToggleShortcutUsingMouseMonitorEnabled(
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        guard userDefaults.object(forKey: AppPreferences.Keys.toggleShortcutUsesMouseMonitor) != nil else {
            return defaultToggleShortcutUsesMouseMonitor
        }

        return userDefaults.bool(forKey: AppPreferences.Keys.toggleShortcutUsesMouseMonitor)
    }

    static func setToggleShortcutUsingMouseMonitorEnabled(
        _ enabled: Bool,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(enabled, forKey: AppPreferences.Keys.toggleShortcutUsesMouseMonitor)
    }

    static func isShowDockIconEnabled(userDefaults: UserDefaults = .standard) -> Bool {
        guard userDefaults.object(forKey: AppPreferences.Keys.showDockIcon) != nil else {
            return defaultShowDockIcon
        }

        return userDefaults.bool(forKey: AppPreferences.Keys.showDockIcon)
    }

    static func setShowDockIconEnabled(_ enabled: Bool, userDefaults: UserDefaults = .standard) {
        userDefaults.set(enabled, forKey: AppPreferences.Keys.showDockIcon)
    }

    static func isShowMenuBarIconEnabled(userDefaults: UserDefaults = .standard) -> Bool {
        guard userDefaults.object(forKey: AppPreferences.Keys.showMenuBarIcon) != nil else {
            return defaultShowMenuBarIcon
        }

        return userDefaults.bool(forKey: AppPreferences.Keys.showMenuBarIcon)
    }

    static func setShowMenuBarIconEnabled(_ enabled: Bool, userDefaults: UserDefaults = .standard) {
        userDefaults.set(enabled, forKey: AppPreferences.Keys.showMenuBarIcon)
    }
}
