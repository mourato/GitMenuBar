import Carbon.HIToolbox
@testable import GitMenuBar
import XCTest

@MainActor
final class GlobalShortcutManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var legacyDefaults: UserDefaults!
    private var legacySuiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "GitMenuBar.ShortcutsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        legacySuiteName = "GitMenuBar.LegacyShortcutsTests-\(UUID().uuidString)"
        legacyDefaults = UserDefaults(suiteName: legacySuiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        if let legacySuiteName {
            legacyDefaults.removePersistentDomain(forName: legacySuiteName)
        }
        defaults = nil
        suiteName = nil
        legacyDefaults = nil
        legacySuiteName = nil
        super.tearDown()
    }

    func testDefaultsAndResetRespectConfiguredBindings() {
        let backend = FakeHotkeyBackend()
        let manager = GlobalShortcutManager(defaults: defaults, backend: backend)

        XCTAssertEqual(
            manager.shortcut(for: .togglePopover),
            ShortcutConfig(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey) | UInt32(optionKey))
        )

        let custom = ShortcutConfig(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey))
        manager.setShortcut(custom, for: .commandPalette)
        XCTAssertEqual(manager.shortcut(for: .commandPalette), custom)

        manager.reset(.commandPalette)
        XCTAssertEqual(
            manager.shortcut(for: .commandPalette),
            ShortcutConfig(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey))
        )

        manager.setShortcut(nil, for: .togglePopover)
        XCTAssertNil(manager.shortcut(for: .togglePopover))
        manager.reset(.togglePopover)
        XCTAssertNotNil(manager.shortcut(for: .togglePopover))
    }

    func testConfigurationScopesRegistrationsAndSuspendsAndResumes() {
        let backend = FakeHotkeyBackend()
        let manager = GlobalShortcutManager(defaults: defaults, backend: backend)
        manager.configure([
            GlobalShortcutAction(id: .togglePopover, onKeyDown: {}),
            GlobalShortcutAction(id: .commit, onKeyDown: {})
        ])

        XCTAssertEqual(backend.registrations.map(\.id), ["togglePopover", "commit"])

        manager.setEnabled(false, for: [.commit])
        XCTAssertEqual(backend.registrations.map(\.id), ["togglePopover"])

        manager.suspend()
        XCTAssertTrue(backend.registrations.isEmpty)
        manager.resume()
        XCTAssertEqual(backend.registrations.map(\.id), ["togglePopover"])

        manager.setEnabled(true, for: [.commit])
        XCTAssertEqual(backend.registrations.map(\.id), ["togglePopover", "commit"])
    }

    func testMigratesKeyboardShortcutsValuesWithoutOverwritingNewStorage() throws {
        let oldValue = try JSONSerialization.data(withJSONObject: [
            "carbonKeyCode": kVK_ANSI_P,
            "carbonModifiers": Int(cmdKey)
        ])
        legacyDefaults.set(
            String(data: oldValue, encoding: .utf8),
            forKey: "KeyboardShortcuts_commandPalette"
        )
        legacyDefaults.set(false, forKey: "KeyboardShortcuts_togglePopover")

        let manager = GlobalShortcutManager(
            defaults: defaults,
            legacyDefaults: legacyDefaults,
            backend: FakeHotkeyBackend()
        )

        XCTAssertEqual(
            manager.shortcut(for: .commandPalette),
            ShortcutConfig(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey))
        )
        XCTAssertNil(manager.shortcut(for: .togglePopover))

        let newValue = ShortcutConfig(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(optionKey))
        let encodedNewValue = try JSONEncoder().encode(newValue)
        defaults.set(encodedNewValue, forKey: GlobalShortcutManager.storageKey(for: .commandPalette))
        legacyDefaults.set(String(data: oldValue, encoding: .utf8), forKey: "KeyboardShortcuts_commandPalette")

        let secondManager = GlobalShortcutManager(
            defaults: defaults,
            legacyDefaults: legacyDefaults,
            backend: FakeHotkeyBackend()
        )

        XCTAssertEqual(secondManager.shortcut(for: .commandPalette), newValue)
    }
}

@MainActor
private final class FakeHotkeyBackend: GlobalHotkeyBackend {
    private(set) var registrations: [HotkeyRegistration] = []

    var registeredHotkeyCount: Int {
        registrations.count
    }

    func registerAll(_ registrations: [HotkeyRegistration]) {
        self.registrations = registrations
    }

    func unregisterAll() {
        registrations = []
    }
}
