import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Keycap-style shortcut recorder backed by the app-owned shortcut manager.
struct ShortcutRecorderControl: View {
    let id: GlobalShortcutID
    let manager: GlobalShortcutManager
    var isInteractionEnabled: Bool = true
    var onChange: ((ShortcutConfig?) -> Void)?

    @State private var isRecording = false
    @State private var shortcut: ShortcutConfig?
    @State private var eventMonitor: Any?
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
                    KeyCapGroupView(parts: shortcut.displayParts)
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
            NotificationCenter.default.publisher(for: GlobalShortcutManager.shortcutDidChange)
        ) { notification in
            guard
                let changed = notification.userInfo?["id"] as? GlobalShortcutID,
                changed == id
            else {
                return
            }
            refreshShortcut()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)
        ) { _ in
            stopRecording()
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
        shortcut = manager.shortcut(for: id)
    }

    private func startRecording() {
        guard !isRecording, isInteractionEnabled else { return }
        isRecording = true
        manager.suspend()

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
                hasUsableModifiers || ShortcutConfig.isFunctionKeyCode(UInt32(event.keyCode)),
                let newShortcut = ShortcutConfig(event: event)
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

    private func saveShortcut(_ newShortcut: ShortcutConfig?) {
        manager.setShortcut(newShortcut, for: id)
        shortcut = newShortcut
        onChange?(newShortcut)
    }

    private func stopRecording() {
        guard isRecording || eventMonitor != nil else { return }
        isRecording = false
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        manager.resume()
    }
}

struct EmptyShortcutCTAView: View {
    let title: String
    var minWidth: CGFloat = 104

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "return")
                .accessibilityHidden(true)
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

#Preview("Shortcut Recorder") {
    let defaults = UserDefaults(suiteName: "GitMenuBar.ShortcutRecorderPreview") ?? .standard
    let manager = GlobalShortcutManager(defaults: defaults)

    Form {
        Section {
            LabeledContent("Open Window (global)") {
                ShortcutRecorderControl(id: .togglePopover, manager: manager)
            }
            LabeledContent("Command Palette") {
                ShortcutRecorderControl(id: .commandPalette, manager: manager)
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
