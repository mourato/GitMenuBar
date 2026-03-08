import KeyboardShortcuts
import SwiftUI

struct KeyboardShortcutsSection: View {
    var body: some View {
        SettingsSection(title: "Keyboard Shortcuts", systemImage: "keyboard") {
            shortcutRow("Open Popover", name: .togglePopover)
            shortcutRow("Commit", name: .commit)
            shortcutRow("Sync", name: .sync)

            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    KeyboardShortcuts.reset(.togglePopover)
                    KeyboardShortcuts.reset(.commit)
                    KeyboardShortcuts.reset(.sync)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
            }
        }
    }

    private func shortcutRow(_ title: String, name: KeyboardShortcuts.Name) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11))
            Spacer()
            KeyboardShortcuts.Recorder(for: name)
                .labelsHidden()
        }
    }
}
