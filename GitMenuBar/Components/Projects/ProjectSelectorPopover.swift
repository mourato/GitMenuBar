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
                    HStack(spacing: WorkbenchMetrics.compactSpacing) {
                        Button(action: { onSelectPath(path) }, label: {
                            HStack(spacing: 6) {
                                Image(systemName: path == currentRepoPath ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(path == currentRepoPath ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(URL(fileURLWithPath: path).lastPathComponent)
                                        .font(WorkbenchTypography.body)
                                        .lineLimit(1)
                                    Text(PathDisplayFormatter.abbreviatedPath(path))
                                        .font(WorkbenchTypography.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                        })
                        .buttonStyle(.plain)
                        .workbenchRow(isSelected: path == currentRepoPath)

                        if path == currentRepoPath, let onShowRepositoryOptions {
                            MainMenuHeaderIconButton(
                                systemImage: "ellipsis.circle",
                                accessibilityLabel: "Repository options",
                                accessibilityHint: "Shows repository visibility and deletion actions.",
                                action: onShowRepositoryOptions
                            )
                        }
                    }
                }
            }

            Section {
                Button(action: onBrowse) {
                    Label("Choose Repository…", systemImage: "folder")
                }
                .workbenchRow()
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .workbenchPanelSurface(material: .thin)
        .frame(width: 300, height: 260)
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

#Preview("Project Selector Without Options") {
    ProjectSelectorPopoverView(
        recentPaths: [
            "/Users/usuario/Documents/Repos/gitmenubar",
            "/Users/usuario/Documents/Repos/my-meeting-assistant"
        ],
        currentRepoPath: "/Users/usuario/Documents/Repos/gitmenubar",
        onSelectPath: { _ in },
        onBrowse: {},
        onShowRepositoryOptions: nil
    )
}
