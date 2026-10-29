import SwiftUI

struct CleanupConfirmationView: View {
    let units: [GitCleanupUnit]
    let blocked: [GitCleanupUnit]
    let onCancel: () -> Void
    let onConfirm: ([GitCleanupUnit]) -> Void
    @State private var selectedIDs: Set<String>
    @State private var didReviewRisk = false
    @State private var showsAllReady = false

    private static let collapsedReadyThreshold = 6
    private static let collapsedReadyCount = 4

    init(
        units: [GitCleanupUnit],
        blocked: [GitCleanupUnit] = [],
        onCancel: @escaping () -> Void,
        onConfirm: @escaping ([GitCleanupUnit]) -> Void
    ) {
        self.units = units
        self.blocked = blocked
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _selectedIDs = State(initialValue: Set(units.map(\.id)))
    }

    private var selectedUnits: [GitCleanupUnit] {
        units.filter { selectedIDs.contains($0.id) }
    }

    private var canConfirm: Bool {
        !selectedUnits.isEmpty
    }

    private var pairedSelected: [GitCleanupUnit] {
        selectedUnits.filter { $0.isPaired && !$0.isForceWorktreeRemoval }
    }

    private var forcedSelected: [GitCleanupUnit] {
        selectedUnits.filter(\.isForceWorktreeRemoval)
    }

    private var worktreeOnlySelected: [GitCleanupUnit] {
        selectedUnits.filter { $0.isWorktreeOnlyAction && !$0.isForceWorktreeRemoval }
    }

    private var unmergedSelected: [GitCleanupUnit] {
        selectedUnits.filter(\.isDangerousBranchDeletion)
    }

    private var requiresRiskReview: Bool {
        !pairedSelected.isEmpty || !forcedSelected.isEmpty || !worktreeOnlySelected.isEmpty || !unmergedSelected.isEmpty
    }

    private var visibleReadyUnits: [GitCleanupUnit] {
        guard !showsAllReady, units.count > Self.collapsedReadyThreshold else { return units }
        return Array(units.prefix(Self.collapsedReadyCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text("Clean up")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text("\(selectedUnits.count) selected")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text("Removes the branch and its linked worktree. Reachability is local Git, not PR status.")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
            riskWarnings
            ScrollView {
                VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
                    readySection
                    blockedSection
                }
            }
            .frame(maxHeight: 320)
            footer
        }
        .padding(WorkbenchMetrics.panelPadding)
        .frame(width: 460)
        .workbenchPanelSurface(cornerRadius: WorkbenchMetrics.largeCornerRadius, material: .regular)
        .accessibilityElement(children: .contain)
        .onChange(of: selectedIDs) { _, _ in
            didReviewRisk = false
        }
    }

    @ViewBuilder
    private var riskWarnings: some View {
        if !unmergedSelected.isEmpty, !didReviewRisk {
            Label("Deleting an unmerged branch permanently removes its branch reference and may make its commits harder to recover.", systemImage: "exclamationmark.triangle.fill")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.red)
        }
        if !forcedSelected.isEmpty, !didReviewRisk {
            Label("Force removal permanently deletes this worktree directory and all uncommitted changes. The branch will be kept.", systemImage: "exclamationmark.triangle.fill")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.red)
        }
        if !pairedSelected.isEmpty, !didReviewRisk {
            Label("Paired worktree directories will be removed before their branches.", systemImage: "exclamationmark.triangle.fill")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.orange)
        }
    }

    private var readySection: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
            CleanupSectionHeader(title: "Ready", count: units.count)
            if units.isEmpty {
                Text("Nothing ready to clean.")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleReadyUnits) { unit in
                    readyRow(unit)
                }
                if units.count > Self.collapsedReadyThreshold {
                    disclosureButton
                }
            }
        }
    }

    private var disclosureButton: some View {
        let hiddenCount = units.count - Self.collapsedReadyCount
        return Button {
            showsAllReady.toggle()
        } label: {
            Label(
                showsAllReady ? "Show fewer" : "\(hiddenCount) more",
                systemImage: showsAllReady ? "chevron.up" : "chevron.down"
            )
            .font(WorkbenchTypography.caption)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(showsAllReady ? "Show fewer ready branches" : "Show \(hiddenCount) more ready branches")
    }

    @ViewBuilder
    private var blockedSection: some View {
        if !blocked.isEmpty {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                CleanupSectionHeader(title: "Blocked", count: blocked.count)
                ForEach(blocked) { unit in
                    blockedRow(unit)
                }
            }
        }
    }

    private func readyRow(_ unit: GitCleanupUnit) -> some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            Toggle(unit.branch.reference.name, isOn: isSelectedBinding(for: unit))
                .toggleStyle(.checkbox)
                .labelsHidden()
            unitNameAndWorktree(unit)
            Spacer(minLength: 0)
            statusBadge(for: unit)
        }
        .padding(.horizontal, WorkbenchMetrics.compactSpacing)
        .padding(.vertical, WorkbenchMetrics.microSpacing)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
    }

    private func blockedRow(_ unit: GitCleanupUnit) -> some View {
        let reason = blockedReason(for: unit)
        return HStack(spacing: WorkbenchMetrics.compactSpacing) {
            Toggle(unit.branch.reference.name, isOn: .constant(false))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(true)
            VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                Text(unit.branch.reference.name)
                    .font(WorkbenchTypography.detail)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(reason)
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            statusBadge(for: unit)
        }
        .padding(.horizontal, WorkbenchMetrics.compactSpacing)
        .padding(.vertical, WorkbenchMetrics.microSpacing)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
        .opacity(0.5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(unit.branch.reference.name), blocked. \(reason)")
    }

    private func unitNameAndWorktree(_ unit: GitCleanupUnit) -> some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
            Text(unit.branch.reference.name)
                .font(WorkbenchTypography.detail)
                .lineLimit(1)
                .truncationMode(.middle)
            if unit.worktree != nil {
                Text("+ worktree")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func statusBadge(for unit: GitCleanupUnit) -> some View {
        if let worktree = unit.worktree {
            CleanupStatusBadgeView(status: worktree.status)
                .fixedSize()
                .layoutPriority(1)
        } else {
            CleanupStatusBadgeView(status: unit.branch.status)
                .fixedSize()
                .layoutPriority(1)
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button(confirmTitle, action: confirm)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canConfirm)
        }
    }

    private var confirmTitle: String {
        requiresRiskReview && !didReviewRisk ? "Review Risk" : "Clean \(selectedUnits.count)"
    }

    private func confirm() {
        guard canConfirm else { return }
        if requiresRiskReview, !didReviewRisk {
            didReviewRisk = true
        } else {
            onConfirm(selectedUnits)
        }
    }

    private func isSelectedBinding(for unit: GitCleanupUnit) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(unit.id) },
            set: { isOn in
                if isOn {
                    selectedIDs.insert(unit.id)
                } else {
                    selectedIDs.remove(unit.id)
                }
            }
        )
    }

    private func blockedReason(for unit: GitCleanupUnit) -> String {
        if unit.isWorktreeOnlyAction, let worktree = unit.worktree {
            return CleanupDetailText.worktreeStatus(worktree.status)
        }
        switch unit.branch.status {
        case .protected, .current, .unknown:
            return CleanupDetailText.branchStatus(unit.branch.status) ?? "Cleanup unavailable."
        default:
            break
        }
        if let worktree = unit.worktree {
            return CleanupDetailText.worktreeStatus(worktree.status)
        }
        return CleanupDetailText.branchStatus(unit.branch.status) ?? "Cleanup unavailable."
    }
}

/// Uppercase, tracked section label with a trailing count; shared with the Projects cleanup sheet.
struct CleanupSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title)
                .textCase(.uppercase)
                .tracking(WorkbenchTypography.tracking(for: WorkbenchTypography.caption))
            Spacer()
            Text("\(count)")
                .monospacedDigit()
        }
        .font(WorkbenchTypography.captionStrong)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(count)")
    }
}

struct CleanupProgressView: View {
    let progress: GitCleanupProgress

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
            HStack {
                Text("Cleaning \(progress.projectName ?? "project")")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(progress.completed) of \(progress.total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(progress.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            ProgressView(value: progress.fractionCompleted)
                .progressViewStyle(.linear)
        }
        .padding(WorkbenchMetrics.compactSpacing)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cleanup progress")
        .accessibilityValue("\(progress.completed) of \(progress.total). \(progress.projectName ?? "Project"). \(progress.detail)")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private func cleanupPreviewUnit(
    _ name: String,
    status: GitBranchCleanupStatus,
    worktree: GitWorktreeCleanupInfo? = nil
) -> GitCleanupUnit {
    GitCleanupUnit(
        repositoryIdentity: "/repo",
        branch: GitBranchCleanupInfo(
            reference: GitBranchReference(name: name, headHash: "1234", isRemote: false),
            status: status,
            worktreePath: worktree?.worktree.path
        ),
        worktree: worktree
    )
}

private func cleanupPreviewWorktree(_ path: String, branch: String, status: GitWorktreeCleanupStatus) -> GitWorktreeCleanupInfo {
    GitWorktreeCleanupInfo(
        worktree: GitWorktreeInfo(path: path, headHash: "1234", branchName: branch, isMainWorktree: false, workingTreeState: .clean),
        status: status
    )
}

#Preview("Cleanup Confirmation") {
    CleanupConfirmationView(
        units: [
            cleanupPreviewUnit("feature/merged", status: .mergedIntoDefault),
            cleanupPreviewUnit(
                "feature/paired",
                status: .checkedOutElsewhere(path: "/tmp/paired"),
                worktree: cleanupPreviewWorktree("/tmp/paired", branch: "feature/paired", status: .eligible)
            ),
            cleanupPreviewUnit("release/unmerged", status: .notMerged)
        ],
        blocked: [
            cleanupPreviewUnit("main", status: .protected),
            cleanupPreviewUnit(
                "feature/dirty",
                status: .notMerged,
                worktree: cleanupPreviewWorktree("/tmp/dirty", branch: "feature/dirty", status: .dirty)
            )
        ],
        onCancel: {},
        onConfirm: { _ in }
    )
}

#Preview("Cleanup Confirmation - Collapsed Ready") {
    CleanupConfirmationView(
        units: (1 ... 8).map { cleanupPreviewUnit("feature/task-\($0)", status: .mergedIntoDefault) },
        blocked: [cleanupPreviewUnit("hotfix/locked", status: .current)],
        onCancel: {},
        onConfirm: { _ in }
    )
}

#Preview("Cleanup Progress") {
    CleanupProgressView(progress: GitCleanupProgress(
        completed: 12,
        total: 40,
        projectName: "Example Project",
        detail: "Removing worktree /tmp/example-feature"
    ))
    .frame(width: 460)
}
