import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let togglePopover = Self(
        "togglePopover",
        default: .init(.g, modifiers: [.option, .command])
    )

    static let commandPalette = Self(
        "commandPalette",
        default: .init(.k, modifiers: [.command])
    )

    static let commit = Self(
        "commit",
        default: .init(.c, modifiers: [.option, .command])
    )

    static let sync = Self(
        "sync",
        default: .init(.s, modifiers: [.option, .command])
    )

    static let push = Self(
        "push",
        default: .init(.p, modifiers: [.option, .command])
    )

    static let branchManagement = Self(
        "branchManagement",
        default: .init(.b, modifiers: [.option, .command])
    )

    static let createBranch = Self(
        "createBranch",
        default: .init(.n, modifiers: [.option, .command])
    )
}
