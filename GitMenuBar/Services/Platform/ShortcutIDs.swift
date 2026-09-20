import Carbon.HIToolbox

enum GlobalShortcutID: String, CaseIterable, Hashable, Sendable {
    case togglePopover
    case commandPalette
    case commit
    case sync
    case atomicCommits
    case push
    case branchManagement
    case createBranch

    var defaultShortcut: ShortcutConfig {
        switch self {
        case .togglePopover:
            ShortcutConfig(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey) | UInt32(optionKey))
        case .commandPalette:
            ShortcutConfig(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey))
        case .commit:
            ShortcutConfig(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey) | UInt32(optionKey))
        case .sync:
            ShortcutConfig(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey) | UInt32(optionKey))
        case .atomicCommits:
            ShortcutConfig(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey) | UInt32(shiftKey))
        case .push:
            ShortcutConfig(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey) | UInt32(optionKey))
        case .branchManagement:
            ShortcutConfig(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(cmdKey) | UInt32(optionKey))
        case .createBranch:
            ShortcutConfig(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey) | UInt32(optionKey))
        }
    }
}
