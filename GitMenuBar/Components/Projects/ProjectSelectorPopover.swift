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
    @State private var renameProject: ProjectReference?
    @State private var renameDraft = ""
    @State private var removalProject: ProjectReference?
    @FocusState private var renameFocused: Bool

    private var normalizedCurrentRepoPath: String {
        RecentProjectsStore.normalize(currentRepoPath)
    }

    var body: some View {
        ZStack {
            List {
                Section {
                    ForEach(recentProjects) { project in
                        ProjectSelectorRowView(
                            project: project,
                            isCurrent: project.path == normalizedCurrentRepoPath,
                            onSelect: { onSelectPath(project.path) },
                            onRename: { beginRename(project) },
                            onReveal: { onRevealProject(project.path) },
                            onRemove: { removalProject = project },
                            onShowRepositoryOptions: project.path == normalizedCurrentRepoPath ? onShowRepositoryOptions : nil
                        )
                    }
                } header: {
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
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            if let renameProject {
                VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                    Text("Rename Project").font(WorkbenchTypography.captionStrong)
                    TextField("Project name", text: $renameDraft)
                        .textFieldStyle(.roundedBorder)
                        .focused($renameFocused)
                    Text("Only the name shown in GitMenuBar changes.")
                        .font(WorkbenchTypography.caption).foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button("Cancel", role: .cancel) { self.renameProject = nil }
                        Button("Save") {
                            onRenameProject(renameProject.path, renameDraft)
                            self.renameProject = nil
                        }.keyboardShortcut(.defaultAction)
                    }
                }
                .padding()
                .background(.regularMaterial)
                .onAppear { renameFocused = true }
                .transition(.opacity)
            }
        }
        .workbenchPanelSurface(material: .thin)
        .frame(width: 300, height: 260)
        .alert(item: $removalProject) { project in
            let isCurrent = project.path == normalizedCurrentRepoPath
            return Alert(
                title: Text("Remove \u{201c}\(project.name)\u{201d} from GitMenuBar?"),
                message: Text(
                    "This only removes the project from this list. The folder, local repository, and remote repository are not deleted."
                        + (isCurrent ? " GitMenuBar will stop using it until you choose it again." : "")
                ),
                primaryButton: .cancel(),
                secondaryButton: .destructive(Text("Remove")) { onRemoveProject(project.path) }
            )
        }
        .onExitCommand {
            if renameProject != nil {
                renameProject = nil
            }
        }
    }

    private func beginRename(_ project: ProjectReference) {
        renameDraft = project.name
        renameProject = project
    }
}

private struct ProjectSelectorRowView: View {
    let project: ProjectReference
    let isCurrent: Bool
    let onSelect: () -> Void
    let onRename: () -> Void
    let onReveal: () -> Void
    let onRemove: () -> Void
    let onShowRepositoryOptions: (() -> Void)?
    @State private var isHovered = false
    @State private var menuActive = false

    var body: some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            Button(action: onSelect) {
                HStack(spacing: 6) {
                    Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.name).font(WorkbenchTypography.body).lineLimit(1)
                        Text(PathDisplayFormatter.abbreviatedPath(project.path))
                            .font(WorkbenchTypography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }.buttonStyle(.plain).workbenchRow(isSelected: isCurrent)
            Menu {
                Button("Rename Project…", action: onRename)
                Button("Reveal in Finder", action: onReveal)
                Button("Remove from GitMenuBar…", role: .destructive, action: onRemove)
                if let onShowRepositoryOptions {
                    Divider(); Button("Repository Options…", action: onShowRepositoryOptions)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .workbenchIcon()
            .opacity(isHovered || menuActive ? 1 : 0)
            .allowsHitTesting(isHovered || menuActive)
            .accessibilityLabel("Project actions")
        }
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Rename Project…", action: onRename)
            Button("Reveal in Finder", action: onReveal)
            Button("Remove from GitMenuBar…", role: .destructive, action: onRemove)
            if let onShowRepositoryOptions {
                Divider(); Button("Repository Options…", action: onShowRepositoryOptions)
            }
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
