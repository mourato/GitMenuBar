import AppKit
import SwiftUI

struct BranchManagementSheet: View {
    @ObservedObject var gitManager: GitManager
    @Environment(\.dismiss) private var dismiss

    @State private var branchInfos: [BranchInfo] = []
    @State var worktreeSnapshot: GitWorktreeSnapshot?
    @State private var isLoading = false
    @State private var query: String = ""
    @State private var errorMessage: String?
    @State private var worktreeErrorMessage: String?
    @State private var mode: BranchManagementMode = .branches
    @State var selectedCleanupIDs: Set<String> = []
    @State var showCleanupConfirmation = false
    @State var isCleanupRunning = false
    @State var cleanupResultMessage: String?

    @State private var showCreateBranch = false
    @State private var newBranchName: String = ""

    @State private var showRenameBranch = false
    @State private var renameOldName: String = ""
    @State private var renameNewName: String = ""

    @State private var deleteLocalName: String?
    @State private var deleteRemoteName: String?
    @State private var mergeSourceName: String?

    @State private var operationError: String?

    var selectedCleanupTargets: [GitCleanupTarget] {
        guard let worktreeSnapshot else { return [] }
        let branchTargets = worktreeSnapshot.branches
            .filter { !$0.reference.isRemote && $0.isEligible }
            .filter { selectedCleanupIDs.contains(GitCleanupTarget.localBranch($0).id) }
            .map(GitCleanupTarget.localBranch)
        let worktreeTargets = worktreeSnapshot.worktrees
            .filter(\.status.isEligible)
            .filter { selectedCleanupIDs.contains(GitCleanupTarget.worktree($0).id) }
            .map(GitCleanupTarget.worktree)
        return branchTargets + worktreeTargets
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if isLoading {
                Spacer()
                ProgressView()
                    .controlSize(.regular)
                Spacer()
            } else {
                BranchManagementListView(
                    mode: $mode,
                    query: $query,
                    branchInfos: branchInfos,
                    worktreeSnapshot: worktreeSnapshot,
                    worktreeErrorMessage: worktreeErrorMessage,
                    selectedCleanupIDs: $selectedCleanupIDs,
                    onRevealWorktree: revealWorktree,
                    onCopyPath: copyPath,
                    onDismissError: { worktreeErrorMessage = nil },
                    branchRow: row
                )
            }

            Divider()

            footer
        }
        .frame(width: 560)
        .macPanelSurface(cornerRadius: MacChromeMetrics.largeCornerRadius, material: .regular)
        .onAppear(perform: reloadData)
        .onChange(of: mode) { _, _ in
            query = ""
            selectedCleanupIDs = []
        }
        .alert("Delete Local Branch?", isPresented: Binding(
            get: { deleteLocalName != nil },
            set: {
                if !$0 {
                    deleteLocalName = nil
                }
            }
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
            set: {
                if !$0 {
                    deleteRemoteName = nil
                }
            }
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
            set: {
                if !$0 {
                    mergeSourceName = nil
                }
            }
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
            set: {
                if !$0 {
                    operationError = nil
                }
            }
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
        .sheet(isPresented: $showCleanupConfirmation) {
            CleanupConfirmationView(
                targets: selectedCleanupTargets,
                onCancel: { showCleanupConfirmation = false },
                onConfirm: performCleanup
            )
        }
        .alert(
            "Cleanup Results",
            isPresented: Binding(
                get: { cleanupResultMessage != nil },
                set: {
                    if !$0 {
                        cleanupResultMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) { cleanupResultMessage = nil }
        } message: {
            if let cleanupResultMessage {
                Text(cleanupResultMessage)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Branch Management")
                .font(.headline.weight(.semibold))
            Spacer()
            Button {
                dismiss()
            } label: {
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

            if mode == .branches {
                Button {
                    showCreateBranch = true
                } label: {
                    Label("New Branch…", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            } else if mode == .cleanup {
                Button("Clean Up Selected") {
                    showCleanupConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || isCleanupRunning || selectedCleanupTargets.isEmpty)
                .help(
                    selectedCleanupTargets.isEmpty
                        ? "Select an eligible branch or worktree first."
                        : "Review the selected cleanup items."
                )
            }
        }
        .padding(16)
    }

    private func row(for branch: BranchInfo) -> BranchManagementRowView {
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

    func reloadData() {
        isLoading = true
        errorMessage = nil
        worktreeErrorMessage = nil
        Task {
            async let branchResult = gitManager.resolveBranchInfoAsync()
            async let snapshotResult = gitManager.resolveWorktreeSnapshotAsync()
            _ = await branchResult
            let resolvedSnapshot = await snapshotResult
            await MainActor.run {
                self.branchInfos = gitManager.branchInfos
                switch resolvedSnapshot {
                case let .success(snapshot):
                    self.worktreeSnapshot = snapshot
                    self.selectedCleanupIDs = []
                case let .failure(error):
                    self.worktreeSnapshot = nil
                    self.worktreeErrorMessage = error.localizedDescription
                }
                self.isLoading = false
            }
        }
    }

    private func revealWorktree(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func copyPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
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
