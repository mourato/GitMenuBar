import AppKit
import SwiftUI

struct BranchManagementSheet: View {
    @ObservedObject var gitManager: GitManager
    @Environment(\.dismiss) private var dismiss

    @State private var branchInfos: [BranchInfo] = []
    @State private var isLoading = false
    @State private var query: String = ""
    @State private var errorMessage: String?

    @State private var showCreateBranch = false
    @State private var newBranchName: String = ""

    @State private var showRenameBranch = false
    @State private var renameOldName: String = ""
    @State private var renameNewName: String = ""

    @State private var deleteLocalName: String?
    @State private var deleteRemoteName: String?
    @State private var mergeSourceName: String?

    @State private var operationError: String?

    private var localInfos: [BranchInfo] {
        filteredInfos { $0.isLocal }
    }

    private var remoteInfos: [BranchInfo] {
        filteredInfos { $0.isRemote }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter branches", text: $query)
                        .textFieldStyle(.plain)
                        .font(MacChromeTypography.body)
                    if !query.isEmpty {
                        Button(action: { query = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: MacChromeMetrics.rowCornerRadius, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if isLoading {
                Spacer()
                ProgressView()
                    .controlSize(.regular)
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeader("Local Branches", infos: localInfos)
                        if localInfos.isEmpty {
                            emptyHint
                        } else {
                            ForEach(localInfos) { row(for: $0) }
                        }

                        sectionHeader("Remote Branches", infos: remoteInfos)
                        if remoteInfos.isEmpty {
                            emptyHint
                        } else {
                            ForEach(remoteInfos) { row(for: $0) }
                        }
                    }
                    .padding(16)
                }
                .frame(maxHeight: 420)
            }

            Divider()

            footer
        }
        .frame(width: 460)
        .macPanelSurface(cornerRadius: MacChromeMetrics.largeCornerRadius)
        .onAppear(perform: reloadData)
        .alert("Delete Local Branch?", isPresented: Binding(
            get: { deleteLocalName != nil },
            set: { if !$0 { deleteLocalName = nil } }
        )) {
            Button("Delete", role: .destructive) {
                guard let name = deleteLocalName else { return }
                deleteLocalName = nil
                performDeleteLocal(name)
            }
            Button("Cancel", role: .cancel) { deleteLocalName = nil }
        } message: {
            if let name = deleteLocalName {
                Text("This will permanently delete the local branch '\(name)'. This cannot be undone.")
            }
        }
        .alert("Delete Remote Branch?", isPresented: Binding(
            get: { deleteRemoteName != nil },
            set: { if !$0 { deleteRemoteName = nil } }
        )) {
            Button("Delete", role: .destructive) {
                guard let name = deleteRemoteName else { return }
                deleteRemoteName = nil
                performDeleteRemote(name)
            }
            Button("Cancel", role: .cancel) { deleteRemoteName = nil }
        } message: {
            if let name = deleteRemoteName {
                Text("This will permanently delete 'origin/\(name)' on the remote. This cannot be undone.")
            }
        }
        .alert("Merge into Current Branch?", isPresented: Binding(
            get: { mergeSourceName != nil },
            set: { if !$0 { mergeSourceName = nil } }
        )) {
            Button("Merge") {
                guard let name = mergeSourceName else { return }
                mergeSourceName = nil
                performMerge(name)
            }
            Button("Cancel", role: .cancel) { mergeSourceName = nil }
        } message: {
            if let name = mergeSourceName {
                Text("Bring all changes from '\(name)' into '\(gitManager.currentBranch)'.")
            }
        }
        .alert("Operation Failed", isPresented: Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button("OK", role: .cancel) { operationError = nil }
        } message: {
            if let operationError {
                Text(operationError)
            }
        }
        .sheet(isPresented: $showCreateBranch) {
            CreateBranchSheet(
                branchName: $newBranchName,
                currentBranch: gitManager.currentBranch,
                errorMessage: errorMessage,
                onCancel: {
                    showCreateBranch = false
                    newBranchName = ""
                    errorMessage = nil
                },
                onCreate: performCreateBranch
            )
        }
        .sheet(isPresented: $showRenameBranch) {
            RenameBranchSheet(
                oldBranchName: renameOldName,
                newBranchName: $renameNewName,
                errorMessage: errorMessage,
                onCancel: {
                    showRenameBranch = false
                    renameOldName = ""
                    renameNewName = ""
                    errorMessage = nil
                },
                onRename: performRenameBranch
            )
        }
    }

    private var header: some View {
        HStack {
            Text("Branch Management")
                .font(.headline.weight(.semibold))
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            Button(action: reloadData) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(isLoading)

            Spacer()

            Button(action: { showCreateBranch = true }) {
                Label("New Branch…", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }

    private func sectionHeader(_ title: String, infos _: [BranchInfo]) -> some View {
        Text(title)
            .font(MacChromeTypography.sectionLabel)
            .foregroundStyle(.secondary)
    }

    private var emptyHint: some View {
        Text("No branches match your filter.")
            .font(MacChromeTypography.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }

    private func row(for branch: BranchInfo) -> some View {
        BranchManagementRowView(
            branch: branch,
            onSwitch: { performSwitch(branch) },
            onRename: {
                renameOldName = branch.name
                renameNewName = branch.name
                showRenameBranch = true
            },
            onDelete: { deleteLocalName = branch.name },
            onPush: branch.isLocal ? { performPush(branch) } : nil,
            onMerge: branch.isLocal ? { mergeSourceName = branch.name } : nil,
            onDeleteRemote: branch.isRemote ? { deleteRemoteName = branch.name } : nil,
            onCheckoutLocally: branch.isRemote ? { performCheckoutLocally(branch) } : nil
        )
    }

    private func filteredInfos(matching predicate: (BranchInfo) -> Bool) -> [BranchInfo] {
        branchInfos
            .filter(predicate)
            .filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) }
            .sorted { lhs, rhs in
                if lhs.isCurrent != rhs.isCurrent {
                    return lhs.isCurrent
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private func reloadData() {
        isLoading = true
        errorMessage = nil
        Task {
            _ = await gitManager.resolveBranchInfoAsync()
            await MainActor.run {
                self.branchInfos = gitManager.branchInfos
                self.isLoading = false
            }
        }
    }

    private func performSwitch(_ branch: BranchInfo) {
        let name = branch.displayName
        gitManager.switchBranch(branchName: name) { result in
            if case let .failure(error) = result {
                operationError = error.localizedDescription
            }
            reloadData()
        }
    }

    private func performCheckoutLocally(_ branch: BranchInfo) {
        gitManager.switchBranch(branchName: "origin/\(branch.name)") { result in
            if case let .failure(error) = result {
                operationError = error.localizedDescription
            }
            reloadData()
        }
    }

    private func performPush(_ branch: BranchInfo) {
        Task {
            let result = await gitManager.pushBranchToRemoteAsync(branchName: branch.name)
            await MainActor.run {
                if case let .failure(error) = result {
                    operationError = error.localizedDescription
                }
                reloadData()
            }
        }
    }

    private func performDeleteLocal(_ name: String) {
        if name == gitManager.currentBranch {
            operationError = "Cannot delete the currently checked out branch."
            return
        }
        gitManager.deleteBranch(branchName: name) { result in
            if case let .failure(error) = result {
                operationError = error.localizedDescription
            }
            reloadData()
        }
    }

    private func performDeleteRemote(_ name: String) {
        Task {
            let result = await gitManager.deleteRemoteBranchAsync(branchName: name)
            await MainActor.run {
                if case let .failure(error) = result {
                    operationError = error.localizedDescription
                }
                reloadData()
            }
        }
    }

    private func performMerge(_ name: String) {
        gitManager.mergeBranch(fromBranch: name) { result in
            if case let .failure(error) = result {
                operationError = error.localizedDescription
            }
            reloadData()
        }
    }

    private func performCreateBranch() {
        let name = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        errorMessage = nil
        gitManager.createBranch(branchName: name) { result in
            switch result {
            case .success:
                showCreateBranch = false
                newBranchName = ""
                reloadData()
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func performRenameBranch() {
        let newName = renameNewName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }
        errorMessage = nil
        gitManager.renameBranch(oldName: renameOldName, newName: newName) { result in
            switch result {
            case .success:
                showRenameBranch = false
                renameOldName = ""
                renameNewName = ""
                reloadData()
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview("Branch Management Sheet") {
    BranchManagementSheet(
        gitManager: GitManager(repositoryPathOverride: NSHomeDirectory())
    )
    .frame(width: 460)
}
