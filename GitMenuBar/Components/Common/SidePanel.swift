import SwiftUI

/// Trailing contextual overlay inspired by VoiceInk's side panel pattern.
/// Independent Workbench-token reimplementation — do not copy upstream sources.
struct SidePanelModifier<PanelContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let panelWidth: CGFloat
    let dismissOnOutsideTap: Bool
    @ViewBuilder let panelContent: () -> PanelContent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var animation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.32)
    }

    private var transition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity)
    }

    private func dismissPanel() {
        isPresented = false
    }

    private var dismissLayer: some View {
        Color.clear
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: dismissPanel)
            .accessibilityHidden(true)
    }

    private var panelSurface: some View {
        panelContent()
            .frame(width: panelWidth)
            .frame(maxHeight: .infinity, alignment: .top)
            .background {
                ZStack {
                    Rectangle().fill(.background)
                    Rectangle().fill(Color.primary.opacity(contrast == .increased ? 0.06 : 0.03))
                }
                .ignoresSafeArea()
            }
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(WorkbenchPalette.neutralBorder(contrast: contrast))
                    .frame(width: 1)
                    .ignoresSafeArea()
            }
    }

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            content

            if isPresented {
                if dismissOnOutsideTap {
                    dismissLayer
                }

                panelSurface
                    .transition(transition)
                    .zIndex(1)
            }
        }
        .animation(animation, value: isPresented)
    }
}

extension View {
    func sidePanel(
        isPresented: Binding<Bool>,
        width: CGFloat = WorkbenchMetrics.sidePanelWidth,
        dismissOnOutsideTap: Bool = true,
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        modifier(
            SidePanelModifier(
                isPresented: isPresented,
                panelWidth: width,
                dismissOnOutsideTap: dismissOnOutsideTap,
                panelContent: content
            )
        )
    }
}

#Preview("Side Panel") {
    struct Host: View {
        @State private var isPresented = true

        var body: some View {
            Color.clear
                .frame(width: 720, height: 420)
                .overlay {
                    Text("Overview")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .sidePanel(
                    isPresented: $isPresented,
                    dismissOnOutsideTap: true
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
