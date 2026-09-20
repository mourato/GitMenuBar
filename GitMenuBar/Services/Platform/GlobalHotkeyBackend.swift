import Foundation

struct HotkeyRegistration {
    let id: String
    let keyCode: UInt32
    let modifiers: UInt32
    let onKeyDown: @MainActor () -> Void
}

@MainActor
protocol GlobalHotkeyBackend: AnyObject {
    var registeredHotkeyCount: Int { get }

    func registerAll(_ registrations: [HotkeyRegistration])
    func unregisterAll()
}
