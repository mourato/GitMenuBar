import AppKit
import SwiftUI

struct ProjectsSidebarView: View {
    @EnvironmentObject private var monitor: ProjectMonitorStore
    @AppStorage(AppPreferences.Keys.isProjectsSidebarCollapsed) private var isCollapsed = false
    @AppStorage(AppPreferences.Keys.projectsSidebarWidth) private var expandedWidth = ProjectsSidebarMetrics.defaultWidth
    @State private var renameProject: ProjectReference?
    @State private var renameDraft = ""
    @State private var resizeDragStartWidth: Double?

    let currentPath: String
    let onSelect: (String) -> Void
    let onReveal: (String) -> Void
    let onStopMonitoring: (String) -> Void
    let onRemove: (String) -> Void
    let onRename: (String, String) -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            VStack(alignment: .leading, spacing: 8) {
                sidebarControls

                ScrollView(.vertical, showsIndicators: true) {
                    projectGroups
                }
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(1)

                sidebarFooter
            }
            .padding(.top, ProjectsSidebarMetrics.headerHeight + WorkbenchMetrics.sectionSpacing)
            .padding(.bottom, WorkbenchMetrics.windowPadding)
            .frame(width: sidebarWidth, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            if !isCollapsed {
                resizeHandle
            }
        }
        .frame(width: sidebarWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(sidebarBackground)
        .alert("Rename Project", isPresented: Binding(
            get: { renameProject != nil },
            set: {
                if !$0 {
                    renameProject = nil
                }
            }
        )) {
            TextField("Project name", text: $renameDraft)
            Button("Cancel", role: .cancel) { renameProject = nil }
            Button("Rename") {
                if let project = renameProject {
                    onRename(project.path, renameDraft)
                }
                renameProject = nil
            }
        }
    }

    @ViewBuilder
    private var sidebarBackground: some View {
        if isCollapsed {
            Color.clear
        } else {
            Rectangle()
                .fill(.quaternary.opacity(0.35))
        }
    }

    @ViewBuilder
    private var sidebarControls: some View {
        if !isCollapsed {
            HStack {
                Text("Projects")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 10)
        }
    }

    private var projectGroups: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(groupedProjects, id: \.0) { title, snapshots in
                if !isCollapsed {
                    Text(title.uppercased())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                }
                ForEach(snapshots) { snapshot in
                    row(snapshot)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var sidebarFooter: some View {
        if !isCollapsed {
            VStack(spacing: WorkbenchMetrics.compactSpacing) {
                Divider()
                UsageQuotaStripView()
                    .padding(.horizontal, 10)
            }
        }
    }

    private var resizeHandle: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: ProjectsSidebarMetrics.resizeHitWidth)
            Rectangle()
                .fill(Color.secondary.opacity(0.16))
                .frame(width: 1)
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(resizeGesture)
        .onHover { isHovering in
            (isHovering ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
        }
        .accessibilityElement()
        .accessibilityLabel("Resize Projects sidebar")
        .accessibilityValue("\(Int(expandedWidth)) pixels")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                expandedWidth = clampedWidth(expandedWidth + ProjectsSidebarMetrics.keyboardResizeStep)
            case .decrement:
                expandedWidth = clampedWidth(expandedWidth - ProjectsSidebarMetrics.keyboardResizeStep)
            default:
                break
            }
        }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if resizeDragStartWidth == nil {
                    resizeDragStartWidth = expandedWidth
                }
                let startWidth = resizeDragStartWidth ?? expandedWidth
                expandedWidth = clampedWidth(startWidth + value.translation.width)
            }
            .onEnded { _ in
                resizeDragStartWidth = nil
            }
    }

    private var sidebarWidth: CGFloat {
        CGFloat(isCollapsed ? ProjectsSidebarMetrics.collapsedWidth : clampedWidth(expandedWidth))
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
                Circle()
                    .fill(snapshot.classification == .clean ? .green : .orange)
                    .frame(width: 7, height: 7)
                if !isCollapsed {
                    HStack(spacing: 7) {
                        Text(snapshot.project.name)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if snapshot.hasWorkingTreeChanges {
                            WorkingTreeLineDiffView(
                                addedCount: snapshot.lineDiff.added,
                                removedCount: snapshot.lineDiff.removed
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                snapshot.project.path == RecentProjectsStore.normalize(currentPath)
                    ? Color.accentColor.opacity(0.18)
                    : Color.clear
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename Project") {
                renameDraft = snapshot.project.name
                renameProject = snapshot.project
            }
            Button("Reveal in Finder") { onReveal(snapshot.project.path) }
            Button("Stop Monitoring") { onStopMonitoring(snapshot.project.path) }
            Button("Remove Project", role: .destructive) { onRemove(snapshot.project.path) }
        }
        .accessibilityLabel(accessibilityLabel(for: snapshot))
    }

    private func accessibilityLabel(for snapshot: ProjectStatusSnapshot) -> String {
        guard snapshot.hasWorkingTreeChanges else { return snapshot.project.name }
        return "\(snapshot.project.name), \(snapshot.lineDiff.added) lines added, \(snapshot.lineDiff.removed) lines deleted"
    }

    private func clampedWidth(_ width: Double) -> Double {
        min(max(width, ProjectsSidebarMetrics.minWidth), ProjectsSidebarMetrics.maxWidth)
    }
}

enum ProjectsSidebarMetrics {
    static let collapsedWidth: Double = 0
    static let defaultWidth: Double = 240
    static let minWidth: Double = 220
    static let maxWidth: Double = 360
    static let keyboardResizeStep: Double = 16
    static let resizeHitWidth: CGFloat = 8
    static let headerHeight: CGFloat = 28
    static let sidebarToggleLeadingPadding: CGFloat = 88
}

#Preview {
    ProjectsSidebarView(
        currentPath: "",
        onSelect: { _ in },
        onReveal: { _ in },
        onStopMonitoring: { _ in },
        onRemove: { _ in },
        onRename: { _, _ in }
    )
    .environmentObject(ProjectMonitorStore())
    .environmentObject(UsageQuotaStore())
}
