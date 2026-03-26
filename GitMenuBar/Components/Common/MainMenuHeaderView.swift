import AppKit
import SwiftUI

struct MainMenuHeaderView<Content: View>: View {
    let currentProjectName: String
    @Binding var showProjectSelector: Bool
    let onProjectLongPress: () -> Void
    let projectSelectorContent: () -> Content

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
        }
        .padding(.leading, 72)
    }
}

#Preview("Main Menu Header") {
    MainMenuHeaderView(
        currentProjectName: "gitmenubar",
        showProjectSelector: .constant(false),
        onProjectLongPress: {},
        projectSelectorContent: {
            Text("Projects")
                .padding()
        }
    )
    .padding()
    .frame(width: 400)
}
