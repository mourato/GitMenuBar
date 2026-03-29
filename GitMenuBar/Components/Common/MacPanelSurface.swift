import SwiftUI

private struct MacPanelSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

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
            shape.fill(.regularMaterial)
        }
    }
}

extension View {
    func macPanelSurface(cornerRadius: CGFloat = MacChromeMetrics.largeCornerRadius) -> some View {
        modifier(MacPanelSurfaceModifier(cornerRadius: cornerRadius))
    }
}
