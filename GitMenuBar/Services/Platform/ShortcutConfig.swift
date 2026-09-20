import AppKit
import Carbon.HIToolbox

struct ShortcutConfig: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32

    private static let supportedModifiers = UInt32(cmdKey)
        | UInt32(shiftKey)
        | UInt32(optionKey)
        | UInt32(controlKey)

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    @MainActor
    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }

        var carbonModifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) {
            carbonModifiers |= UInt32(cmdKey)
        }
        if event.modifierFlags.contains(.shift) {
            carbonModifiers |= UInt32(shiftKey)
        }
        if event.modifierFlags.contains(.option) {
            carbonModifiers |= UInt32(optionKey)
        }
        if event.modifierFlags.contains(.control) {
            carbonModifiers |= UInt32(controlKey)
        }

        let config = Self(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers)
        guard config.isUsable else { return nil }
        self = config
    }

    var isUsable: Bool {
        guard keyCode <= UInt32(UInt16.max),
              modifiers & ~Self.supportedModifiers == 0
        else {
            return false
        }

        return modifiers & Self.supportedModifiers != 0 || Self.isFunctionKeyCode(keyCode)
    }

    var displayParts: [String] {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 {
            parts.append("⌃")
        }
        if modifiers & UInt32(optionKey) != 0 {
            parts.append("⌥")
        }
        if modifiers & UInt32(shiftKey) != 0 {
            parts.append("⇧")
        }
        if modifiers & UInt32(cmdKey) != 0 {
            parts.append("⌘")
        }
        parts.append(Self.keyCodeToDisplayString(keyCode))
        return parts
    }

    var description: String {
        displayParts.joined()
    }

    static func isFunctionKeyCode(_ keyCode: UInt32) -> Bool {
        switch Int(keyCode) {
        case kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
             kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20:
            true
        default:
            false
        }
    }

    private static let keyLabels: [Int: String] = [
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
        kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
        kVK_Space: "Space", kVK_Return: "↩", kVK_ANSI_KeypadEnter: "↩", kVK_Tab: "⇥",
        kVK_Delete: "⌫", kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'",
        kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
        kVK_ANSI_Backslash: "\\", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_Grave: "\u{60}",
        kVK_ANSI_KeypadDecimal: ".", kVK_ANSI_KeypadMultiply: "*", kVK_ANSI_KeypadPlus: "+",
        kVK_ANSI_KeypadDivide: "/", kVK_ANSI_KeypadMinus: "-", kVK_ANSI_KeypadEquals: "=",
        kVK_ANSI_Keypad0: "0", kVK_ANSI_Keypad1: "1", kVK_ANSI_Keypad2: "2", kVK_ANSI_Keypad3: "3",
        kVK_ANSI_Keypad4: "4", kVK_ANSI_Keypad5: "5", kVK_ANSI_Keypad6: "6", kVK_ANSI_Keypad7: "7",
        kVK_ANSI_Keypad8: "8", kVK_ANSI_Keypad9: "9",
        kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞",
        kVK_PageDown: "⇟"
    ]

    private static func keyCodeToDisplayString(_ keyCode: UInt32) -> String {
        keyLabels[Int(keyCode), default: "?"]
    }
}
