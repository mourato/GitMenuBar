import SwiftUI

enum MacPanelMaterialWeight {
    case thin
    case regular
    case thick
}

private struct MacPanelSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let materialWeight: MacPanelMaterialWeight

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background(backgroundFill)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var backgroundFill: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            shape.fill(Color(nsColor: .controlBackgroundColor))
        } else {
            switch materialWeight {
            case .thin:
                shape.fill(.thinMaterial)
            case .regular:
                shape.fill(.regularMaterial)
            case .thick:
                shape.fill(.thickMaterial)
            }
        }
    }
}

extension View {
    func macPanelSurface(cornerRadius: CGFloat = MacChromeMetrics.largeCornerRadius, material: MacPanelMaterialWeight = .regular) -> some View {
        modifier(MacPanelSurfaceModifier(cornerRadius: cornerRadius, materialWeight: material))
    }
}
