import SwiftUI

struct RecentProjectsSection: View {
    let recentPaths: [String]
    let currentRepoPath: String
    @Binding var showFullPathInRecents: Bool
    let onSelectPath: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectablePaths: [String] {
        Array(recentPaths.filter { $0 != currentRepoPath }.prefix(5))
    }

    var body: some View {
        if !selectablePaths.isEmpty {
            Toggle("Show full path", isOn: $showFullPathInRecents)
                .toggleStyle(.checkbox)

            ForEach(selectablePaths, id: \.self) { path in
                let abbreviatedPath = PathDisplayFormatter.abbreviatedPath(path)
                RecentPathRowView(
                    displayText: showFullPathInRecents
                        ? abbreviatedPath
                        : RecentProjectsStore().displayName(for: path),
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
                    recentPaths: [
                        "/Users/usuario/Documents/Projects/gitmenubar",
                        "/tmp/demo-app",
                        "/tmp/docs-site"
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
