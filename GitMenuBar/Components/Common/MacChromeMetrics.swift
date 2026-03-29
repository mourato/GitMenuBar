import CoreGraphics
import SwiftUI

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
