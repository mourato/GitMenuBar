import SwiftUI

struct KeyboardShortcutsSection: View {
    let manager: GlobalShortcutManager

    var body: some View {
        shortcutRow("Open Window (global)", id: .togglePopover)
        shortcutRow("Command Palette", id: .commandPalette)
        shortcutRow("Commit", id: .commit)
        shortcutRow("Sync", id: .sync)
        shortcutRow("Split Commits", id: .atomicCommits)

        Button("Reset to Defaults") {
            manager.reset([.togglePopover, .commandPalette, .commit, .sync, .atomicCommits])
        }
        .buttonStyle(.borderless)
        .font(WorkbenchTypography.detail)
    }

    private func shortcutRow(_ title: String, id: GlobalShortcutID) -> some View {
        LabeledContent(title) {
            ShortcutRecorderControl(id: id, manager: manager)
                .accessibilityLabel(title)
        }
    }
}

#Preview("Keyboard Shortcuts") {
    let defaults = UserDefaults(suiteName: "GitMenuBar.KeyboardShortcutsSectionPreview") ?? .standard
    Form {
        Section {
            KeyboardShortcutsSection(manager: GlobalShortcutManager(defaults: defaults))
        } header: {
            SettingsFormSectionHeader(title: "Keyboard Shortcuts", icon: "keyboard")
        }
    }
    .formStyle(.grouped)
    .frame(width: 560, height: 280)
}
