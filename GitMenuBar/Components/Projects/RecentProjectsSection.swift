import SwiftUI

struct RecentProjectsSection: View {
    let recentPaths: [String]
    let currentRepoPath: String
    @Binding var showFullPathInRecents: Bool
    let onSelectPath: (String) -> Void

    var body: some View {
        if !recentPaths.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Recently Used")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)

                    Spacer()

                    Toggle("Show full path", isOn: $showFullPathInRecents.animation(.easeInOut(duration: 0.2)))
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
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
