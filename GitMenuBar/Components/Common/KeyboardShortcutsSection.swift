import KeyboardShortcuts
import SwiftUI

struct KeyboardShortcutsSection: View {
    var body: some View {
        SettingsSection(title: "Keyboard Shortcuts", systemImage: "keyboard") {
            shortcutRow("Open Window (global)", name: .togglePopover)
            shortcutRow("Command Palette", name: .commandPalette)
            shortcutRow("Commit", name: .commit)
            shortcutRow("Sync", name: .sync)

            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    KeyboardShortcuts.reset(.togglePopover)
                    KeyboardShortcuts.reset(.commandPalette)
                    KeyboardShortcuts.reset(.commit)
                    KeyboardShortcuts.reset(.sync)
                }
                .buttonStyle(.borderless)
                .font(MacChromeTypography.detail)
            }
        }
    }

    private func shortcutRow(_ title: String, name: KeyboardShortcuts.Name) -> some View {
        HStack {
            Text(title)
                .font(MacChromeTypography.body)
            Spacer()
            KeyboardShortcuts.Recorder(for: name)
                .labelsHidden()
        }
    }
}

#Preview("Keyboard Shortcuts") {
    KeyboardShortcutsSection()
        .padding()
        .frame(width: 360)
}
