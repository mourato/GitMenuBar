import SwiftUI

struct ProjectsSidebarView: View {
    @EnvironmentObject private var monitor: ProjectMonitorStore
    @AppStorage(AppPreferences.Keys.isProjectsSidebarCollapsed) private var isCollapsed = false
    let currentPath: String
    let onSelect: (String) -> Void
    let onReveal: (String) -> Void
    let onStopMonitoring: (String) -> Void
    let onRemove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isCollapsed {
                    Text("Projects").font(.headline)
                }
                Spacer()
                Button { isCollapsed.toggle() } label: {
                    Image(systemName: isCollapsed ? "sidebar.right" : "sidebar.left")
                }.help(isCollapsed ? "Expand projects" : "Collapse projects")
            }.padding(.horizontal, 10)
            ForEach(groupedProjects, id: \.0) { title, snapshots in
                if !isCollapsed {
                    Text(title.uppercased()).font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 10)
                }
                ForEach(snapshots) { snapshot in row(snapshot) }
            }
        }
        .frame(width: isCollapsed ? 42 : 240, alignment: .top)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.35))
    }

    private var groupedProjects: [(String, [ProjectStatusSnapshot])] {
        let values = monitor.monitoredProjects.compactMap { monitor.snapshots[$0.path] }
        return [
            ("Needs Attention", values.filter { $0.classification == .needsAttention }),
            ("Clean", values.filter { $0.classification == .clean }),
            ("Unavailable", values.filter { $0.classification == .unavailable })
        ].filter { !$0.1.isEmpty }
    }

    private func row(_ snapshot: ProjectStatusSnapshot) -> some View {
        Button { onSelect(snapshot.project.path) } label: {
            HStack(spacing: 7) {
                Circle().fill(snapshot.classification == .clean ? .green : .orange).frame(width: 7, height: 7)
                if !isCollapsed {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.project.name).lineLimit(1)
                        Text(snapshot.branchName.isEmpty ? "Unavailable" : snapshot.branchName)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                }
            }.padding(.horizontal, 10).padding(.vertical, 5)
                .background(
                    snapshot.project.path == RecentProjectsStore.normalize(currentPath)
                        ? Color.accentColor.opacity(0.18)
                        : Color.clear
                )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Reveal in Finder") { onReveal(snapshot.project.path) }
            Button("Stop Monitoring") { onStopMonitoring(snapshot.project.path) }
            Button("Remove Project", role: .destructive) { onRemove(snapshot.project.path) }
        }
        .accessibilityLabel(snapshot.project.name)
    }
}

#Preview {
    ProjectsSidebarView(
        currentPath: "",
        onSelect: { _ in },
        onReveal: { _ in },
        onStopMonitoring: { _ in },
        onRemove: { _ in }
    )
    .environmentObject(ProjectMonitorStore())
}
