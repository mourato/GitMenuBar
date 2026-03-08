import AppKit

final class DirectoryPickerService {
    func selectDirectory(
        title: String = "Select Git Repository",
        prompt: String = "Choose",
        activateApp: Bool = false,
        preparePanel: ((NSOpenPanel) -> Void)? = nil,
        completion: @escaping (String?) -> Void
    ) {
        if activateApp {
            NSApp.activate(ignoringOtherApps: true)
        }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.title = title
        panel.prompt = prompt
        panel.worksWhenModal = false
        preparePanel?(panel)

        DispatchQueue.main.async {
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        }

        panel.begin { result in
            completion(result == .OK ? panel.url?.path : nil)
        }
    }
}
