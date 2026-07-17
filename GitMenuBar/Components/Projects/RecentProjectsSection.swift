import SwiftUI

struct RecentProjectsSection: View {
    let recentPaths: [String]
    let currentRepoPath: String
    @Binding var showFullPathInRecents: Bool
    let onSelectPath: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !recentPaths.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Recently Used")
                        .font(MacChromeTypography.sectionLabel)
                        .foregroundColor(.secondary)

                    Spacer()

                    Toggle("Show full path", isOn: $showFullPathInRecents)
                        .toggleStyle(.checkbox)
                        .font(MacChromeTypography.caption)
                }

                ForEach(recentPaths.filter { $0 != currentRepoPath }.prefix(5), id: \.self) { path in
                    let abbreviatedPath = PathDisplayFormatter.abbreviatedPath(path)
                    RecentPathRowView(
                        displayText: PathDisplayFormatter.recentProjectLabel(
                            for: path,
                            showFullPath: showFullPathInRecents
                        ),
                        fullPath: abbreviatedPath,
                        onTap: {
                            onSelectPath(path)
                        }
                    )
                }
            }
            .padding(.top, 4)
            .animation(
                MacChromeMotion.adaptive(MacChromeMotion.swap, usesReducedMotion: reduceMotion),
                value: showFullPathInRecents
            )
        }
    }
}

private struct RecentProjectsSectionPreviewContainer: View {
    @State private var showFullPathInRecents = false

    var body: some View {
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
        .padding()
        .frame(width: 360)
    }
}

#Preview("Recent Projects") {
    RecentProjectsSectionPreviewContainer()
}
