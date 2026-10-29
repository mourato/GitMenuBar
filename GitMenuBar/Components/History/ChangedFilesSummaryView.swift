import AppKit
import SwiftUI

private enum ChangedFilesListMetrics {
    /// Changed-file row height floor from the commit inspector contract.
    static let rowMinHeight: CGFloat = 24
    /// Summary proportion bar: 40 x 5 pt, radius 2.5.
    static let proportionBarWidth: CGFloat = 40
    static let proportionBarHeight: CGFloat = 5
    static let proportionBarCornerRadius: CGFloat = 2.5
    /// Files shown before the list asks to reveal the rest.
    static let collapsedFileLimit = 8
}

private struct ChangedFilesGroup: Identifiable {
    let label: String
    let files: [CommitFileChange]

    var id: String {
        label
    }
}

struct ChangedFilesSummaryView: View {
    let changedFiles: [CommitFileChange]
    let commitSHA: String
    let remoteURL: String
    var onOpenLocalFile: ((String) -> Void)?

    @State private var showsAllFiles = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private let aggregateStat: DiffTreeStat
    private let groups: [ChangedFilesGroup]

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

        aggregateStat = DiffTreeBuilder.summarizeDiffTreeStats(changedFiles.map(\.diffTreeFileInput))
        groups = Self.makeGroups(from: changedFiles)
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

    private var totalChangedLines: Int {
        aggregateStat.additions + aggregateStat.deletions
    }

    private var isTruncated: Bool {
        changedFiles.count > ChangedFilesListMetrics.collapsedFileLimit && !showsAllFiles
    }

    private var visibleGroups: [ChangedFilesGroup] {
        guard isTruncated else {
            return groups
        }

        var remaining = ChangedFilesListMetrics.collapsedFileLimit
        var truncated: [ChangedFilesGroup] = []

        for group in groups {
            guard remaining > 0 else {
                break
            }
            let files = Array(group.files.prefix(remaining))
            remaining -= files.count
            truncated.append(ChangedFilesGroup(label: group.label, files: files))
        }

        return truncated
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
            if changedFiles.isEmpty {
                Text("No file list available for this commit.")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
            } else {
                summaryRow
                fileList
            }
        }
        .onChange(of: changedFiles) {
            showsAllFiles = false
        }
    }

    private var summaryRow: some View {
        HStack(spacing: WorkbenchMetrics.chipSpacing) {
            Text(changedFilesTitle)
                .font(WorkbenchTypography.body)
                .lineLimit(1)
                .layoutPriority(1)

            WorkingTreeLineDiffView(
                addedCount: aggregateStat.additions,
                removedCount: aggregateStat.deletions
            )

            proportionBar

            Spacer(minLength: WorkbenchMetrics.compactSpacing)

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
        .padding(.vertical, WorkbenchMetrics.headerVerticalPadding)
        .padding(.horizontal, WorkbenchMetrics.microSpacing)
    }

    private var proportionBar: some View {
        HStack(spacing: 0) {
            if totalChangedLines == 0 {
                Rectangle()
                    .fill(WorkbenchPalette.neutralBorder(contrast: colorSchemeContrast))
            } else {
                if aggregateStat.additions > 0 {
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: proportionWidth(for: aggregateStat.additions))
                }
                if aggregateStat.deletions > 0 {
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: proportionWidth(for: aggregateStat.deletions))
                }
            }
        }
        .frame(
            width: ChangedFilesListMetrics.proportionBarWidth,
            height: ChangedFilesListMetrics.proportionBarHeight
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: ChangedFilesListMetrics.proportionBarCornerRadius,
                style: .continuous
            )
        )
        .accessibilityHidden(true)
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
            ForEach(visibleGroups) { group in
                groupSection(group)
            }

            if isTruncated {
                Button("Show All \(changedFiles.count) Files") {
                    showsAllFiles = true
                }
                .workbenchGhost()
                .font(WorkbenchTypography.captionStrong)
                .accessibilityLabel("Show all \(changedFiles.count) changed files")
            }
        }
        .padding(.leading, WorkbenchMetrics.microSpacing)
        .animation(
            WorkbenchMotion.adaptive(WorkbenchMotion.settle, usesReducedMotion: reduceMotion),
            value: showsAllFiles
        )
    }

    private func groupSection(_ group: ChangedFilesGroup) -> some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
            Text(group.label)
                .font(WorkbenchTypography.captionStrong)
                .textCase(.uppercase)
                .tracking(WorkbenchTypography.tracking(for: .caption))
                .foregroundStyle(.secondary)
                .accessibilityLabel(group.label)
                .accessibilityAddTraits(.isHeader)

            ForEach(group.files) { file in
                ChangedFilesFileRow(
                    file: file,
                    directoryTitle: relativeDirectory(for: file, in: group)
                ) {
                    openFile(at: file.path)
                }
            }
        }
    }

    private func proportionWidth(for count: Int) -> CGFloat {
        guard totalChangedLines > 0 else {
            return 0
        }
        return ChangedFilesListMetrics.proportionBarWidth
            * CGFloat(count)
            / CGFloat(totalChangedLines)
    }

    /// Nearest directory under the group label. The group already names the
    /// top-level folder, so the row keeps the shortest distinguishing context
    /// and the full path stays in the row tooltip.
    private func relativeDirectory(for file: CommitFileChange, in group: ChangedFilesGroup) -> String {
        let directory = file.directoryPath
        guard !directory.isEmpty, directory != group.label else {
            return ""
        }

        let prefix = "\(group.label)/"
        let relative = directory.hasPrefix(prefix) ? String(directory.dropFirst(prefix.count)) : directory
        return relative.split(separator: "/").last.map(String.init) ?? ""
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

    private static func makeGroups(from files: [CommitFileChange]) -> [ChangedFilesGroup] {
        var order: [String] = []
        var filesByLabel: [String: [CommitFileChange]] = [:]

        for file in files {
            let label = groupLabel(for: file.path)
            if filesByLabel[label] == nil {
                order.append(label)
                filesByLabel[label] = []
            }
            filesByLabel[label]?.append(file)
        }

        return order.map { ChangedFilesGroup(label: $0, files: filesByLabel[$0] ?? []) }
    }

    private static func groupLabel(for path: String) -> String {
        let segments = path
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
        guard let topLevel = segments.first, segments.count > 1 else {
            return "Root"
        }
        return String(topLevel)
    }
}

private struct ChangedFilesFileRow: View {
    let file: CommitFileChange
    let directoryTitle: String
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: WorkbenchMetrics.chipSpacing) {
                FileTypeIconView(path: file.path)

                // Directory context appears only when it fits whole; the
                // row tooltip always carries the full path.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: WorkbenchMetrics.chipSpacing) {
                        fileNameLabel
                            .fixedSize()
                        if !directoryTitle.isEmpty {
                            Text(directoryTitle)
                                .font(WorkbenchTypography.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }

                    fileNameLabel
                        .truncationMode(.middle)
                }
                .layoutPriority(1)

                Spacer(minLength: WorkbenchMetrics.compactSpacing)

                lineDiffLabel
            }
            .padding(.horizontal, WorkbenchMetrics.chipSpacing)
            .frame(minHeight: ChangedFilesListMetrics.rowMinHeight)
            .background(isHovered ? WorkbenchPalette.hoverFill() : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(file.path)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens this file.")
    }

    private var fileNameLabel: some View {
        Text(file.fileName)
            .font(WorkbenchTypography.body)
            .foregroundStyle(.primary)
            .lineLimit(1)
    }

    private var lineDiffLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: WorkbenchMetrics.microSpacing) {
            Text("+\(file.lineDiff.added)")
                .foregroundStyle(file.lineDiff.added > 0 ? .green : .secondary)
            Text("-\(file.lineDiff.removed)")
                .foregroundStyle(file.lineDiff.removed > 0 ? .red : .secondary)
        }
        .font(WorkbenchTypography.captionStrong.monospacedDigit())
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityHidden(true)
    }

    private var accessibilityLabel: String {
        var label = file.fileName
        if file.lineDiff.added > 0 {
            label += ", \(file.lineDiff.added) additions"
        }
        if file.lineDiff.removed > 0 {
            label += ", \(file.lineDiff.removed) deletions"
        }
        return label
    }
}
