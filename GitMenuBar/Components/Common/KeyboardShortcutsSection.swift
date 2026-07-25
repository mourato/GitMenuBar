import KeyboardShortcuts
import SwiftUI

struct KeyboardShortcutsSection: View {
    var body: some View {
        shortcutRow("Open Window (global)", name: .togglePopover)
        shortcutRow("Command Palette", name: .commandPalette)
        shortcutRow("Commit", name: .commit)
        shortcutRow("Sync", name: .sync)

        Button("Reset to Defaults") {
            KeyboardShortcuts.reset(.togglePopover)
            KeyboardShortcuts.reset(.commandPalette)
            KeyboardShortcuts.reset(.commit)
            KeyboardShortcuts.reset(.sync)
        }
        .buttonStyle(.borderless)
        .font(WorkbenchTypography.detail)
    }

    private func shortcutRow(_ title: String, name: KeyboardShortcuts.Name) -> some View {
        LabeledContent(title) {
            KeyboardShortcuts.Recorder(for: name)
                .labelsHidden()
        }
    }
}

#Preview("Keyboard Shortcuts") {
    Form {
        Section {
            KeyboardShortcutsSection()
        } header: {
            SettingsFormSectionHeader(title: "Keyboard Shortcuts", icon: "keyboard")
        }
    }
    .formStyle(.grouped)
    .frame(width: 560, height: 280)
}
