import AppKit
import SwiftUI

struct ChangedFilesSummaryView: View {
    let changedFiles: [CommitFileChange]
    let commitSHA: String
    let remoteURL: String
    var onOpenLocalFile: ((String) -> Void)?

    @State private var isCollapsed: Bool
    @State private var allDirectoriesExpanded: Bool
    @State private var directoryExpansionOverrides: [String: Bool] = [:]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        changedFiles: [CommitFileChange],
        commitSHA: String,
        remoteURL: String,
        onOpenLocalFile: ((String) -> Void)? = nil
    ) {
        self.changedFiles = changedFiles
        self.commitSHA = commitSHA
        self.remoteURL = remoteURL
        self.onOpenLocalFile = onOpenLocalFile

        let totalChangedLines = changedFiles.reduce(into: 0) { total, file in
            total += file.lineDiff.added + file.lineDiff.removed
        }
        let shouldAutoExpand = ChangedFilesPresentation.shouldAutoExpandChangedFiles(
            fileCount: changedFiles.count,
            totalChangedLines: totalChangedLines,
            isPrimaryContext: true
        )
        _isCollapsed = State(initialValue: !shouldAutoExpand)
        _allDirectoriesExpanded = State(initialValue: shouldAutoExpand)
    }

    private var paths: [String] {
        changedFiles.map(\.path)
    }

    private var aggregateStat: DiffTreeStat {
        DiffTreeBuilder.summarizeDiffTreeStats(changedFiles.map(\.diffTreeFileInput))
    }

    private var treeNodes: [DiffTreeNode] {
        DiffTreeBuilder.buildDiffTree(changedFiles.map(\.diffTreeFileInput))
    }

    private var directoryPaths: [String] {
        Self.collectDirectoryPaths(in: treeNodes)
    }

    private var hasDirectoryNodes: Bool {
        !directoryPaths.isEmpty
    }

    private var commitURL: URL? {
        GitHubRemoteURLParser.commitURL(remoteURL: remoteURL, sha: commitSHA)
    }

    private var canOpenCommitOnGitHub: Bool {
        commitURL != nil
    }

    private var changedFilesTitle: String {
        let count = changedFiles.count
        return "\(count) changed file\(count == 1 ? "" : "s")"
    }

    private var scopeSummary: [ChangedFilesScopeSummary] {
        ChangedFilesPresentation.summarizeChangedFileScopes(paths: paths)
    }

    private var previewPaths: [String] {
        ChangedFilesPresentation.selectChangedFilePreview(paths: paths)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
            if changedFiles.isEmpty {
                Text("No file list available for this commit.")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
            } else {
                summaryHeader

                if isCollapsed {
                    compactPreview
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .move(edge: .top))
                        )
                } else {
                    diffTree
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .move(edge: .top))
                        )
                }
            }
        }
        .animation(
            WorkbenchMotion.adaptive(WorkbenchMotion.settle, usesReducedMotion: reduceMotion),
            value: isCollapsed
        )
    }

    private var summaryHeader: some View {
        WorkbenchSectionHeaderChrome(
            title: changedFilesTitle,
            isCollapsed: $isCollapsed,
            accessibilityLabel: "\(changedFilesTitle) section",
            accessibilityHintExpanded: "Shows changed files.",
            accessibilityHintCollapsed: "Hides changed files."
        ) { isHovered in
            HStack(spacing: WorkbenchMetrics.microSpacing) {
                WorkingTreeLineDiffView(
                    addedCount: aggregateStat.additions,
                    removedCount: aggregateStat.deletions
                )

                if isHovered {
                    Text(isCollapsed ? "Show files" : "Hide files")
                        .font(WorkbenchTypography.caption)
                        .foregroundStyle(.secondary)
                }

                if !isCollapsed, hasDirectoryNodes {
                    Button(action: toggleAllDirectories) {
                        Image(
                            systemName: allDirectoriesExpanded
                                ? "arrow.down.right.and.arrow.up.left"
                                : "arrow.up.left.and.arrow.down.right"
                        )
                        .font(WorkbenchTypography.captionStrong)
                        .foregroundStyle(.primary)
                        .frame(
                            width: WorkingTreeLayoutMetrics.actionHitTarget,
                            height: WorkingTreeLayoutMetrics.actionHitTarget
                        )
                        .contentShape(Rectangle())
                    }
                    .workbenchIcon()
                    .help(allDirectoriesExpanded ? "Collapse all folders" : "Expand all folders")
                    .accessibilityLabel(allDirectoriesExpanded ? "Collapse all folders" : "Expand all folders")
                }

                Button("Open Diff") {
                    openCommitDiff()
                }
                .workbenchGhost()
                .disabled(!canOpenCommitOnGitHub)
                .accessibilityLabel("Open diff")
                .accessibilityHint(
                    canOpenCommitOnGitHub
                        ? "Opens this commit on GitHub."
                        : "Unavailable without a GitHub remote."
                )
            }
        }
    }

    private var compactPreview: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
            if !scopeSummary.isEmpty {
                HStack(spacing: WorkbenchMetrics.chipSpacing) {
                    ForEach(Array(scopeSummary.enumerated()), id: \.element.label) { index, scope in
                        if index > 0 {
                            Text("·")
                                .font(WorkbenchTypography.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }

                        HStack(spacing: WorkbenchMetrics.microSpacing) {
                            Text(scope.label)
                                .font(WorkbenchTypography.captionStrong.monospaced())
                                .foregroundStyle(.primary.opacity(0.75))
                            Text("\(scope.fileCount) file\(scope.fileCount == 1 ? "" : "s")")
                                .font(WorkbenchTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            ChangedFilesPreviewFlowLayout(spacing: WorkbenchMetrics.chipSpacing) {
                ForEach(previewPaths, id: \.self) { path in
                    previewChip(for: path)
                }

                Button("Show all \(changedFiles.count) files") {
                    withAnimation(
                        WorkbenchMotion.adaptive(WorkbenchMotion.settle, usesReducedMotion: reduceMotion)
                    ) {
                        isCollapsed = false
                    }
                }
                .workbenchGhost()
                .font(WorkbenchTypography.captionStrong)
                .accessibilityLabel("Show all \(changedFiles.count) changed files")
            }
        }
        .padding(.leading, WorkbenchMetrics.compactSpacing)
    }

    private func previewChip(for path: String) -> some View {
        Button {
            openFile(at: path)
        } label: {
            HStack(spacing: WorkbenchMetrics.microSpacing) {
                FileTypeIconView(path: path)

                Text(ChangedFilesPresentation.changedFileName(path: path))
                    .font(WorkbenchTypography.captionStrong.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, WorkbenchMetrics.chipSpacing)
            .padding(.vertical, WorkbenchMetrics.microSpacing)
            .background(WorkbenchPalette.hoverFill().opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(path)
        .accessibilityLabel(previewChipAccessibilityLabel(for: path))
    }

    private var diffTree: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
            ForEach(treeNodes, id: \.self) { node in
                ChangedFilesDiffTreeNodeView(
                    node: node,
                    depth: 0,
                    hasDirectoryNodes: hasDirectoryNodes,
                    allDirectoriesExpanded: allDirectoriesExpanded,
                    directoryExpansionOverrides: directoryExpansionOverrides,
                    onToggleDirectory: toggleDirectory,
                    onOpenFile: openFile(at:)
                )
            }
        }
        .padding(.leading, WorkbenchMetrics.microSpacing)
    }

    private func openCommitDiff() {
        guard let commitURL else {
            return
        }
        NSWorkspace.shared.open(commitURL)
    }

    private func openFile(at path: String) {
        if let blobURL = GitHubRemoteURLParser.blobURL(
            remoteURL: remoteURL,
            sha: commitSHA,
            path: path
        ) {
            NSWorkspace.shared.open(blobURL)
            return
        }

        onOpenLocalFile?(path)
    }

    private func toggleAllDirectories() {
        allDirectoriesExpanded.toggle()
        directoryExpansionOverrides = [:]
    }

    private func toggleDirectory(_ path: String) {
        let isExpanded = directoryExpansionOverrides[path] ?? allDirectoriesExpanded
        directoryExpansionOverrides[path] = !isExpanded
    }

    private func previewChipAccessibilityLabel(for path: String) -> String {
        guard let file = changedFiles.first(where: { $0.path == path }) else {
            return ChangedFilesPresentation.changedFileName(path: path)
        }
        return fileAccessibilityLabel(for: file)
    }

    private func fileAccessibilityLabel(for file: CommitFileChange) -> String {
        var label = ChangedFilesPresentation.changedFileName(path: file.path)
        if file.lineDiff.added > 0 {
            label += ", \(file.lineDiff.added) additions"
        }
        if file.lineDiff.removed > 0 {
            label += ", \(file.lineDiff.removed) deletions"
        }
        return label
    }

    private static func collectDirectoryPaths(in nodes: [DiffTreeNode]) -> [String] {
        nodes.flatMap { node -> [String] in
            switch node {
            case let .directory(_, path, _, children):
                return [path] + collectDirectoryPaths(in: children)
            case .file:
                return []
            }
        }
    }
}
