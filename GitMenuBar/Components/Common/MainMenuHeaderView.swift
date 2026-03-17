import AppKit
import SwiftUI

struct MainMenuHeaderView<ProjectSelectorContent: View>: View {
    let currentProjectName: String
    @Binding var showProjectSelector: Bool
    let onProjectLongPress: () -> Void
    let onSettingsTap: () -> Void
    let projectSelectorContent: () -> ProjectSelectorContent

    var body: some View {
        HStack {
            Button(action: { showProjectSelector.toggle() }) {
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
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 2.0, perform: onProjectLongPress)
            .onHover { inside in
                if inside {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .popover(isPresented: $showProjectSelector) {
                projectSelectorContent()
            }

            Spacer()

            Button("Settings", action: onSettingsTap)
                .buttonStyle(.borderless)
                .focusable(false)
        }
        .padding(.top, 4)
    }
}

#Preview("Main Menu Header") {
    MainMenuHeaderView(
        currentProjectName: "gitmenubar",
        showProjectSelector: .constant(false),
        onProjectLongPress: {},
        onSettingsTap: {},
        projectSelectorContent: {
            Text("Projects")
                .padding()
        }
    )
    .padding()
    .frame(width: 400)
}
