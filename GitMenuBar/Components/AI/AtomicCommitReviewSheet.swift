import SwiftUI

struct AtomicCommitReviewSheet: View {
    @ObservedObject var gitManager: GitManager
    let generateGroups: () async throws -> [AtomicCommitGroup]
    let onCancel: () -> Void
    let onCommit: ([AtomicCommitGroup]) -> Void

    @State private var groups: [AtomicCommitGroup] = []
    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if isGenerating {
                loadingState
            } else if let errorMessage {
                errorState(message: errorMessage)
            } else {
                groupsState
            }
        }
        .padding(20)
        .frame(width: 520)
        .workbenchPanelSurface(cornerRadius: WorkbenchMetrics.largeCornerRadius, material: .thick)
        .onAppear(perform: generateIfNeeded)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Review Atomic Commits")
                .font(.headline.weight(.semibold))
            Text("Grouped changes into logical commits. Edit messages, move files between groups, then create the commits.")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.regular)
            Text("Analyzing changes with AI")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message)
                .font(WorkbenchTypography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Retry with AI") { Task { await regenerate() } }
                Button("Use One Group Per File") { fallbackToPerFile() }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private var groupsState: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(groups.indices, id: \.self) { index in
                        groupCard(index: index)
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: 360)

            HStack {
                Button(action: addEmptyGroup) {
                    Label("Add Group", systemImage: "plus")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("Regenerate", action: { Task { await regenerate() } })
                    .buttonStyle(.borderless)
            }

            Divider()

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button(action: commit) {
                    Text("Create \(groups.count) Commit\(groups.count == 1 ? "" : "s")")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(groups.isEmpty || groups.allSatisfy(\.files.isEmpty))
            }
        }
    }

    private func groupCard(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Group \(index + 1)")
                    .font(WorkbenchTypography.captionStrong)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(groups[index].fileCount) file\(groups[index].fileCount == 1 ? "" : "s")")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
                if groups.count > 1 {
                    Button {
                        removeGroup(at: index)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove group")
                }
            }

            TextField("Commit message", text: $groups[index].message)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(groups[index].files, id: \.self) { file in
                    fileRow(file: file, groupIndex: index)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
    }

    private func fileRow(file: String, groupIndex: Int) -> some View {
        HStack(spacing: 8) {
            FileTypeIconView(path: file)
            Text(file)
                .font(WorkbenchTypography.body)
                .lineLimit(1)
            Spacer()
            HStack(spacing: 4) {
                if groupIndex > 0 {
                    Button {
                        moveFile(file, from: groupIndex, to: groupIndex - 1)
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.plain)
                    .help("Move to previous group")
                }
                if groupIndex < groups.count - 1 {
                    Button {
                        moveFile(file, from: groupIndex, to: groupIndex + 1)
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .buttonStyle(.plain)
                    .help("Move to next group")
                }
                Button {
                    removeFile(file, from: groupIndex)
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Exclude from commits")
            }
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 26)
    }

    private func generateIfNeeded() {
        if groups.isEmpty {
            Task { await regenerate() }
        }
    }

    private func regenerate() async {
        isGenerating = true
        errorMessage = nil
        do {
            let generated = try await generateGroups()
            await MainActor.run {
                groups = generated
                isGenerating = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isGenerating = false
            }
        }
    }

    private func fallbackToPerFile() {
        groups = AtomicCommitGroup.fallbackGroups(for: gitManager.changedFiles)
        errorMessage = nil
    }

    private func addEmptyGroup() {
        groups.append(AtomicCommitGroup(files: [], message: ""))
    }

    private func removeGroup(at index: Int) {
        groups.remove(at: index)
    }

    private func moveFile(_ file: String, from source: Int, to target: Int) {
        guard groups.indices.contains(source), groups.indices.contains(target) else { return }
        groups[source].files.removeAll { $0 == file }
        if !groups[target].files.contains(file) {
            groups[target].files.append(file)
        }
    }

    private func removeFile(_ file: String, from groupIndex: Int) {
        groups[groupIndex].files.removeAll { $0 == file }
    }

    private func commit() {
        let commitGroups = groups.filter { !$0.files.isEmpty }
        onCommit(commitGroups)
    }
}

#Preview("Atomic Commit Review Sheet") {
    AtomicCommitReviewSheet(
        gitManager: GitManager(repositoryPathOverride: NSHomeDirectory()),
        generateGroups: {
            [
                AtomicCommitGroup(files: ["Sources/Feature/api.swift"], message: "feat: add endpoint"),
                AtomicCommitGroup(files: ["Sources/Utils/helper.swift"], message: "refactor: extract helper")
            ]
        },
        onCancel: {},
        onCommit: { _ in }
    )
}
