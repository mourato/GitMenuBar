import SwiftUI

struct ProjectSelectorPopoverView: View {
    let recentPaths: [String]
    let currentRepoPath: String
    let onSelectPath: (String) -> Void
    let onBrowse: () -> Void
    let onShowRepositoryOptions: (() -> Void)?

    var body: some View {
        List {
            Section("Projects") {
                ForEach(recentPaths, id: \.self) { path in
                    Button(action: { onSelectPath(path) }, label: {
                        HStack(spacing: 6) {
                            Image(systemName: path == currentRepoPath ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(path == currentRepoPath ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(URL(fileURLWithPath: path).lastPathComponent)
                                    .lineLimit(1)
                                Text(PathDisplayFormatter.abbreviatedPath(path))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                    })
                    .buttonStyle(.plain)
                }
            }

            Section {
                Button(action: onBrowse) {
                    Label("Choose Repository…", systemImage: "folder")
                }

                if let onShowRepositoryOptions {
                    Button(action: onShowRepositoryOptions) {
                        Label("Repository Options…", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .macPanelSurface()
        .frame(width: 280, height: 240)
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
        onBrowse: {},
        onShowRepositoryOptions: {}
    )
}
