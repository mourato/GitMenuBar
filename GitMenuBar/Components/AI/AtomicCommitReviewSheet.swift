import SwiftUI

struct AtomicCommitReviewSheet: View {
    @ObservedObject var gitManager: GitManager
    let makeSnapshot: () async -> AtomicCommitSnapshot?
    let generateGroups: (AtomicCommitSnapshot) async throws -> [AtomicCommitGroup]
    let onCancel: () -> Void
    let onCommit: (AtomicCommitExecutionPlan) -> Void

    @State private var groups: [AtomicCommitGroup] = []
    @State private var snapshot: AtomicCommitSnapshot?
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
            Text("Grouped changes into logical commits. Edit messages, move files or hunks between groups, then create the commits.")
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
                .disabled(!isValidDraft)
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
                Text("\(groups[index].selectionCount) item\(groups[index].selectionCount == 1 ? "" : "s")")
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
                ForEach(groups[index].hunks, id: \.self) { hunkID in
                    if let hunk = snapshot?.hunksByID[hunkID] {
                        hunkRow(hunk, groupIndex: index)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
    }

    private func hunkRow(_ hunk: AtomicCommitHunk, groupIndex: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "text.badge.plus")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(hunk.path).lineLimit(1)
                Text("Hunk \(hunk.ordinal) · +\(hunk.additions) / -\(hunk.removals) · \(hunk.header)")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if groupIndex > 0 {
                Button { moveHunk(hunk.id, from: groupIndex, to: groupIndex - 1) } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Move hunk to previous group")
            }
            if groupIndex < groups.count - 1 {
                Button { moveHunk(hunk.id, from: groupIndex, to: groupIndex + 1) } label: {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Move hunk to next group")
            }
            Button { groups[groupIndex].hunks.removeAll { $0 == hunk.id } } label: {
                Image(systemName: "xmark.circle").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Exclude hunk from commits")
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 34)
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
            guard let generatedSnapshot = await makeSnapshot() else {
                throw NSError(domain: "GitManager", code: 35, userInfo: [NSLocalizedDescriptionKey: "Could not capture the working tree snapshot."])
            }
            let generated = try await generateGroups(generatedSnapshot)
            await MainActor.run {
                snapshot = generatedSnapshot
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
        if let snapshot {
            groups = AtomicCommitGroup.fallbackGroups(for: snapshot.files)
        }
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

    private func moveHunk(_ hunk: String, from source: Int, to target: Int) {
        guard groups.indices.contains(source), groups.indices.contains(target) else { return }
        groups[source].hunks.removeAll { $0 == hunk }
        if !groups[target].hunks.contains(hunk) {
            groups[target].hunks.append(hunk)
        }
    }

    private var isValidDraft: Bool {
        guard let snapshot else { return false }
        do {
            _ = try AtomicCommitPlan(groups: groups, allowedFiles: snapshot.allowedFiles, hunksByID: snapshot.hunksByID)
            return true
        } catch {
            return false
        }
    }

    private func commit() {
        guard let snapshot, isValidDraft else { return }
        onCommit(AtomicCommitExecutionPlan(groups: groups, snapshot: snapshot))
    }
}

#Preview("Atomic Commit Review Sheet") {
    let feature = WorkingTreeFile(
        path: "Sources/Feature/api.swift",
        lineDiff: LineDiffStats(added: 2, removed: 1),
        status: .modified
    )
    let helper = WorkingTreeFile(
        path: "Sources/Utils/helper.swift",
        lineDiff: LineDiffStats(added: 8, removed: 0),
        status: .modified
    )
    let snapshot = AtomicCommitSnapshot(
        head: "preview-head",
        fingerprint: "preview-fingerprint",
        files: [feature, helper],
        hunks: [
            AtomicCommitHunk(
                id: "Sources/Feature/api.swift#hunk-1",
                path: feature.path,
                ordinal: 1,
                header: "@@ -10,3 +10,4 @@",
                additions: 1,
                removals: 0,
                patch: ""
            ),
            AtomicCommitHunk(
                id: "Sources/Feature/api.swift#hunk-2",
                path: feature.path,
                ordinal: 2,
                header: "@@ -28,4 +29,5 @@",
                additions: 1,
                removals: 1,
                patch: ""
            )
        ]
    )
    AtomicCommitReviewSheet(
        gitManager: GitManager(repositoryPathOverride: NSHomeDirectory()),
        makeSnapshot: { snapshot },
        generateGroups: { _ in
            [
                AtomicCommitGroup(
                    files: [],
                    hunks: snapshot.hunks.map(\.id),
                    message: "feat: add endpoint"
                ),
                AtomicCommitGroup(
                    files: [helper.path],
                    message: "refactor: extract helper"
                )
            ]
        },
        onCancel: {},
        onCommit: { _ in }
    )
}
