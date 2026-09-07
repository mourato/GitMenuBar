import AppKit
import Carbon.HIToolbox
@preconcurrency import KeyboardShortcuts
import SwiftUI

/// Keycap-style shortcut recorder backed by `KeyboardShortcuts` storage.
struct ShortcutRecorderControl: View {
    let name: KeyboardShortcuts.Name
    var isInteractionEnabled: Bool = true
    var onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?

    @State private var isRecording = false
    @State private var shortcut: KeyboardShortcuts.Shortcut?
    @State private var eventMonitor: Any?
    @State private var previousShortcutsEnabled: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            startRecording()
        } label: {
            Group {
                if isRecording {
                    Text("Press keys…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(minWidth: 100)
                } else if let shortcut {
                    KeyCapGroupView(parts: shortcut.keyCapParts)
                } else {
                    EmptyShortcutCTAView(title: "Set shortcut")
                }
            }
        }
        .buttonStyle(ShortcutKeycapButtonStyle(isRecording: isRecording, reduceMotion: reduceMotion))
        .disabled(!isInteractionEnabled)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Click to record a shortcut.")
        .onAppear(perform: refreshShortcut)
        .onDisappear(perform: stopRecording)
        .onChange(of: isInteractionEnabled) { _, enabled in
            if !enabled {
                stopRecording()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange")
            )
        ) { notification in
            guard
                let changed = notification.userInfo?["name"] as? KeyboardShortcuts.Name,
                changed == name
            else {
                return
            }
            refreshShortcut()
        }
    }

    private var accessibilityValue: String {
        if isRecording {
            return "Press keys…"
        }
        if let shortcut {
            return shortcut.description
        }
        return "Set shortcut"
    }

    private func refreshShortcut() {
        shortcut = KeyboardShortcuts.getShortcut(for: name)
    }

    private func startRecording() {
        guard !isRecording, isInteractionEnabled else { return }
        isRecording = true
        previousShortcutsEnabled = KeyboardShortcuts.isEnabled
        KeyboardShortcuts.isEnabled = false

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }

            if isClearShortcutEvent(event) {
                saveShortcut(nil)
                stopRecording()
                return nil
            }

            let hasUsableModifiers = !event.modifierFlags
                .intersection([.command, .control, .option, .shift])
                .subtracting([.shift])
                .isEmpty
            guard
                hasUsableModifiers || isFunctionKeyCode(event.keyCode),
                let newShortcut = KeyboardShortcuts.Shortcut(event: event)
            else {
                NSSound.beep()
                return nil
            }

            saveShortcut(newShortcut)
            stopRecording()
            return nil
        }
    }

    private func isClearShortcutEvent(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case kVK_Delete, kVK_ForwardDelete:
            event.modifierFlags
                .isDisjoint(with: [.command, .control, .option, .shift])
        default:
            false
        }
    }

    private func isFunctionKeyCode(_ keyCode: UInt16) -> Bool {
        switch Int(keyCode) {
        case kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
             kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20:
            true
        default:
            false
        }
    }

    private func saveShortcut(_ newShortcut: KeyboardShortcuts.Shortcut?) {
        KeyboardShortcuts.setShortcut(newShortcut, for: name)
        shortcut = newShortcut
        onChange?(newShortcut)
    }

    private func stopRecording() {
        guard isRecording || eventMonitor != nil || previousShortcutsEnabled != nil else { return }
        isRecording = false
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        if let previousShortcutsEnabled {
            KeyboardShortcuts.isEnabled = previousShortcutsEnabled
            self.previousShortcutsEnabled = nil
        }
    }
}

struct EmptyShortcutCTAView: View {
    let title: String
    var minWidth: CGFloat = 104

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "return")
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(Color.accentColor)
        .frame(minWidth: minWidth)
    }
}

/// Transparent button style; keycaps provide the idle affordance, accent chrome marks recording.
struct ShortcutKeycapButtonStyle: ButtonStyle {
    let isRecording: Bool
    var reduceMotion: Bool = false
    // ponytail: gugu used fixed 6/4 padding and radius 7; mapped to the matching Workbench tokens.
    var horizontalPadding: CGFloat = WorkbenchMetrics.chipSpacing
    var verticalPadding: CGFloat = WorkbenchMetrics.microSpacing

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous)
                    .fill(isRecording ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous)
                    .strokeBorder(
                        isRecording ? Color.accentColor.opacity(0.5) : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1.0)
            .animation(
                reduceMotion ? nil : WorkbenchMotion.micro,
                value: configuration.isPressed
            )
    }
}

extension KeyboardShortcuts.Shortcut {
    /// Individual key parts for keycap-style rendering (⌃ ⌥ ⇧ ⌘ order).
    @MainActor
    var keyCapParts: [String] {
        var parts: [String] = []
        if modifiers.contains(.control) {
            parts.append("⌃")
        }
        if modifiers.contains(.option) {
            parts.append("⌥")
        }
        if modifiers.contains(.shift) {
            parts.append("⇧")
        }
        if modifiers.contains(.command) {
            parts.append("⌘")
        }
        if modifiers.contains(.function) {
            parts.append("fn")
        }

        var keyLabel = description
        for symbol in ["⌃", "⌥", "⇧", "⌘", "🌐\u{FE0E}", "fn"] {
            keyLabel = keyLabel.replacingOccurrences(of: symbol, with: "")
        }
        parts.append(keyLabel.isEmpty ? "?" : keyLabel)
        return parts
    }
}

#Preview("Shortcut Recorder") {
    Form {
        Section {
            LabeledContent("Open Window (global)") {
                ShortcutRecorderControl(name: .togglePopover)
            }
            LabeledContent("Command Palette") {
                ShortcutRecorderControl(name: .commandPalette)
            }
            LabeledContent("Empty") {
                EmptyShortcutCTAView(title: "Set shortcut")
            }
        } header: {
            SettingsFormSectionHeader(title: "Keyboard Shortcuts", icon: "keyboard")
        }
    }
    .formStyle(.grouped)
    .frame(width: 560, height: 280)
}
