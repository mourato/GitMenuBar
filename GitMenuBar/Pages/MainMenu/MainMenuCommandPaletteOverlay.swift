import SwiftUI

struct MainMenuCommandPaletteOverlay: View {
    let isPresented: Bool
    @Binding var query: String
    let items: [MainMenuCommandPaletteItem]
    @Binding var selectedItemID: String?
    let onClose: () -> Void
    let onSelectItem: (MainMenuCommandPaletteItem) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isPresented {
            ZStack {
                commandPaletteScrim
                    .ignoresSafeArea()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Dismiss command palette")
                    .accessibilityAddTraits(.isButton)
                    .onTapGesture {
                        onClose()
                    }
                    .zIndex(0)

                MainMenuCommandPaletteView(
                    query: $query,
                    items: items,
                    selectedItemID: $selectedItemID,
                    onClose: onClose,
                    onSelectItem: onSelectItem
                )
                .accessibilityAddTraits(.isModal)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(1)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var commandPaletteScrim: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            ZStack {
                Color.black.opacity(0.08)
                Rectangle()
                    .fill(.ultraThinMaterial)
            }
        }
    }
}

#Preview("Command Palette Overlay") {
    MainMenuCommandPaletteOverlay(
        isPresented: true,
        query: .constant(""),
        items: [],
        selectedItemID: .constant(nil),
        onClose: {},
        onSelectItem: { _ in }
    )
    .frame(width: 420, height: 420)
    .padding()
}
