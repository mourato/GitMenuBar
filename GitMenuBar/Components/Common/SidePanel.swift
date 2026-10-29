import SwiftUI

/// Trailing contextual column for the main workbench.
/// Independent Workbench-token reimplementation — do not copy upstream sources.
struct SidePanelModifier<PanelContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let panelWidth: CGFloat
    @ViewBuilder let panelContent: () -> PanelContent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var animation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.32)
    }

    private var transition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity)
    }

    private var panelSurface: some View {
        panelContent()
            .frame(width: panelWidth)
            .frame(maxHeight: .infinity, alignment: .top)
            .background {
                ZStack {
                    RoundedRectangle(
                        cornerRadius: WorkbenchMetrics.largeCornerRadius,
                        style: .continuous
                    )
                    .fill(.background)
                    RoundedRectangle(
                        cornerRadius: WorkbenchMetrics.largeCornerRadius,
                        style: .continuous
                    )
                    .fill(Color.primary.opacity(contrast == .increased ? 0.06 : 0.03))
                }
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: WorkbenchMetrics.largeCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: WorkbenchMetrics.largeCornerRadius,
                    style: .continuous
                )
                .stroke(
                    WorkbenchPalette.neutralBorder(contrast: contrast),
                    lineWidth: 1
                )
            }
            .padding(.bottom, WorkbenchMetrics.windowPadding)
    }

    func body(content: Content) -> some View {
        HStack(alignment: .top, spacing: WorkbenchMetrics.sectionSpacing) {
            content
                .frame(
                    minWidth: WorkbenchMetrics.centralMinimumWidth,
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .top
                )
            if isPresented {
                panelSurface
                    .transition(transition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(animation, value: isPresented)
    }
}

extension View {
    func sidePanel(
        isPresented: Binding<Bool>,
        width: CGFloat = WorkbenchMetrics.sidePanelWidth,
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        modifier(
            SidePanelModifier(
                isPresented: isPresented,
                panelWidth: width,
                panelContent: content
            )
        )
    }
}

#Preview("Side Panel – Open") {
    struct Host: View {
        @State private var isPresented = true

        var body: some View {
            Color.clear
                .frame(
                    width: WorkbenchMetrics.centralMinimumWidth
                        + WorkbenchMetrics.sidePanelWidth
                        + WorkbenchMetrics.sectionSpacing,
                    height: 420
                )
                .overlay {
                    Text("Overview")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .sidePanel(
                    isPresented: $isPresented
                ) {
                    VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
                        Text("Details")
                            .font(WorkbenchTypography.windowTitle)
                        Text("Preview panel content")
                            .font(WorkbenchTypography.detail)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(WorkbenchMetrics.panelPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
        }
    }

    return Host()
}
