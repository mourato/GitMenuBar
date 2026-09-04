import Foundation

enum MainWindowPreferences {
    static let defaultAutoHideOnBlur = false
    static let defaultToggleShortcutUsesMouseMonitor = false

    static func inspectorColumnWidth(userDefaults: UserDefaults = .standard) -> Double {
        let storedWidth = userDefaults.double(forKey: AppPreferences.Keys.inspectorColumnWidth)
        guard storedWidth.isFinite,
              storedWidth >= Double(WorkbenchMetrics.inspectorMinimumWidth)
        else {
            return Double(WorkbenchMetrics.inspectorDefaultWidth)
        }

        return storedWidth
    }

    static func setInspectorColumnWidth(
        _ width: Double,
        userDefaults: UserDefaults = .standard
    ) {
        guard width.isFinite,
              width >= Double(WorkbenchMetrics.inspectorMinimumWidth) else { return }

        userDefaults.set(width, forKey: AppPreferences.Keys.inspectorColumnWidth)
    }

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
}
