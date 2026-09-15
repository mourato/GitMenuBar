import Foundation

@Observable
@MainActor
final class MainMenuCommandPaletteState {
    var isPresented = false
    var query = ""
    var selectedItemID: String?
    private(set) var lastHandledToken = 0

    func open(defaultSelectionID: String?) {
        query = ""
        selectedItemID = defaultSelectionID
        isPresented = true
    }

    func close() {
        isPresented = false
        query = ""
        selectedItemID = nil
    }

    /// Claims a presentation token. Returns false when the token was already handled.
    func claimPresentationRequest(_ token: Int) -> Bool {
        guard token > lastHandledToken else {
            return false
        }

        lastHandledToken = token
        return true
    }
}
