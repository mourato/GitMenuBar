import SwiftUI

struct ProjectCleanupPage: View {
    @EnvironmentObject private var store: ProjectCleanupStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var review: ProjectCleanupReview?

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.groupSpacing) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                    Text("Project Cleanup").font(.title2.weight(.semibold))
                    Text("Local-only cleanup across monitored projects.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { store.refresh() }
                    .disabled(store.loadState.isLoading || store.isRunning)
                Button("Clean Selected") { review = store.reviewSelected() }
                    .disabled(store.reviewSelected() == nil)
                Button("Clean All") { review = store.reviewAll() }
                    .disabled(store.reviewAll() == nil)
                    .buttonStyle(.borderedProminent)
            }

            summary

            switch store.loadState {
            case let .loading(completed, total):
                ProgressView("Analyzing \(completed) of \(total) projects…")
                    .accessibilityValue("Loading project cleanup analysis")
            case let .failed(message):
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                Button("Try Again") { store.refresh() }
            case .idle:
                Text("Open this page to analyze monitored projects.").foregroundStyle(.secondary)
            case .loaded:
                if store.rows.isEmpty {
                    ContentUnavailableView("No Monitored Projects", systemImage: "folder", description: Text("Add a project before reviewing cleanup."))
                } else {
                    ScrollView {
                        VStack(spacing: WorkbenchMetrics.compactSpacing) {
                            ForEach(store.rows) { row in
                                ProjectCleanupProjectRowView(row: row, isSelected: store.selectedPaths.contains(row.id), isRunning: store.isRunning, onToggle: { store.toggleSelection(path: row.id) }, onClean: {
                                    store.selectOnly(path: row.id)
                                    review = store.reviewSelected()
                                })
                            }
                            if let result = store.result {
                                ProjectCleanupResultsView(
                                    result: result,
                                    onDismiss: store.dismissResult,
                                    onRefresh: store.refresh
                                )
                            }
                        }
                    }
                }
            }
        }
        .task {
            if store.loadState == .idle {
                store.load()
            }
        }
        .sheet(item: $review) { value in
            ProjectCleanupConfirmationView(review: value) {
                store.runCleanup(value)
                review = nil
            }
        }
        .animation(WorkbenchMotion.adaptive(WorkbenchMotion.swap, usesReducedMotion: reduceMotion), value: store.loadState)
    }

    private var summary: some View {
        HStack(spacing: WorkbenchMetrics.sectionSpacing) {
            Label("\(store.rows.count) projects", systemImage: "folder")
            Label("\(store.rows.reduce(0) { $0 + $1.branchCount }) branches", systemImage: "arrow.triangle.branch")
            Label("\(store.rows.reduce(0) { $0 + $1.worktreeCount }) worktrees", systemImage: "square.stack.3d.up")
        }
        .font(.callout.monospacedDigit())
        .foregroundStyle(.secondary)
    }
}

#Preview("Project Cleanup") {
    ProjectCleanupPage()
        .environmentObject(ProjectCleanupStore())
        .frame(width: 700, height: 500)
}
