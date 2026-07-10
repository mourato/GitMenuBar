import AppKit
import SwiftUI

enum MainMenuCommandPaletteSection: String, CaseIterable {
    case actions
    case branches
    case recentProjects
    case app

    var title: String {
        switch self {
        case .actions:
            return "Actions"
        case .branches:
            return "Branches"
        case .recentProjects:
            return "Recent Projects"
        case .app:
            return "App"
        }
    }
}

enum MainMenuCommandPaletteKind: Hashable {
    case commit
    case commitAndPush
    case sync
    case atomicCommits
    case push
    case pull
    case branchManagement
    case createBranch
    case mergeToDefault(featureBranch: String)
    case switchToBranchList
    case switchBranch(branchName: String)
    case recentProject(path: String)
    case restartApp
    case quitApp

    var stableID: String {
        switch self {
        case .commit:
            return "action.commit"
        case .commitAndPush:
            return "action.commitAndPush"
        case .sync:
            return "action.sync"
        case .atomicCommits:
            return "action.atomicCommits"
        case .push:
            return "action.push"
        case .pull:
            return "action.pull"
        case .branchManagement:
            return "branch.management"
        case .createBranch:
            return "branch.create"
        case .mergeToDefault:
            return "branch.mergeToDefault"
        case .switchToBranchList:
            return "branch.switchToBranchList"
        case let .switchBranch(branchName):
            return "branch.switch.\(branchName)"
        case let .recentProject(path):
            return "recent.\(path)"
        case .restartApp:
            return "app.restart"
        case .quitApp:
            return "app.quit"
        }
    }
}

enum MainMenuCommandPaletteExecutionDecision: Equatable {
    case executeNow
    case requiresConfirmation
}

struct MainMenuCommandPaletteItem: Identifiable, Equatable {
    let kind: MainMenuCommandPaletteKind
    let section: MainMenuCommandPaletteSection
    let title: String
    let subtitle: String?
    let keywords: [String]
    let isEnabled: Bool

    var id: String {
        kind.stableID
    }

    func matches(query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return true
        }

        if title.lowercased().contains(normalizedQuery) {
            return true
        }

        if let subtitle, subtitle.lowercased().contains(normalizedQuery) {
            return true
        }

        return keywords.contains { $0.lowercased().contains(normalizedQuery) }
    }
}

struct MainMenuCommandPaletteView: View {
    @Binding var query: String
    let items: [MainMenuCommandPaletteItem]
    @Binding var selectedItemID: String?
    let onClose: () -> Void
    let onSelectItem: (MainMenuCommandPaletteItem) -> Void

    @FocusState private var isSearchFieldFocused: Bool
    @State private var localKeyEventMonitor: Any?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: MacChromeMetrics.sectionSpacing) {
            TextField("Search commands", text: $query)
                .textFieldStyle(.roundedBorder)
                .font(MacChromeTypography.field)
                .focused($isSearchFieldFocused)
                .onSubmit {
                    executeSelectedOrFirstVisibleItem()
                }

            if items.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(MainMenuCommandPaletteSection.allCases, id: \.self) { section in
                                let sectionItems = items.filter { $0.section == section }
                                if !sectionItems.isEmpty {
                                    sectionView(section: section, items: sectionItems)
                                }
                            }
                        }
                        .padding(.bottom, 2)
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: 330)
                    .onAppear {
                        scrollSelectionIntoView(using: proxy, animated: false)
                    }
                    .onChange(of: selectedItemID) { _ in
                        scrollSelectionIntoView(using: proxy, animated: true)
                    }
                }
            }
        }
        .padding(MacChromeMetrics.panelPadding)
        .frame(width: 360)
        .background(backgroundStyle)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 16, x: 0, y: 8)
        .onAppear {
            selectedItemID = MainMenuCommandPaletteResolver.defaultSelectionID(for: items)
            isSearchFieldFocused = true
            installLocalKeyMonitor()
        }
        .onDisappear {
            removeLocalKeyMonitor()
        }
        .onChange(of: items.map(\.id)) { _ in
            synchronizeSelectionWithVisibleItems()
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No matching commands")
                .font(MacChromeTypography.sectionLabel)
            Text("Try another query.")
                .font(MacChromeTypography.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var backgroundStyle: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        }
    }

    private func sectionView(section: MainMenuCommandPaletteSection, items: [MainMenuCommandPaletteItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.title)
                .font(MacChromeTypography.captionStrong)
                .foregroundColor(.secondary)

            ForEach(items) { item in
                Button {
                    selectedItemID = item.id
                    execute(item)
                } label: {
                    row(for: item)
                }
                .id(item.id)
                .buttonStyle(.plain)
                .disabled(!item.isEnabled)
                .accessibilityLabel(item.title)
            }
        }
    }

    private func row(for item: MainMenuCommandPaletteItem) -> some View {
        let isSelected = selectedItemID == item.id

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(MacChromeTypography.body)
                    .foregroundColor(item.isEnabled ? .primary : .secondary)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(MacChromeTypography.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: MacChromeMetrics.rowCornerRadius, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: MacChromeMetrics.rowCornerRadius, style: .continuous))
    }

    private func synchronizeSelectionWithVisibleItems() {
        selectedItemID = MainMenuCommandPaletteResolver.defaultSelectionID(for: items)
    }

    private func scrollSelectionIntoView(using proxy: ScrollViewProxy, animated: Bool) {
        guard let selectedItemID else {
            return
        }

        let targetID = selectedItemID
        let performScroll = {
            proxy.scrollTo(targetID, anchor: .center)
        }

        if animated {
            if reduceMotion {
                DispatchQueue.main.async {
                    performScroll()
                }
                return
            }

            // SwiftUI ScrollView.scrollTo can miss the target on the first
            // attempt when the layout hasn't settled yet. The second scroll
            // without animation ensures the item is visible even if the first
            // animation-targeted scroll lands at the wrong offset.
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.15)) {
                    performScroll()
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                performScroll()
            }
            return
        }

        DispatchQueue.main.async {
            performScroll()
        }
    }

    private func execute(_ item: MainMenuCommandPaletteItem) {
        guard item.isEnabled else {
            NSSound.beep()
            return
        }

        onSelectItem(item)
    }

    private func executeSelectedOrFirstVisibleItem() {
        guard let item = resolveItemToExecuteOnEnter() else {
            NSSound.beep()
            return
        }

        selectedItemID = item.id
        execute(item)
    }

    private func resolveItemToExecuteOnEnter() -> MainMenuCommandPaletteItem? {
        selectedItemID.flatMap { id in
            items.first(where: { $0.id == id })
        }
    }

    private func installLocalKeyMonitor() {
        guard localKeyEventMonitor == nil else {
            return
        }

        localKeyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyEvent(event) ? nil : event
        }
    }

    private func removeLocalKeyMonitor() {
        guard let localKeyEventMonitor else {
            return
        }

        NSEvent.removeMonitor(localKeyEventMonitor)
        self.localKeyEventMonitor = nil
    }

    private enum KeyCode: UInt16 {
        case escape = 53
        case downArrow = 125
        case upArrow = 126
        case `return` = 36
        case enter = 76
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard let keyCode = KeyCode(rawValue: event.keyCode) else {
            return false
        }

        switch keyCode {
        case .escape:
            onClose()
        case .downArrow:
            selectedItemID = MainMenuCommandPaletteResolver.nextSelectionID(
                currentID: selectedItemID,
                items: items,
                direction: 1
            )
        case .upArrow:
            selectedItemID = MainMenuCommandPaletteResolver.nextSelectionID(
                currentID: selectedItemID,
                items: items,
                direction: -1
            )
        case .return, .enter:
            executeSelectedOrFirstVisibleItem()
        }

        return true
    }
}
