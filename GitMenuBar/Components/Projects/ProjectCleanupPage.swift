import SwiftUI

struct ProjectCleanupPage: View {
    @EnvironmentObject private var store: ProjectCleanupStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentedSheet: ProjectCleanupSheet?

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
                Button("Clean Selected") { presentReview(store.reviewSelected()) }
                    .disabled(store.reviewSelected() == nil)
                Button("Clean All") { presentReview(store.reviewAll()) }
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
                                ProjectCleanupProjectRowView(row: row, isSelected: store.selectedPaths.contains(row.id), isRunning: store.isRunning, onToggle: { store.toggleSelection(path: row.id) }, onInspect: {
                                    presentedSheet = .candidates(row)
                                }, onClean: {
                                    store.selectOnly(path: row.id)
                                    presentReview(store.reviewSelected())
                                })
                            }
                        }
                        .workbenchEdgeDissolve()
                        .workbenchThinScrollbar()
                    }
                }
            }
        }
        .task {
            if store.loadState == .idle {
                store.load()
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case let .review(value):
                ProjectCleanupConfirmationView(review: value) {
                    store.runCleanup(value)
                    presentedSheet = nil
                }
            case let .candidates(row):
                ProjectCleanupCandidatesView(row: row)
            case let .results(result):
                ProjectCleanupResultsView(
                    result: result,
                    onDismiss: {
                        presentedSheet = nil
                        store.dismissResult()
                    },
                    onRefresh: {
                        presentedSheet = nil
                        store.refresh()
                    }
                )
            }
        }
        .onChange(of: store.result?.id) { _, _ in
            if let result = store.result {
                presentedSheet = .results(result)
            }
        }
        .onChange(of: presentedSheet?.id) { _, id in
            if id == nil, store.result != nil {
                store.dismissResult()
            }
        }
        .animation(WorkbenchMotion.adaptive(WorkbenchMotion.swap, usesReducedMotion: reduceMotion), value: store.loadState)
    }

    private func presentReview(_ review: ProjectCleanupReview?) {
        guard let review else { return }
        presentedSheet = .review(review)
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

private enum ProjectCleanupSheet: Identifiable {
    case review(ProjectCleanupReview)
    case candidates(ProjectCleanupRow)
    case results(ProjectCleanupRunResult)

    var id: String {
        switch self {
        case let .review(review): "review-\(review.id)"
        case let .candidates(row): "candidates-\(row.id)"
        case .results: "results"
        }
    }
}

#Preview("Project Cleanup") {
    ProjectCleanupPage()
        .environmentObject(ProjectCleanupStore())
        .frame(width: 700, height: 500)
}
