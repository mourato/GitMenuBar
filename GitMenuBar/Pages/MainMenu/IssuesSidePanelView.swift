import SwiftUI

/// Side panel that lists the selected project's GitHub issues, open by
/// default with a switch to closed ones. Rows open the issue on GitHub; each
/// row's tag menu applies or removes repository labels.
struct IssuesSidePanelView: View {
    let projectName: String
    let remoteURL: String
    let isAuthenticated: Bool
    let onClose: () -> Void

    @State private var model: IssueListModel
    @State private var stateFilter: GitHubIssueState = .open
    @State private var showsLabelCreation = false
    @Environment(\.openURL) private var openURL

    init(
        projectName: String,
        remoteURL: String,
        isAuthenticated: Bool,
        model: IssueListModel,
        onClose: @escaping () -> Void
    ) {
        self.projectName = projectName
        self.remoteURL = remoteURL
        self.isAuthenticated = isAuthenticated
        self.onClose = onClose
        _model = State(initialValue: model)
    }

    private struct LoadKey: Equatable {
        let remoteURL: String
        let state: GitHubIssueState
        let isAuthenticated: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
            SidePanelHeaderView(projectName: projectName, title: "Issues", onClose: onClose)
            controls
            labelStatus
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .task(id: LoadKey(remoteURL: remoteURL, state: stateFilter, isAuthenticated: isAuthenticated)) {
            await model.load(remoteURL: remoteURL, state: stateFilter)
        }
        .sheet(isPresented: $showsLabelCreation) {
            IssueLabelCreationSheet(
                repositoryName: repositoryDisplayName,
                isSaving: model.isCreatingLabel,
                errorMessage: model.labelCreationError.map(IssueLabelMessages.creation),
                onCancel: {
                    showsLabelCreation = false
                    model.clearLabelCreationError()
                },
                onCreate: { name, color, description in
                    Task {
                        if await model.createLabel(name: name, color: color, description: description) {
                            showsLabelCreation = false
                        }
                    }
                }
            )
        }
    }

    /// Names the repository the new label belongs to, even before its remote
    /// resolves.
    private var repositoryDisplayName: String {
        guard let repository = model.repository else { return projectName }
        return "\(repository.owner)/\(repository.repository)"
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
            if let repository = model.repository {
                Text("\(repository.owner)/\(repository.repository)")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityLabel("Repository \(repository.owner)/\(repository.repository)")
            }
            HStack(spacing: WorkbenchMetrics.compactSpacing) {
                Picker("Issue state", selection: $stateFilter) {
                    Text("Open").tag(GitHubIssueState.open)
                    Text("Closed").tag(GitHubIssueState.closed)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                Spacer(minLength: 0)

                Button("Refresh Issues", systemImage: "arrow.clockwise") {
                    Task { await model.refresh() }
                }
                .labelStyle(.iconOnly)
                .workbenchIcon()
                .help("Refresh issues")
                .disabled(model.phase == .loading || model.repository == nil)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .loading:
            ProgressView("Loading issues")
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(error):
            failureView(error)
        case .loaded where model.issues.isEmpty:
            ContentUnavailableView(
                stateFilter == .open ? "No Open Issues" : "No Closed Issues",
                systemImage: "checkmark.circle",
                description: Text("This repository has no \(stateFilter == .open ? "open" : "closed") issues.")
            )
        case .loaded:
            issueList
        }
    }

    @ViewBuilder
    private var labelStatus: some View {
        if model.phase == .loaded {
            if let error = model.labelError {
                IssueLabelStatusView(
                    text: IssueLabelMessages.mutation(error),
                    systemImage: "exclamationmark.triangle",
                    retry: model.canEditLabels ? { Task { await model.retryLastLabelChange() } } : nil
                )
            } else if case let .failed(error) = model.labelsPhase {
                IssueLabelStatusView(
                    text: IssueLabelMessages.list(error),
                    systemImage: "exclamationmark.triangle",
                    retry: { Task { await model.reloadLabels() } }
                )
            } else if model.labelsPhase == .loaded, !model.canEditLabels {
                IssueLabelStatusView(
                    text: "Labels are read-only in this repository. Your GitHub account can view them but not change them.",
                    systemImage: "lock",
                    retry: nil
                )
            }
        }
    }

    private var issueList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                ForEach(model.issues) { issue in
                    HStack(alignment: .top, spacing: WorkbenchMetrics.microSpacing) {
                        Button {
                            openURL(issue.url)
                        } label: {
                            IssueRowView(issue: issue)
                        }
                        .workbenchRow()
                        .help("Open issue #\(issue.number) on GitHub")
                        .accessibilityHint("Opens on GitHub")

                        IssueLabelMenu(
                            issue: issue,
                            labels: model.availableLabels,
                            canEdit: model.canEditLabels && model.labelsPhase == .loaded,
                            canCreate: model.canCreateLabels,
                            isPending: model.pendingLabelChange?.issueNumber == issue.number,
                            isEnabled: model.pendingLabelChange == nil,
                            onSet: { label, adding in
                                Task { await model.setLabel(label, on: issue, adding: adding) }
                            },
                            onCreate: {
                                model.clearLabelCreationError()
                                showsLabelCreation = true
                            }
                        )
                        .padding(.top, WorkbenchMetrics.microSpacing)
                    }
                }
                loadMoreFooter
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(stateFilter == .open ? "Open" : "Closed") issues")
    }

    @ViewBuilder
    private var loadMoreFooter: some View {
        if model.isLoadingMore {
            ProgressView("Loading more issues")
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(.vertical, WorkbenchMetrics.compactSpacing)
        } else if model.canLoadMore {
            VStack(spacing: WorkbenchMetrics.microSpacing) {
                if model.loadMoreFailed {
                    Text("Could not load more issues.")
                        .font(WorkbenchTypography.caption)
                        .foregroundStyle(.secondary)
                }
                Button(model.loadMoreFailed ? "Try Again" : "Load More Issues") {
                    Task { await model.loadMore() }
                }
                .workbenchGhost()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, WorkbenchMetrics.compactSpacing)
        }
    }

    @ViewBuilder
    private func failureView(_ error: GitHubIssueListError) -> some View {
        switch error {
        case .notAuthenticated:
            ContentUnavailableView {
                Label("Sign In to GitHub", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text("Connect your GitHub account in Settings to see issues for this project.")
            } actions: {
                openOnGitHubButton
            }
        case .unsupportedRepository:
            ContentUnavailableView(
                "Issues Not Available",
                systemImage: "questionmark.folder",
                description: Text("Issues show only for projects with a github.com remote.")
            )
        case .repositoryNotFound:
            retryableFailure(
                title: "Repository Not Found",
                message: "GitHub did not find this repository, or your account cannot read it."
            )
        case .requestFailed:
            retryableFailure(
                title: "Could Not Load Issues",
                message: "Check your connection and try again."
            )
        }
    }

    private func retryableFailure(title: String, message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task { await model.reload() }
            }
            .workbenchGhost()
            openOnGitHubButton
        }
    }

    /// Keeps the one-click path to the browser when the in-app list fails.
    @ViewBuilder
    private var openOnGitHubButton: some View {
        if let url = URL(string: GitHubRemoteURLParser.normalizedWebURL(from: remoteURL) + "/issues") {
            Button("Open on GitHub") { openURL(url) }
                .workbenchGhost()
        }
    }
}

private struct IssueRowView: View {
    let issue: GitHubIssue

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: WorkbenchMetrics.compactSpacing) {
            Image(systemName: issue.state == .open ? "circle.circle" : "checkmark.circle")
                .foregroundStyle(issue.state == .open ? Color.green : Color.purple)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                Text(issue.title)
                    .font(WorkbenchTypography.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(metadata)
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if !issue.labels.isEmpty {
                    IssueLabelFlowLayout(spacing: WorkbenchMetrics.microSpacing) {
                        ForEach(issue.labels, id: \.self) { label in
                            IssueLabelChip(label: label)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, WorkbenchMetrics.microSpacing)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var author: String {
        issue.authorLogin ?? "deleted user"
    }

    private var metadata: String {
        let opened = HistoryTimelineDateFormatter.relativeTimestamp(for: issue.createdAt)
        let updated = HistoryTimelineDateFormatter.relativeTimestamp(for: issue.updatedAt)
        return "#\(issue.number) opened \(opened) by \(author) · updated \(updated)"
    }

    private var accessibilityText: String {
        var parts = [
            "Issue \(issue.number)",
            issue.title,
            issue.state == .open ? "Open" : "Closed",
            "opened \(HistoryTimelineDateFormatter.relativeTimestamp(for: issue.createdAt)) by \(author)",
            "updated \(HistoryTimelineDateFormatter.relativeTimestamp(for: issue.updatedAt))"
        ]
        if !issue.labels.isEmpty {
            parts.append("Labels: " + issue.labels.map(\.name).joined(separator: ", "))
        }
        return parts.joined(separator: ", ")
    }
}

/// GitHub label rendered with its own color; text switches between black and
/// white by luminance so every label color stays legible.
private struct IssueLabelChip: View {
    let label: GitHubIssueLabel

    var body: some View {
        let color = IssueLabelColor(hex: label.colorHex)
        Text(label.name)
            .font(WorkbenchTypography.captionStrong)
            .lineLimit(1)
            .foregroundStyle(color.prefersDarkText ? Color.black : Color.white)
            .padding(.horizontal, WorkbenchMetrics.chipSpacing)
            .padding(.vertical, 1)
            .background(color.color, in: Capsule())
    }
}

struct IssueLabelColor {
    let red: Double
    let green: Double
    let blue: Double

    init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xBBBBBB
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    /// Picks black text when it contrasts better than white (WCAG luminance).
    var prefersDarkText: Bool {
        func linear(_ channel: Double) -> Double {
            channel <= 0.039_28 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        return (luminance + 0.05) / 0.05 > 1.05 / (luminance + 0.05)
    }
}

/// Wraps label chips onto new lines inside the narrow side panel.
private struct IssueLabelFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var originY = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var originX = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.init(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: originX, y: originY), proposal: .init(size))
                originX += size.width + spacing
            }
            originY += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.init(width: width, height: nil))
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

#Preview("Issues Side Panel") {
    IssuesSidePanelPreview(writeAccess: true)
}

#Preview("Issues Side Panel Read Only") {
    IssuesSidePanelPreview(writeAccess: false)
}

private struct IssuesSidePanelPreview: View {
    let writeAccess: Bool

    var body: some View {
        let now = Date()
        let labels = [
            GitHubIssueLabel(name: "enhancement", colorHex: "a2eeef", nodeID: "L_enh"),
            GitHubIssueLabel(name: "bug", colorHex: "d73a4a", nodeID: "L_bug"),
            GitHubIssueLabel(name: "good first issue", colorHex: "7057ff", nodeID: "L_first")
        ]
        let issues = [
            GitHubIssue(
                number: 42,
                title: "Consultar a lista de issues do projeto dentro do app sem sair do fluxo de trabalho atual",
                state: .open,
                authorLogin: "mourato",
                createdAt: now.addingTimeInterval(-86400 * 3),
                updatedAt: now.addingTimeInterval(-3600),
                labels: Array(labels.prefix(2)),
                url: URL(string: "https://github.com/mourato/GitMenuBar/issues/42")!,
                nodeID: "I_42"
            ),
            GitHubIssue(
                number: 41,
                title: "Badges in the sidebar",
                state: .open,
                authorLogin: nil,
                createdAt: now.addingTimeInterval(-86400 * 10),
                updatedAt: now.addingTimeInterval(-86400 * 2),
                labels: [],
                url: URL(string: "https://github.com/mourato/GitMenuBar/issues/41")!,
                nodeID: "I_41"
            )
        ]
        IssuesSidePanelView(
            projectName: "GitMenuBar",
            remoteURL: "https://github.com/mourato/GitMenuBar.git",
            isAuthenticated: true,
            model: IssueListModel(
                fetchPage: { _, _, _ in GitHubIssuePage(issues: issues, nextCursor: "next") },
                labels: IssueListModel.IssueLabelActions(
                    fetchLabels: { _ in
                        GitHubIssueLabelSnapshot(labels: labels, canWrite: writeAccess, repositoryID: "R_1")
                    },
                    mutateLabel: { _, _, _ in labels },
                    createLabel: { _, name, color, _ in
                        GitHubIssueLabel(name: name, colorHex: color, nodeID: "L_new")
                    }
                )
            ),
            onClose: {}
        )
        .frame(width: WorkbenchMetrics.sidePanelWidth, height: 520)
        .padding()
    }
}
