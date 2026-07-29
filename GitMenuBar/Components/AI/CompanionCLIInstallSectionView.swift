import AppKit
import SwiftUI

struct CompanionCLIInstallSectionView: View {
    @State private var statusMessage: String?
    @State private var isError = false
    @State private var isInstalling = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(isInstalling ? "Installing" : "Install CLI") {
                installCLI()
            }
            .disabled(isInstalling)
            .buttonStyle(.borderless)

            Text(
                "Installs gitmenubar to ~/.local/bin for agents on your PATH. " +
                    "Use Propose mode by default; apply commits only when asked. " +
                    "Add ~/.local/bin to PATH if needed."
            )
            .font(WorkbenchTypography.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if let statusMessage {
                Text(statusMessage)
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(isError ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func installCLI() {
        isInstalling = true
        statusMessage = nil
        isError = false

        defer { isInstalling = false }

        do {
            let result = try CompanionCLIInstaller.install()
            switch result {
            case let .installed(destination, source):
                statusMessage = "Installed \(destination.path) → \(source.path)"
                presentSuccessAlert(destination: destination)
            case let .alreadyInstalled(destination, _):
                statusMessage = "CLI already installed at \(destination.path)"
            }
        } catch {
            statusMessage = error.localizedDescription
            isError = true
        }
    }

    private func presentSuccessAlert(destination: URL) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Companion CLI Installed"
        alert.informativeText =
            "gitmenubar is linked at \(destination.path). Ensure ~/.local/bin is on your PATH."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

#Preview {
    Form {
        Section {
            CompanionCLIInstallSectionView()
        } header: {
            SettingsFormSectionHeader(title: "Companion CLI", icon: "terminal")
        }
    }
    .formStyle(.grouped)
    .frame(width: 560, height: 180)
}
