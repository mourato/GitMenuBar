import SwiftUI

struct ProjectSelectorPopoverView: View {
    let recentProjects: [ProjectReference]
    let currentRepoPath: String
    let onSelectPath: (String) -> Void
    let onBrowse: () -> Void
    let onRenameProject: (String, String) -> Void
    let onRevealProject: (String) -> Void
    let onRemoveProject: (String) -> Void
    let onShowRepositoryOptions: (() -> Void)?
    @State private var renamingProjectPath: String?
    @State private var renameDraft = ""
    @State private var removalProject: ProjectReference?
    @FocusState private var focusedRenameProjectPath: String?

    private var normalizedCurrentRepoPath: String {
        guard !currentRepoPath.isEmpty else {
            return ""
        }
        return RecentProjectsStore.normalize(currentRepoPath)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack {
                    Text("Projects").font(WorkbenchTypography.captionStrong)
                    Spacer()
                    Button(action: onBrowse) {
                        Image(systemName: "folder.badge.plus")
                    }
                    .workbenchIcon()
                    .accessibilityLabel("Add project")
                    .help("Choose a repository folder to add to GitMenuBar.")
                }
                .padding(.horizontal, WorkbenchMetrics.panelPadding)
                .padding(.vertical, WorkbenchMetrics.compactSpacing)
                .background(Color.clear)

                List {
                    ForEach(recentProjects) { project in
                        ProjectSelectorRowView(
                            project: project,
                            isCurrent: project.path == normalizedCurrentRepoPath,
                            isRenaming: project.path == renamingProjectPath,
                            renameDraft: $renameDraft,
                            focusedRenameProjectPath: $focusedRenameProjectPath,
                            onSelect: {
                                cancelRename()
                                onSelectPath(project.path)
                            },
                            onRename: { beginRename(project) },
                            onCommitRename: commitRename,
                            onCancelRename: cancelRename,
                            onReveal: { onRevealProject(project.path) },
                            onRemove: { removalProject = project },
                            onShowRepositoryOptions: project.path == normalizedCurrentRepoPath ? onShowRepositoryOptions : nil
                        )
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .workbenchPanelSurface(material: .thin)
        .frame(width: 300, height: 260)
        .alert(item: $removalProject) { project in
            let isCurrent = project.path == normalizedCurrentRepoPath
            return Alert(
                title: Text("Remove \u{201c}\(project.name)\u{201d}?"),
                message: Text(
                    "This only removes the project from this list. The folder, local repository, and remote repository are not deleted."
                        + (isCurrent ? " GitMenuBar will stop using it until you choose it again." : "")
                ),
                primaryButton: .cancel(),
                secondaryButton: .destructive(Text("Remove")) { onRemoveProject(project.path) }
            )
        }
        .onExitCommand {
            if renamingProjectPath != nil {
                cancelRename()
            }
        }
    }

    private func beginRename(_ project: ProjectReference) {
        renameDraft = project.name
        renamingProjectPath = project.path
        DispatchQueue.main.async {
            focusedRenameProjectPath = project.path
        }
    }

    private func commitRename() {
        guard let renamingProjectPath else { return }
        onRenameProject(renamingProjectPath, renameDraft)
        cancelRename()
    }

    private func cancelRename() {
        renamingProjectPath = nil
        focusedRenameProjectPath = nil
        renameDraft = ""
    }
}

private struct ProjectSelectorRowView: View {
    let project: ProjectReference
    let isCurrent: Bool
    let isRenaming: Bool
    @Binding var renameDraft: String
    var focusedRenameProjectPath: FocusState<String?>.Binding
    let onSelect: () -> Void
    let onRename: () -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    let onReveal: () -> Void
    let onRemove: () -> Void
    let onShowRepositoryOptions: (() -> Void)?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            if isRenaming {
                editingContent
            } else {
                displayContent
            }

            if isRenaming {
                Button(action: onCommitRename) {
                    Image(systemName: "checkmark")
                }
                .workbenchIcon()
                .accessibilityLabel("Save project name")

                Button(action: onCancelRename) {
                    Image(systemName: "xmark")
                }
                .workbenchIcon()
                .accessibilityLabel("Cancel rename")
            } else {
                Menu {
                    Button("Rename project", action: onRename)
                    Button("Reveal in Finder", action: onReveal)
                    Button("Remove project", role: .destructive, action: onRemove)
                    if let onShowRepositoryOptions {
                        Divider(); Button("Repository options", action: onShowRepositoryOptions)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuIndicator(.hidden)
                .workbenchIcon()
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
                .accessibilityHidden(!isHovered)
                .accessibilityLabel("Project actions for \(project.name)")
            }
        }
        .onHover { isHovered = $0 }
        .contextMenu {
            if isRenaming {
                Button("Save project name", action: onCommitRename)
                Button("Cancel rename", action: onCancelRename)
            } else {
                Button("Rename project", action: onRename)
                Button("Reveal in Finder", action: onReveal)
                Button("Remove project", role: .destructive, action: onRemove)
                if let onShowRepositoryOptions {
                    Divider(); Button("Repository options", action: onShowRepositoryOptions)
                }
            }
        }
    }

    private var displayContent: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                projectStatusIcon
                projectLabels(name: project.name)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .workbenchRow(isSelected: isCurrent)
        .accessibilityLabel(isCurrent ? "\(project.name), current project" : project.name)
        .accessibilityHint("Switches to this project.")
    }

    private var editingContent: some View {
        HStack(spacing: 6) {
            projectStatusIcon
            VStack(alignment: .leading, spacing: 2) {
                TextField("Project name", text: $renameDraft)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled(true)
                    .focused(focusedRenameProjectPath, equals: project.path)
                    .onSubmit(onCommitRename)
                    .accessibilityLabel("Project name")
                    .accessibilityHint("Enter a local display name for this project.")
                Text(PathDisplayFormatter.abbreviatedPath(project.path))
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .workbenchRow(isSelected: isCurrent)
    }

    private var projectStatusIcon: some View {
        Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
    }

    private func projectLabels(name: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(WorkbenchTypography.body).lineLimit(1)
            Text(PathDisplayFormatter.abbreviatedPath(project.path))
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

#Preview("Project Selector") {
    ProjectSelectorPopoverView(
        recentProjects: [
            ProjectReference(path: "/tmp/gitmenubar"),
            ProjectReference(path: "/tmp/assistant", name: "Assistant")
        ],
        currentRepoPath: "/tmp/gitmenubar",
        onSelectPath: { _ in },
        onBrowse: {},
        onRenameProject: { _, _ in },
        onRevealProject: { _ in },
        onRemoveProject: { _ in },
        onShowRepositoryOptions: {}
    )
}
