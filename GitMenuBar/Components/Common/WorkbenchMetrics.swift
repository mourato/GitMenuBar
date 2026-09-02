import CoreGraphics
import SwiftUI

// MARK: - Adaptive motion

struct AdaptiveMotionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    func body(content: Content) -> some View {
        content
            .transaction { transaction in
                if reduceMotion {
                    transaction.animation = WorkbenchMotion.reduceMotion
                }
            }
    }
}

extension View {
    func adaptiveMotion() -> some View {
        modifier(AdaptiveMotionModifier())
    }
}

enum WorkbenchMetrics {
    static let microSpacing: CGFloat = 4
    static let chipSpacing: CGFloat = 6
    static let compactSpacing: CGFloat = 8
    static let sectionSpacing: CGFloat = 12
    static let groupSpacing: CGFloat = 20
    static let panelPadding: CGFloat = 16
    static let windowPadding: CGFloat = 12
    static let headerVerticalPadding: CGFloat = 2
    static let microCornerRadius: CGFloat = 6
    static let rowCornerRadius: CGFloat = 8
    static let cornerRadius: CGFloat = 10
    static let largeCornerRadius: CGFloat = 14
    static let overlayCornerRadius: CGFloat = 16
    static let iconHitTarget: CGFloat = 28
}

enum WorkbenchTypography {
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

    static func tracking(for font: Font) -> CGFloat {
        switch font {
        case .largeTitle: -1.0
        case .title, .title2: -0.5
        case .headline: 0.0
        case .body: 0.1
        case .callout: 0.1
        case .subheadline: 0.15
        case .footnote: 0.2
        case .caption, .caption2: 0.3
        default: 0.0
        }
    }
}

enum WorkbenchPalette {
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
