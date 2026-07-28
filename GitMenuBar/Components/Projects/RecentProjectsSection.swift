import SwiftUI

struct RecentProjectsSection: View {
    let recentProjects: [ProjectReference]
    let currentRepoPath: String
    @Binding var showFullPathInRecents: Bool
    let onSelectPath: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var normalizedCurrentRepoPath: String {
        guard !currentRepoPath.isEmpty else {
            return ""
        }
        return RecentProjectsStore.normalize(currentRepoPath)
    }

    private var selectableProjects: [ProjectReference] {
        Array(recentProjects.filter { $0.path != normalizedCurrentRepoPath }.prefix(5))
    }

    var body: some View {
        if !selectableProjects.isEmpty {
            Toggle("Show full path", isOn: $showFullPathInRecents)
                .toggleStyle(.checkbox)

            ForEach(selectableProjects) { project in
                let path = project.path
                let abbreviatedPath = PathDisplayFormatter.abbreviatedPath(path)
                RecentPathRowView(
                    displayText: showFullPathInRecents
                        ? abbreviatedPath
                        : project.name,
                    fullPath: abbreviatedPath,
                    onTap: {
                        onSelectPath(path)
                    }
                )
            }
            .animation(
                WorkbenchMotion.adaptive(WorkbenchMotion.swap, usesReducedMotion: reduceMotion),
                value: showFullPathInRecents
            )
        } else {
            Text("No other recent projects.")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct RecentProjectsSectionPreviewContainer: View {
    @State private var showFullPathInRecents = false

    var body: some View {
        Form {
            Section {
                RecentProjectsSection(
                    recentProjects: [
                        ProjectReference(path: "/Users/usuario/Documents/Projects/gitmenubar", name: "GitMenuBar"),
                        ProjectReference(path: "/tmp/demo-app", name: "Client Demo"),
                        ProjectReference(path: "/tmp/docs-site", name: "Documentation Site")
                    ],
                    currentRepoPath: "/Users/usuario/Documents/Projects/gitmenubar",
                    showFullPathInRecents: $showFullPathInRecents,
                    onSelectPath: { _ in }
                )
            } header: {
                SettingsFormSectionHeader(title: "Recent Projects", icon: "clock")
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 240)
    }
}

#Preview("Recent Projects") {
    RecentProjectsSectionPreviewContainer()
}
