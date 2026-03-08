import AppKit
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
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFullPathInRecents.toggle()
                    }
                }
                .onHover { inside in
                    if inside {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .help("Click to toggle between full path and project name")

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
