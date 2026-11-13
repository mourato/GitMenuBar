import AppKit
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
    /// Leading edge of dense list row content (status slot). Row padding and
    /// list section headers and captions share it so their edges line up.
    static let rowContentInset: CGFloat = sectionSpacing
    static let windowPadding: CGFloat = 12
    static let headerVerticalPadding: CGFloat = 2
    static let microCornerRadius: CGFloat = 6
    static let rowCornerRadius: CGFloat = 8
    static let cornerRadius: CGFloat = 10
    static let largeCornerRadius: CGFloat = 14
    static let overlayCornerRadius: CGFloat = 16
    static let iconHitTarget: CGFloat = 28
    /// Minimum interactive height for text chips, toggles, and buttons (DESIGN.md hit areas).
    static let minimumHitTarget: CGFloat = 32
    static let quotaMeterWidth: CGFloat = 20
    static let quotaMeterHeight: CGFloat = 6
    static let projectsMinimumWidth: CGFloat = 256
    static let projectsMaximumWidth: CGFloat = 360
    /// Preferred width for a project row's name and status column. Trailing
    /// GitHub totals are only shown when this width still fits; at supported
    /// sidebar widths the no-totals fallback leaves even more room.
    static let projectsRowTextMinimumWidth: CGFloat = 110
    static let centralMinimumWidth: CGFloat = 360
    /// Fixed trailing side-panel column width (contextual details).
    static let sidePanelWidth: CGFloat = 360
    static let splitDividerThickness: CGFloat = 8
    /// Three-column floor: Projects sidebar + central detail + side panel,
    /// window insets, divider, and the split-column gap.
    static let mainWindowMinimumWidth: CGFloat = projectsMinimumWidth
        + centralMinimumWidth
        + sidePanelWidth
        + (windowPadding * 2)
        + splitDividerThickness
        + sectionSpacing
    /// Start at the three-column floor so an opened panel has room immediately.
    static let mainWindowInitialWidth: CGFloat = mainWindowMinimumWidth
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

    /// Project names in the Projects sidebar: native body size with enough
    /// weight to lead the secondary status line.
    static var projectName: Font {
        .body.weight(.semibold)
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

    /// GitHub issue markers keep one semantic green across the workbench.
    static func issueMarker() -> Color {
        .green
    }

    /// GitHub pull-request markers keep one semantic purple across the workbench.
    static func pullRequestMarker() -> Color {
        Color(nsColor: pullRequestMarkerColor)
    }

    private static let pullRequestMarkerColor = NSColor(name: "WorkbenchPullRequestMarker") { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0xAB / 255.0, green: 0x7D / 255.0, blue: 0xF8 / 255.0, alpha: 1)
            : NSColor(srgbRed: 0x82 / 255.0, green: 0x50 / 255.0, blue: 0xDF / 255.0, alpha: 1)
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
