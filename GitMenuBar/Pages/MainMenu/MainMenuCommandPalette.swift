import AppKit
import SwiftUI

enum MainMenuCommandPaletteSection: String, CaseIterable {
    case actions
    case recentProjects
    case app

    var title: String {
        switch self {
        case .actions:
            return "Actions"
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

enum MainMenuCommandPaletteResolver {
    static func resolveItems(
        actionState: StatusBarContextMenuActionState,
        syncActionTitle: String,
        recentPaths: [String],
        currentRepoPath: String
    ) -> [MainMenuCommandPaletteItem] {
        var items: [MainMenuCommandPaletteItem] = []

        if actionState.showsCommit {
            items.append(
                MainMenuCommandPaletteItem(
                    kind: .commit,
                    section: .actions,
                    title: "Commit",
                    subtitle: "Generate an automatic commit message",
                    keywords: ["git", "commit", "working tree"],
                    isEnabled: actionState.canCommit
                )
            )
        }

        if actionState.showsCommitAndPush {
            items.append(
                MainMenuCommandPaletteItem(
                    kind: .commitAndPush,
                    section: .actions,
                    title: "Commit & Push",
                    subtitle: "Create a commit and push to remote",
                    keywords: ["git", "commit", "push", "remote"],
                    isEnabled: actionState.canCommitAndPush
                )
            )
        }

        if actionState.showsSync {
            items.append(
                MainMenuCommandPaletteItem(
                    kind: .sync,
                    section: .actions,
                    title: syncActionTitle,
                    subtitle: "Synchronize local and remote branches",
                    keywords: ["git", "sync", "pull", "push"],
                    isEnabled: actionState.canSync
                )
            )
        }

        for path in recentPaths.filter({ $0 != currentRepoPath }).prefix(5) {
            items.append(
                MainMenuCommandPaletteItem(
                    kind: .recentProject(path: path),
                    section: .recentProjects,
                    title: PathDisplayFormatter.projectName(from: path),
                    subtitle: PathDisplayFormatter.abbreviatedPath(path),
                    keywords: ["project", "switch", path],
                    isEnabled: true
                )
            )
        }

        items.append(
            MainMenuCommandPaletteItem(
                kind: .restartApp,
                section: .app,
                title: "Restart App",
                subtitle: "Relaunch GitMenuBar",
                keywords: ["restart", "relaunch", "app"],
                isEnabled: true
            )
        )

        items.append(
            MainMenuCommandPaletteItem(
                kind: .quitApp,
                section: .app,
                title: "Quit App",
                subtitle: "Close GitMenuBar",
                keywords: ["quit", "close", "app"],
                isEnabled: true
            )
        )

        return items
    }

    static func filteredItems(from items: [MainMenuCommandPaletteItem], query: String) -> [MainMenuCommandPaletteItem] {
        items.filter { $0.matches(query: query) }
    }

    static func defaultSelectionID(for items: [MainMenuCommandPaletteItem]) -> String? {
        if let firstEnabled = items.first(where: { $0.isEnabled }) {
            return firstEnabled.id
        }

        return items.first?.id
    }

    static func nextSelectionID(
        currentID: String?,
        items: [MainMenuCommandPaletteItem],
        direction: Int
    ) -> String? {
        guard !items.isEmpty else {
            return nil
        }

        guard let currentID,
              let currentIndex = items.firstIndex(where: { $0.id == currentID })
        else {
            return defaultSelectionID(for: items)
        }

        let normalizedDirection = direction >= 0 ? 1 : -1
        let nextIndex = (currentIndex + normalizedDirection + items.count) % items.count
        return items[nextIndex].id
    }

    static func executionDecision(for kind: MainMenuCommandPaletteKind) -> MainMenuCommandPaletteExecutionDecision {
        switch kind {
        case .restartApp:
            return .requiresConfirmation
        default:
            return .executeNow
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search commands", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
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
        .padding(14)
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 20, x: 0, y: 10)
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
                .font(.system(size: 13, weight: .semibold))
            Text("Try another query.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionView(section: MainMenuCommandPaletteSection, items: [MainMenuCommandPaletteItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.title)
                .font(.system(size: 11, weight: .semibold))
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
            }
        }
    }

    private func row(for item: MainMenuCommandPaletteItem) -> some View {
        let isSelected = selectedItemID == item.id

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(item.isEnabled ? .primary : .secondary)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func synchronizeSelectionWithVisibleItems() {
        guard !items.isEmpty else {
            selectedItemID = nil
            return
        }

        let selectionStillVisible = selectedItemID.map { id in
            items.contains(where: { $0.id == id })
        } ?? false
        if selectionStillVisible {
            return
        }

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
        let selectedItem = selectedItemID.flatMap { id in
            items.first(where: { $0.id == id })
        }
        if let selectedItem {
            return selectedItem
        }

        return items.first
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

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // Escape
            onClose()
            return true
        case 125: // Down
            selectedItemID = MainMenuCommandPaletteResolver.nextSelectionID(
                currentID: selectedItemID,
                items: items,
                direction: 1
            )
            return true
        case 126: // Up
            selectedItemID = MainMenuCommandPaletteResolver.nextSelectionID(
                currentID: selectedItemID,
                items: items,
                direction: -1
            )
            return true
        case 36, 76: // Return, Enter
            executeSelectedOrFirstVisibleItem()
            return true
        default:
            return false
        }
    }
}
