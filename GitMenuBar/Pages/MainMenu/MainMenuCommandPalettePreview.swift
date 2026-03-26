import SwiftUI

private struct MainMenuCommandPalettePreviewContainer: View {
    @State private var query = ""
    @State private var selectedItemID: String?

    private let items = [
        MainMenuCommandPaletteItem(
            kind: .commit,
            section: .actions,
            title: "Commit",
            subtitle: "Generate an automatic commit message",
            keywords: ["git", "commit"],
            isEnabled: true
        ),
        MainMenuCommandPaletteItem(
            kind: .commitAndPush,
            section: .actions,
            title: "Commit & Push",
            subtitle: "Create a commit and push to remote",
            keywords: ["git", "push"],
            isEnabled: true
        ),
        MainMenuCommandPaletteItem(
            kind: .recentProject(path: "/Users/usuario/Documents/Projects/gitmenubar"),
            section: .recentProjects,
            title: "gitmenubar",
            subtitle: "~/Documents/Projects/gitmenubar",
            keywords: ["project"],
            isEnabled: true
        ),
        MainMenuCommandPaletteItem(
            kind: .restartApp,
            section: .app,
            title: "Restart App",
            subtitle: "Relaunch GitMenuBar",
            keywords: ["restart"],
            isEnabled: true
        )
    ]

    var body: some View {
        MainMenuCommandPaletteView(
            query: $query,
            items: MainMenuCommandPaletteResolver.filteredItems(from: items, query: query),
            selectedItemID: $selectedItemID,
            onClose: {},
            onSelectItem: { _ in }
        )
        .padding(24)
        .background(Color.black.opacity(0.08))
    }
}

#Preview("Command Palette") {
    MainMenuCommandPalettePreviewContainer()
}
