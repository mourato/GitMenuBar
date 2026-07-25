import SwiftUI

enum WorkbenchMaterialWeight {
    case thin
    case regular
    case thick
}

private struct WorkbenchPanelSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let materialWeight: WorkbenchMaterialWeight

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
    func workbenchPanelSurface(
        cornerRadius: CGFloat = WorkbenchMetrics.largeCornerRadius,
        material: WorkbenchMaterialWeight = .regular
    ) -> some View {
        modifier(WorkbenchPanelSurfaceModifier(cornerRadius: cornerRadius, materialWeight: material))
    }
}
