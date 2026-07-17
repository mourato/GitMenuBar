import CoreGraphics
import SwiftUI

// MARK: - Press feedback

struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(
                MacChromeMotion.adaptive(MacChromeMotion.press, usesReducedMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

extension View {
    func pressable() -> some View {
        modifier(PressableModifier())
    }
}

private struct PressableModifier: ViewModifier {
    @GestureState private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(
                MacChromeMotion.adaptive(MacChromeMotion.press, usesReducedMotion: reduceMotion),
                value: isPressed
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in state = true }
            )
    }
}

// MARK: - Adaptive motion

struct AdaptiveMotionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    func body(content: Content) -> some View {
        content
            .transaction { transaction in
                if reduceMotion {
                    transaction.animation = MacChromeMotion.reduceMotion
                }
            }
    }
}

extension View {
    func adaptiveMotion() -> some View {
        modifier(AdaptiveMotionModifier())
    }
}

enum MacChromeMetrics {
    static let compactSpacing: CGFloat = 8
    static let sectionSpacing: CGFloat = 12
    static let groupSpacing: CGFloat = 20
    static let panelPadding: CGFloat = 16
    static let windowPadding: CGFloat = 20
    static let rowCornerRadius: CGFloat = 8
    static let cornerRadius: CGFloat = 10
    static let largeCornerRadius: CGFloat = 14
}

enum MacChromeTypography {
    static var windowTitle: Font {
        .headline
    }

    static var sectionLabel: Font {
        .subheadline.weight(.semibold)
    }

    static var body: Font {
        .body
    }

    static var detail: Font {
        .subheadline
    }

    static var caption: Font {
        .caption
    }

    static var captionStrong: Font {
        .caption.weight(.semibold)
    }

    static var field: Font {
        .body.weight(.medium)
    }

    static var monospacedCaption: Font {
        .system(.caption, design: .monospaced)
    }

    static func tracking(for font: Font) -> CGFloat {
        switch font {
        case .largeTitle: return -1.0
        case .title, .title2: return -0.5
        case .headline: return 0.0
        case .body: return 0.1
        case .callout: return 0.1
        case .subheadline: return 0.15
        case .footnote: return 0.2
        case .caption, .caption2: return 0.3
        default: return 0.0
        }
    }
}

enum MacChromePalette {
    static func hoverFill() -> Color {
        Color.primary.opacity(0.06)
    }

    static func selectedFill() -> Color {
        Color.accentColor.opacity(0.14)
    }

    static func neutralBorder(contrast: ColorSchemeContrast) -> Color {
        Color.secondary.opacity(contrast == .increased ? 0.45 : 0.2)
    }

    static func warningFill(contrast: ColorSchemeContrast) -> Color {
        Color.orange.opacity(contrast == .increased ? 0.22 : 0.12)
    }

    static func warningBorder(contrast: ColorSchemeContrast) -> Color {
        Color.orange.opacity(contrast == .increased ? 0.7 : 0.35)
    }

    static func errorFill(contrast: ColorSchemeContrast) -> Color {
        Color.red.opacity(contrast == .increased ? 0.20 : 0.10)
    }

    static func errorBorder(contrast: ColorSchemeContrast) -> Color {
        Color.red.opacity(contrast == .increased ? 0.7 : 0.35)
    }

    static func successFill(contrast: ColorSchemeContrast) -> Color {
        Color.green.opacity(contrast == .increased ? 0.22 : 0.12)
    }

    static func accentFill(contrast: ColorSchemeContrast) -> Color {
        Color.accentColor.opacity(contrast == .increased ? 0.22 : 0.12)
    }
}
