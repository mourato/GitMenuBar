import Carbon.HIToolbox
import Foundation

struct GlobalShortcutAction {
    let id: GlobalShortcutID
    let onKeyDown: @MainActor () -> Void
}

@MainActor
final class GlobalShortcutManager {
    static let shortcutDidChange = Notification.Name("GitMenuBar.shortcutDidChange")
    private static let legacyStoragePrefix = "KeyboardShortcuts_"
    private static let migrationMarker = "GitMenuBar.shortcutsMigratedFromKeyboardShortcuts.v1"

    private struct LegacyShortcut: Codable {
        let carbonKeyCode: Int
        let carbonModifiers: Int
    }

    private let defaults: UserDefaults
    private let backend: any GlobalHotkeyBackend
    private var actions: [GlobalShortcutID: @MainActor () -> Void] = [:]
    private var enabledIDs = Set<GlobalShortcutID>()
    private var isSuspended = false

    init(
        defaults: UserDefaults = .standard,
        legacyDefaults: UserDefaults? = nil,
        backend: any GlobalHotkeyBackend = CarbonGlobalHotkeyBackend()
    ) {
        self.defaults = defaults
        self.backend = backend
        migrateLegacyShortcuts(from: legacyDefaults ?? defaults)
    }

    static var allIDs: [GlobalShortcutID] {
        Array(GlobalShortcutID.allCases)
    }

    nonisolated static func storageKey(for id: GlobalShortcutID) -> String {
        "GitMenuBar.shortcut." + id.rawValue
    }

    func shortcut(for id: GlobalShortcutID) -> ShortcutConfig? {
        let key = Self.storageKey(for: id)
        if defaults.object(forKey: key) as? Bool == false {
            return nil
        }
        if let data = defaults.data(forKey: key),
           let shortcut = try? JSONDecoder().decode(ShortcutConfig.self, from: data),
           shortcut.isUsable
        {
            return shortcut
        }
        return id.defaultShortcut
    }

    func setShortcut(_ shortcut: ShortcutConfig?, for id: GlobalShortcutID) {
        guard shortcut == nil || shortcut?.isUsable == true else { return }

        let key = Self.storageKey(for: id)
        if let shortcut {
            defaults.set(try? JSONEncoder().encode(shortcut), forKey: key)
        } else {
            defaults.set(false, forKey: key)
        }
        notifyChange(for: id)
        refresh()
    }

    func reset(_ id: GlobalShortcutID) {
        defaults.removeObject(forKey: Self.storageKey(for: id))
        notifyChange(for: id)
        refresh()
    }

    func reset(_ ids: [GlobalShortcutID]) {
        ids.forEach(reset)
    }

    func configure(
        _ actions: [GlobalShortcutAction],
        enabledIDs: Set<GlobalShortcutID>? = nil
    ) {
        self.actions = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0.onKeyDown) })
        self.enabledIDs = enabledIDs ?? Set(actions.map(\.id))
        refresh()
    }

    func setEnabled(_ enabled: Bool, for ids: [GlobalShortcutID]) {
        if enabled {
            enabledIDs.formUnion(ids)
        } else {
            enabledIDs.subtract(ids)
        }
        refresh()
    }

    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        backend.unregisterAll()
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        refresh()
    }

    func stop() {
        backend.unregisterAll()
    }

    private func refresh() {
        guard !isSuspended else { return }

        let registrations = Self.allIDs.compactMap { id -> HotkeyRegistration? in
            guard enabledIDs.contains(id),
                  let action = actions[id],
                  let shortcut = shortcut(for: id)
            else {
                return nil
            }
            return HotkeyRegistration(
                id: id.rawValue,
                keyCode: shortcut.keyCode,
                modifiers: shortcut.modifiers,
                onKeyDown: action
            )
        }
        backend.registerAll(registrations)
    }

    private func notifyChange(for id: GlobalShortcutID) {
        NotificationCenter.default.post(
            name: Self.shortcutDidChange,
            object: self,
            userInfo: ["id": id]
        )
    }

    private func migrateLegacyShortcuts(from legacyDefaults: UserDefaults) {
        guard !defaults.bool(forKey: Self.migrationMarker) else { return }

        for id in Self.allIDs where defaults.object(forKey: Self.storageKey(for: id)) == nil {
            let legacyKey = Self.legacyStoragePrefix + id.rawValue
            guard let stored = legacyDefaults.object(forKey: legacyKey) else { continue }

            if stored as? Bool == false {
                defaults.set(false, forKey: Self.storageKey(for: id))
                continue
            }
            if stored is Bool {
                continue
            }

            guard let raw = legacyDefaults.string(forKey: legacyKey),
                  let data = raw.data(using: .utf8),
                  let legacy = try? JSONDecoder().decode(LegacyShortcut.self, from: data)
            else {
                continue
            }

            let shortcut = ShortcutConfig(
                keyCode: UInt32(clamping: legacy.carbonKeyCode),
                modifiers: UInt32(clamping: legacy.carbonModifiers)
            )
            if shortcut.isUsable {
                defaults.set(try? JSONEncoder().encode(shortcut), forKey: Self.storageKey(for: id))
            }
        }

        defaults.set(true, forKey: Self.migrationMarker)
    }
}
