import SwiftUI

struct ProjectSelectorPopoverView: View {
    let recentPaths: [String]
    let currentRepoPath: String
    let onSelectPath: (String) -> Void
    let onBrowse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Projects")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            ForEach(recentPaths, id: \.self) { path in
                Button(action: { onSelectPath(path) }, label: {
                    HStack(spacing: 6) {
                        Image(systemName: path == currentRepoPath ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12))
                            .foregroundColor(path == currentRepoPath ? .green : .secondary)
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.system(size: 13))
                            .lineLimit(1)
                        Spacer()
                    }
                })
                .buttonStyle(.plain)
            }

            Divider()

            Button(action: onBrowse) {
                Label("Browse...", systemImage: "folder")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 250)
    }
}

#Preview("Project Selector") {
    ProjectSelectorPopoverView(
        recentPaths: [
            "/Users/usuario/Documents/Repos/gitmenubar",
            "/Users/usuario/Documents/Repos/my-meeting-assistant"
        ],
        currentRepoPath: "/Users/usuario/Documents/Repos/gitmenubar",
        onSelectPath: { _ in },
        onBrowse: {}
    )
}
