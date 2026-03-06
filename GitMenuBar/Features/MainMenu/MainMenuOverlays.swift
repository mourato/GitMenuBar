//
//  MainMenuOverlays.swift
//  GitMenuBar
//

import SwiftUI

extension MainMenuView {
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    func applyMainViewOverlays<Content: View>(to view: Content) -> some View {
        view
            .alert("Push Failed", isPresented: .init(
                get: { pushError != nil },
                set: { if !$0 { pushError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(pushError ?? "An unknown error occurred.")
            }
            .alert("Sync Failed", isPresented: .init(
                get: { syncError != nil },
                set: { if !$0 { syncError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(syncError ?? "An unknown error occurred.")
            }
            .alert("Branch Switch Failed", isPresented: .init(
                get: { branchSwitchError != nil },
                set: { if !$0 { branchSwitchError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(branchSwitchError ?? "An unknown error occurred.")
            }
            .alert("Merge Failed", isPresented: .init(
                get: { mergeError != nil },
                set: { if !$0 { mergeError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(mergeError ?? "An unknown error occurred.")
            }
            .alert("Delete Failed", isPresented: .init(
                get: { deleteBranchError != nil },
                set: { if !$0 { deleteBranchError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteBranchError ?? "An unknown error occurred.")
            }
            .alert("Rename Failed", isPresented: .init(
                get: { renameBranchError != nil },
                set: { if !$0 { renameBranchError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(renameBranchError ?? "An unknown error occurred.")
            }
            .alert("Merge into \(mergeTargetBranch)?", isPresented: $showMergeConfirmation) {
                Button("Merge") {
                    gitManager.mergeBranch(fromBranch: mergeBranchName) { result in
                        if case let .failure(error) = result {
                            mergeError = error.localizedDescription
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    mergeBranchName = ""
                    mergeTargetBranch = ""
                }
            } message: {
                Text("This will bring all changes from '\(mergeBranchName)' into your current branch '\(mergeTargetBranch)'.")
            }
            .alert("Uncommitted Changes", isPresented: $showDirtySwitchConfirmation) {
                Button("Switch & Carry Over") {
                    gitManager.switchBranch(branchName: pendingSwitchBranch) { result in
                        if case let .failure(error) = result {
                            branchSwitchError = error.localizedDescription
                        }
                    }
                    pendingSwitchBranch = ""
                }
                Button("Cancel", role: .cancel) {
                    pendingSwitchBranch = ""
                }
            } message: {
                Text("You have uncommitted changes. They will follow you to '\(pendingSwitchBranch)'.")
            }
            .alert("Delete '\(branchNameToDelete)'?", isPresented: $showBranchDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    gitManager.deleteBranch(branchName: branchNameToDelete) { result in
                        if case let .failure(error) = result {
                            deleteBranchError = error.localizedDescription
                        }
                    }
                    branchNameToDelete = ""
                }
                Button("Cancel", role: .cancel) {
                    branchNameToDelete = ""
                }
            } message: {
                Text(
                    (branchNameToDelete == "main" || branchNameToDelete == "master" || branchNameToDelete == "develop") ?
                        "WARNING: '\(branchNameToDelete)' is a primary branch. Deleting it may cause serious issues." :
                        "Are you sure you want to delete this branch? This action cannot be undone."
                )
            }

            .sheet(isPresented: $showRenameBranch) {
                VStack(spacing: 16) {
                    Text("Rename Branch")
                        .font(.system(size: 14, weight: .semibold))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("New name for '\(oldBranchName)':")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        TextField("new-branch-name", text: $renameBranchNewName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .onSubmit {
                                renameBranch()
                            }
                    }

                    HStack(spacing: 12) {
                        Button("Cancel") {
                            showRenameBranch = false
                            renameBranchNewName = ""
                        }
                        .keyboardShortcut(.escape, modifiers: [])

                        Spacer()

                        Button("Rename") {
                            renameBranch()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(renameBranchNewName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || renameBranchNewName == oldBranchName)
                    }
                }
                .padding(20)
                .frame(width: 300)
            }
            .sheet(isPresented: $showSyncOptions) {
                VStack(spacing: 16) {
                    Text("Sync with Remote")
                        .font(.system(size: 14, weight: .semibold))

                    Text("Remote has \(gitManager.behindCount) new commit\(gitManager.behindCount == 1 ? "" : "s")")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        Button(action: {
                            useRebase = false
                            syncWithRemote()
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Merge")
                                        .font(.system(size: 12, weight: .medium))
                                    Text("Safe: Creates a merge commit")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.borderless)
                        .buttonStyle(.borderless)

                        Button(action: {
                            useRebase = true
                            syncWithRemote()
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Rebase")
                                        .font(.system(size: 12, weight: .medium))
                                    Text("Clean: Replays your commits on top")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.borderless)

                        Button(action: {
                            showSyncOptions = false
                            pullToNewBranchName = "\(gitManager.currentBranch)-remote"
                            showPullToNewBranch = true
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Pull to New Branch")
                                        .font(.system(size: 12, weight: .medium))
                                    Text("Safe: Creates a fresh branch from remote")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.borderless)
                    }

                    Button("Cancel") {
                        showSyncOptions = false
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                }
                .padding()
                .frame(width: 320)
            }
            .sheet(isPresented: $showCreateBranch) {
                VStack(spacing: 16) {
                    Text("Create New Branch")
                        .font(.system(size: 14, weight: .semibold))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Branch Name")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        TextField("feature/new-feature", text: $newBranchName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .onSubmit {
                                if !newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    createNewBranch()
                                }
                            }

                        if let error = createBranchError {
                            Text(error)
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                        }

                        Text("Will branch from: \(gitManager.currentBranch)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Button("Cancel") {
                            showCreateBranch = false
                            newBranchName = ""
                            createBranchError = nil
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.secondary)

                        Spacer()

                        Button("Create") {
                            createNewBranch()
                        }
                        .buttonStyle(.borderless)
                        .disabled(newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding()
                .frame(width: 320)
            }
            .sheet(isPresented: $showPullToNewBranch) {
                VStack(spacing: 16) {
                    Text("Pull to New Branch")
                        .font(.system(size: 14, weight: .semibold))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Branch name:")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        TextField("branch-name", text: $pullToNewBranchName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .onSubmit {
                                pullToNewBranch()
                            }
                    }

                    HStack(spacing: 12) {
                        Button("Cancel") {
                            showPullToNewBranch = false
                            pullToNewBranchName = ""
                        }
                        .keyboardShortcut(.escape, modifiers: [])

                        Spacer()

                        Button("Pull") {
                            pullToNewBranch()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(pullToNewBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding()
                .frame(width: 320)
            }
    }
}

#Preview("Main Overlays") {
    MainMenuPreviewHarness {
        MainMenuView()
    }
}
