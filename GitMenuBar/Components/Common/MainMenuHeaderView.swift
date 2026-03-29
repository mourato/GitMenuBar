import AppKit
import SwiftUI

struct MainMenuHeaderView<PopoverContent: View, ContextMenuContent: View>: View {
    let currentProjectName: String
    @Binding var showProjectSelector: Bool
    let showsRepositoryOptionsButton: Bool
    let onShowRepositoryOptions: () -> Void
    let projectSelectorContent: () -> PopoverContent
    let projectContextMenu: () -> ContextMenuContent

    init(
        currentProjectName: String,
        showProjectSelector: Binding<Bool>,
        showsRepositoryOptionsButton: Bool,
        onShowRepositoryOptions: @escaping () -> Void,
        @ViewBuilder projectSelectorContent: @escaping () -> PopoverContent,
        @ViewBuilder projectContextMenu: @escaping () -> ContextMenuContent
    ) {
        self.currentProjectName = currentProjectName
        _showProjectSelector = showProjectSelector
        self.showsRepositoryOptionsButton = showsRepositoryOptionsButton
        self.onShowRepositoryOptions = onShowRepositoryOptions
        self.projectSelectorContent = projectSelectorContent
        self.projectContextMenu = projectContextMenu
    }

    var body: some View {
        HStack {
            Button(action: { showProjectSelector.toggle() }, label: {
                HStack(spacing: 4) {
                    Text(currentProjectName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundColor(.primary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            })
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel("Current repository")
            .accessibilityHint("Opens the recent repository picker.")
            .onHover { inside in
                if inside {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .contextMenu(menuItems: projectContextMenu)
            .popover(isPresented: $showProjectSelector) {
                projectSelectorContent()
            }

            if showsRepositoryOptionsButton {
                Button {
                    onShowRepositoryOptions()
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Repository options")
                .accessibilityHint("Shows repository visibility and deletion actions.")
            }

            Spacer()
        }
    }
}

#Preview("Main Menu Header") {
    MainMenuHeaderView(
        currentProjectName: "gitmenubar",
        showProjectSelector: .constant(false),
        showsRepositoryOptionsButton: true,
        onShowRepositoryOptions: {},
        projectSelectorContent: {
            Text("Projects")
                .padding()
        },
        projectContextMenu: {
            Button("Repository Options…") {}
        }
    )
    .padding()
    .frame(width: 400)
}
