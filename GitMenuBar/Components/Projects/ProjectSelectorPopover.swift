import SwiftUI

struct ProjectSelectorPopoverView: View {
    let recentProjects: [ProjectReference]
    let currentRepoPath: String
    let onSelectPath: (String) -> Void
    let onBrowse: () -> Void
    let onShowRepositoryOptions: (() -> Void)?

    private var normalizedCurrentRepoPath: String {
        guard !currentRepoPath.isEmpty else {
            return ""
        }
        return RecentProjectsStore.normalize(currentRepoPath)
    }

    var body: some View {
        List {
            Section("Projects") {
                ForEach(recentProjects) { project in
                    let path = project.path
                    let isCurrentProject = path == normalizedCurrentRepoPath
                    HStack(spacing: WorkbenchMetrics.compactSpacing) {
                        Button(action: { onSelectPath(path) }, label: {
                            HStack(spacing: 6) {
                                Image(systemName: isCurrentProject ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isCurrentProject ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(project.name)
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
                        .workbenchRow(isSelected: isCurrentProject)

                        if isCurrentProject, let onShowRepositoryOptions {
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
        recentProjects: [
            ProjectReference(path: "/Users/usuario/Documents/Repos/gitmenubar", name: "GitMenuBar"),
            ProjectReference(path: "/Users/usuario/Documents/Repos/my-meeting-assistant", name: "Meeting Assistant")
        ],
        currentRepoPath: "/Users/usuario/Documents/Repos/gitmenubar",
        onSelectPath: { _ in },
        onBrowse: {},
        onShowRepositoryOptions: {}
    )
}

#Preview("Project Selector Without Options") {
    ProjectSelectorPopoverView(
        recentProjects: [
            ProjectReference(path: "/Users/usuario/Documents/Repos/gitmenubar", name: "GitMenuBar"),
            ProjectReference(path: "/Users/usuario/Documents/Repos/my-meeting-assistant", name: "Meeting Assistant")
        ],
        currentRepoPath: "/Users/usuario/Documents/Repos/gitmenubar",
        onSelectPath: { _ in },
        onBrowse: {},
        onShowRepositoryOptions: nil
    )
}
